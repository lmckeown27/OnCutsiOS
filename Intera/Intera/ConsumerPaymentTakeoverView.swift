//
//  ConsumerPaymentTakeoverView.swift
//  Intera
//
//  Full-screen payment when the provider marks the booking complete (COMPLETED).
//  Stripe PaymentSheet + `bookings-simple` create/confirm endpoints (same pipeline as the web app).
//

import SwiftUI
#if os(iOS)
import Core
import PassKit
import UIKit
#endif

#if os(iOS)
/// Past row kerning is 2.2pt; +15% tracking for the service title on this screen.
private let paymentServiceTitleKerning: CGFloat = 2.2 * 1.15

/// Primary online payment CTAs (Apple Pay + Card).
private let paymentPrimaryActionLabelFont = InteraFont.system(size: 19, weight: .bold, design: .default)
private let paymentCashActionLabelFont = InteraFont.system(size: 16, weight: .semibold, design: .default)

private enum PaymentMethodButtonMetrics {
    static let primaryHeight: CGFloat = 58
    static let primaryCornerRadius: CGFloat = 14
    static let cashVerticalPadding: CGFloat = 11
    static let cashCornerRadius: CGFloat = 12
}

/// Percentage tip options; none selected until the user taps (tap again to clear).
private enum TipPreset: Int, CaseIterable {
    case fifteen
    case twenty
    case twentyFive

    var label: String {
        switch self {
        case .fifteen: return "15%"
        case .twenty: return "20%"
        case .twentyFive: return "25%"
        }
    }

    func tipCents(priceCents: Int) -> Int {
        switch self {
        case .fifteen: return Int((Double(priceCents) * 0.15).rounded())
        case .twenty: return Int((Double(priceCents) * 0.20).rounded())
        case .twentyFive: return Int((Double(priceCents) * 0.25).rounded())
        }
    }
}

/// System Apple Pay affordance (required for App Store / HIG when offering Apple Pay).
private struct PaymentApplePayButton: UIViewRepresentable {
    var isEnabled: Bool
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    private static func applePayButtonStyle() -> PKPaymentButtonStyle {
        #if canImport(UIKit)
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
        return dark ? .whiteOutline : .black
        #else
        return .black
        #endif
    }

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .plain, paymentButtonStyle: Self.applePayButtonStyle())
        button.cornerRadius = PaymentMethodButtonMetrics.primaryCornerRadius
        button.addTarget(context.coordinator, action: #selector(Coordinator.touchUp), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        context.coordinator.action = action
        uiView.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }

        @objc func touchUp() {
            action()
        }
    }
}

struct ConsumerPaymentTakeoverView: View {
    let payload: BookingPaymentRequestPayload
    let sessionManager: AppSessionManager

    @EnvironmentObject private var chatViewModel: ChatViewModel

    @StateObject private var checkout: CheckoutViewModel

    @State private var phase: PaymentPhase = .loading
    @State private var tipAmountCents: Int
    @State private var selectedTipPreset: TipPreset?
    @State private var bannerError: String?
    @State private var isPaying = false
    @State private var isStartingApplePay = false
    @State private var isConfirmingCash = false
    @State private var showCashPaymentConfirm = false
    /// Filled via `GET /bookings-simple/:id` when the socket payload omitted `barberAvatar` (e.g. older servers).
    @State private var enrichedBarberAvatarURL: String?
    /// Publishable key chosen in `configureStripeIfPossible` (server client-config or plist); reapplied at pay time so the SDK cannot drift from a stale value.
    @State private var validatedPublishableKeyForCheckout: String = ""

    private enum PaymentPhase: Equatable {
        case loading
        case ready
        case misconfigured(String)
    }

    init(payload: BookingPaymentRequestPayload, sessionManager: AppSessionManager) {
        self.payload = payload
        self.sessionManager = sessionManager
        _tipAmountCents = State(initialValue: 0)
        _selectedTipPreset = State(initialValue: nil)
        _checkout = StateObject(
            wrappedValue: CheckoutViewModel(
                merchantDisplayName: "CampusCuts",
                stripeReturnURL: "campuscuts://stripe-redirect"
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                InteraLavaLampBackground()

                ScrollView {
                    VStack(spacing: 0) {
                        switch phase {
                        case .loading:
                            loadingBlock
                        case .misconfigured(let message):
                            misconfiguredBlock(message: message)
                        case .ready:
                            readyBlock
                        }
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                }
            }
            .navigationTitle("Pay for service")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Color.interaShellBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Pay later") {
                        chatViewModel.dismissPaymentTakeoverForLater()
                    }
                    .font(InteraFont.body.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCream)
                }
            }
        }
        .task {
            await configureStripeIfPossible()
            await enrichBookingMetadataIfNeeded()
        }
        .onChange(of: checkout.destination) { _, new in
            // Defer mutations: Stripe’s sheet can publish `CheckoutDestination` during SwiftUI’s update pass;
            // assigning `@State` / `ObservableObject` here synchronously triggers “Modifying state during view update”.
            Task { @MainActor in
                switch new {
                case .success:
                    await confirmAfterCheckoutSuccess()
                case .failed(let message):
                    bannerError = message
                    checkout.resetNavigation()
                case .idle:
                    break
                }
            }
        }
        .alert("Confirm Cash Payment?", isPresented: $showCashPaymentConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                Task { await completeCashPayment() }
            }
        } message: {
            Text("Please ensure you have paid your barber in person.")
        }
    }

    private var loadingBlock: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(Color.lavaShellCream)
            Text("Loading checkout…")
                .font(InteraFont.subheadline)
                .foregroundStyle(Color.lavaShellCreamSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func misconfiguredBlock(message: String) -> some View {
        VStack(spacing: 24) {
            paymentGlassCard {
                Text(message)
                    .font(InteraFont.subheadline)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Normalizes app-relative or absolute avatar strings so `AsyncImage` loads reliably.
    private var resolvedBarberAvatarURLString: String? {
        let raw = enrichedBarberAvatarURL ?? payload.barberAvatarURL
        return ProfileImageURLResolver.url(from: raw)?.absoluteString
    }

    private var displayBarberName: String {
        let t = payload.barberName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Your barber" : t
    }

    private static let paymentAvatarCorner: CGFloat = 12

    /// `StripeApplePayMerchantId` in Info.plist — when missing, only Card + Cash are offered.
    private var isApplePayConfigured: Bool {
        guard let mid = Bundle.StripeConfig.applePayMerchantId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mid.isEmpty,
              !mid.contains("$(")
        else { return false }
        return true
    }

    private var readyBlock: some View {
        VStack(spacing: 0) {
            paymentGlassCard {
                VStack(spacing: 40) {
                    VStack(spacing: 12) {
                        AvatarView(
                            imageUrl: resolvedBarberAvatarURLString,
                            name: displayBarberName,
                            size: 112,
                            fontSize: 38,
                            clipStyle: .square(cornerRadius: Self.paymentAvatarCorner)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Self.paymentAvatarCorner, style: .continuous)
                                .stroke(Color.interaShellGlassStroke, lineWidth: 1)
                        )

                        Text(displayBarberName)
                            .font(InteraFont.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(Color.lavaShellCream)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: 260)

                        Text(payload.displayServiceName)
                            .font(InteraFont.system(size: 14, weight: .medium, design: .default))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .kerning(paymentServiceTitleKerning)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .frame(maxWidth: 280)
                    }

                    Text(payload.priceFormatted)
                        .font(InteraFont.system(size: 36, weight: .bold, design: .default))
                        .foregroundStyle(Color.lavaShellCream)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .center, spacing: 14) {
                        Text("Tip")
                            .font(InteraFont.caption.weight(.semibold))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                            .textCase(.uppercase)
                            .tracking(1.2)

                        tipPillRow
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 20) {
                        Text(isApplePayConfigured ? "Pay online with Apple Pay or your card." : "Pay online with your card.")
                            .font(InteraFont.subheadline)
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 10) {
                            if isApplePayConfigured {
                                applePayPrimaryButton
                                paymentMethodOrDivider
                            }

                            cardPrimaryButton
                        }

                        paymentCashPreferenceHint
                            .padding(.top, 4)

                        cashSecondaryButton

                        if let bannerError {
                            Text(bannerError)
                                .font(InteraFont.caption)
                                .foregroundStyle(Color.red.opacity(0.92))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
        }
    }

    private var paymentMethodOrDivider: some View {
        Text("or")
            .font(InteraFont.subheadline.weight(.semibold))
            .foregroundStyle(Color.lavaShellCreamTertiary)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("or")
    }

    private var paymentCashPreferenceHint: some View {
        (
            Text("If you prefer to pay with cash, select the ")
                + Text("Cash").fontWeight(.semibold)
                + Text(" option below.")
        )
        .font(InteraFont.footnote)
        .foregroundStyle(Color.lavaShellCreamTertiary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var applePayPrimaryButton: some View {
        ZStack {
            if isStartingApplePay {
                RoundedRectangle(cornerRadius: PaymentMethodButtonMetrics.primaryCornerRadius, style: .continuous)
                    .fill(Color.lavaShellCream.opacity(0.22))
                    .frame(maxWidth: .infinity)
                    .frame(height: PaymentMethodButtonMetrics.primaryHeight)
                ProgressView()
                    .tint(Color.lavaShellCream)
            } else {
                PaymentApplePayButton(
                    isEnabled: !isPaying && !isConfirmingCash,
                    action: { presentStandaloneApplePayCheckout() }
                )
                .frame(maxWidth: .infinity)
                .frame(height: PaymentMethodButtonMetrics.primaryHeight)
                .clipShape(RoundedRectangle(cornerRadius: PaymentMethodButtonMetrics.primaryCornerRadius, style: .continuous))
            }
        }
    }

    private var cardPrimaryButton: some View {
        Button {
            presentStripePaymentSheet()
        } label: {
            HStack(spacing: 12) {
                if isPaying {
                    ProgressView()
                        .tint(Color.paymentFilledButtonLabel)
                } else {
                    Image(systemName: "creditcard.fill")
                        .font(InteraFont.title3.weight(.semibold))
                        .foregroundStyle(Color.paymentFilledButtonLabel)
                }
                Text(isPaying ? "Opening…" : "Card")
                    .font(paymentPrimaryActionLabelFont)
                    .foregroundStyle(Color.paymentFilledButtonLabel)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: PaymentMethodButtonMetrics.primaryHeight)
            .background(Color.paymentFilledButtonFill)
            .clipShape(RoundedRectangle(cornerRadius: PaymentMethodButtonMetrics.primaryCornerRadius, style: .continuous))
        }
        .disabled(isPaying || isConfirmingCash || isStartingApplePay)
        .buttonStyle(BookButtonStyle())
    }

    private var cashSecondaryButton: some View {
        Button {
            showCashPaymentConfirm = true
        } label: {
            HStack(spacing: 8) {
                if isConfirmingCash {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.paymentOutlineButtonLabel)
                } else {
                    Image(systemName: "banknote")
                        .font(InteraFont.subheadline.weight(.semibold))
                }
                Text(isConfirmingCash ? "Completing…" : "Cash")
                    .font(paymentCashActionLabelFont)
            }
            .foregroundStyle(Color.paymentOutlineButtonLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, PaymentMethodButtonMetrics.cashVerticalPadding)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: PaymentMethodButtonMetrics.cashCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PaymentMethodButtonMetrics.cashCornerRadius, style: .continuous)
                    .stroke(Color.paymentOutlineButtonLabel, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: PaymentMethodButtonMetrics.cashCornerRadius, style: .continuous))
        }
        .disabled(isConfirmingCash || isPaying || isStartingApplePay)
        .buttonStyle(BookButtonStyle())
    }

    private var tipPillRow: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                ForEach(TipPreset.allCases, id: \.self) { preset in
                    tipPill(preset)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func tipPill(_ preset: TipPreset) -> some View {
        let selected = selectedTipPreset == preset
        return Button {
            if selected {
                selectedTipPreset = nil
                tipAmountCents = 0
            } else {
                BookingSelectorTheme.triggerSelectionChangedIfNewSelection(wasSelected: false)
                selectedTipPreset = preset
                tipAmountCents = preset.tipCents(priceCents: payload.priceCents)
            }
        } label: {
            Text(preset.label)
                .font(InteraFont.subheadline.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Color.paymentTipSelectedLabel : Color.paymentOutlineButtonLabel)
                .padding(.horizontal, selected ? 18 : 16)
                .padding(.vertical, selected ? 12 : 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? Color.paymentTipSelectedFill : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            selected ? Color.paymentTipSelectedFill : Color.paymentTipUnselectedStroke,
                            lineWidth: selected ? 2.5 : 1.25
                        )
                )
                .shadow(color: selected ? Color.paymentTipSelectedFill.opacity(0.45) : .clear, radius: 8, y: 2)
                .scaleEffect(selected ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(BookingSelectorTheme.selectionSpring, value: selected)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Frosted panel: strong material blur + 15% white wash (service summary and actions).
    private func paymentGlassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.thickMaterial)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.paymentGlassWash)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.interaShellGlassStroke, lineWidth: 1)
            )
    }

    @MainActor
    private func enrichBookingMetadataIfNeeded() async {
        guard enrichedBarberAvatarURL == nil else { return }
        let trimmed = payload.barberAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty else { return }
        guard let token = sessionManager.currentSession?.token.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return }
        if let url = await ConsumerBookingsSimpleAPI.resolveBarberAvatarURL(
            bookingId: payload.bookingId,
            bearerToken: token
        ) {
            enrichedBarberAvatarURL = url
        }
    }

    @MainActor
    private func configureStripeIfPossible() async {
        phase = .loading
        validatedPublishableKeyForCheckout = ""
        let fromPlist = AppConfiguration.stripePublishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let fetchedServer = await ConsumerStripeClientConfigAPI.fetchPublishableKeyIfAvailable(
            apiBaseURLTrimmed: AppConfiguration.messagingAPIRootTrimmed
        )
        let serverTrimmed = fetchedServer?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Production API + live PaymentIntents must not use a test publishable key. If client-config
        // is mis-set to pk_test while the bundle has pk_live, preferring server would cause 404/400 on PI + Elements.
        let fromServer: String? = {
            guard let s = serverTrimmed, s.hasPrefix("pk_") else { return nil }
            if Self.hostsProductionCampusCutsAPI, s.hasPrefix("pk_test") {
                #if DEBUG
                print("Stripe: ignoring pk_test from client-config on production API host; using Info.plist if present.")
                #endif
                return nil
            }
            return s
        }()
        let pk = fromServer ?? fromPlist
        guard pk.hasPrefix("pk_"), !pk.contains("REPLACE"), !pk.contains("NOT_CONFIGURED") else {
            phase = .misconfigured(stripeMisconfiguredHint(actualValue: pk))
            return
        }
        if Self.hostsProductionCampusCutsAPI, pk.hasPrefix("pk_test") {
            phase = .misconfigured(
                "This build uses a Stripe test publishable key (pk_test…) while the app is pointed at the production CampusCuts API. " +
                    "Live PaymentIntents return 404 in that setup. Set STRIPE_PUBLISHABLE_KEY = pk_live… on the server (GET /api/v1/stripe/client-config) and/or in `Config/StripeKeys.xcconfig`, then Product → Clean Build Folder."
            )
            return
        }
        // Do not call `configureFromAppBundle()` here: it would briefly apply Info.plist and can disagree with `pk` from client-config.
        StripeService.setPublishableKey(pk)
        validatedPublishableKeyForCheckout = pk
        phase = .ready
    }

    /// `true` when API root is production — Stripe mode must match live server PaymentIntents.
    private static var hostsProductionCampusCutsAPI: Bool {
        AppConfiguration.messagingAPIRootTrimmed.lowercased().contains("campuscut.com")
    }

    /// Explains common xcconfig / Info.plist mistakes (key must be `STRIPE_PUBLISHABLE_KEY` in a local xcconfig, then clean build).
    private func stripeMisconfiguredHint(actualValue: String) -> String {
        if actualValue.isEmpty {
            return "No Stripe publishable key in the app Info.plist and none from GET /api/v1/stripe/client-config. Set STRIPE_PUBLISHABLE_KEY in `Config/StripeKeys.xcconfig` (and on the API host’s environment for client-config), then Product → Clean Build Folder and run again."
        }
        return "The app still has a placeholder Stripe key (or invalid value). For production payments set STRIPE_PUBLISHABLE_KEY = pk_live_… in `Config/StripeKeys.xcconfig` and on the server so client-config matches your Stripe secret mode, then Clean Build Folder."
    }

    /// Loads PaymentIntent params (including optional Connect `stripeAccountId`), configures PaymentSheet with 3DS return URL, and presents the sheet.
    private func presentStripePaymentSheet() {
        bannerError = nil
        isPaying = true
        checkout.resetNavigation()
        Task { @MainActor in
            do {
                let config = try await checkout.fetchPaymentParams(
                    bookingID: payload.bookingId,
                    stripeAccountID: payload.barberStripeAccountId,
                    tipAmountCents: tipAmountCents,
                    bearerToken: sessionManager.currentSession?.token,
                    apiBaseURLTrimmed: AppConfiguration.messagingAPIRootTrimmed,
                    publishableKeyValidatedByHost: validatedPublishableKeyForCheckout.isEmpty
                        ? nil
                        : validatedPublishableKeyForCheckout,
                    paymentSheetIncludesApplePay: false
                )
                guard let presenter = UIApplication.shared.interaPresentationRootViewController else {
                    isPaying = false
                    bannerError = "Couldn’t open the payment sheet. Close this screen and try again."
                    return
                }
                checkout.presentPaymentSheet(from: presenter, paymentConfig: config)
                isPaying = false
            } catch {
                isPaying = false
                bannerError = error.localizedDescription
            }
        }
    }

    private func presentStandaloneApplePayCheckout() {
        bannerError = nil
        isStartingApplePay = true
        checkout.resetNavigation()
        Task { @MainActor in
            do {
                let config = try await checkout.fetchPaymentParams(
                    bookingID: payload.bookingId,
                    stripeAccountID: payload.barberStripeAccountId,
                    tipAmountCents: tipAmountCents,
                    bearerToken: sessionManager.currentSession?.token,
                    apiBaseURLTrimmed: AppConfiguration.messagingAPIRootTrimmed,
                    publishableKeyValidatedByHost: validatedPublishableKeyForCheckout.isEmpty
                        ? nil
                        : validatedPublishableKeyForCheckout,
                    paymentSheetIncludesApplePay: false
                )
                let window = UIApplication.shared.interaKeyWindow
                let started = checkout.presentStandaloneApplePay(
                    from: window,
                    paymentConfig: config,
                    serviceCents: payload.priceCents,
                    tipCents: tipAmountCents
                )
                isStartingApplePay = false
                if !started {
                    bannerError = "Apple Pay isn’t available on this device or couldn’t be started. Try Card instead."
                }
            } catch {
                isStartingApplePay = false
                bannerError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func confirmAfterCheckoutSuccess() async {
        guard let pi = checkout.lastCompletedPaymentIntentId else {
            bannerError = "Couldn’t confirm with the server (missing payment reference). Try paying again."
            checkout.resetNavigation()
            return
        }
        await confirmAndRefresh(paymentIntentId: pi)
        checkout.resetNavigation()
    }

    @MainActor
    private func confirmAndRefresh(paymentIntentId: String) async {
        do {
            try await BookingSimplePaymentAPI.confirmPayment(
                bookingId: payload.bookingId,
                paymentIntentId: paymentIntentId,
                tipAmountCents: tipAmountCents,
                bearerToken: sessionManager.currentSession?.token
            )
            await Task.yield()
            // Home + cleared stacks under the modals so dismiss/review never reveals Bookings/detail (stale paid state).
            NotificationCenter.default.post(name: .interaNavigateToConsumerHomeAfterPayment, object: nil)
            await Task.yield()
            // Snapshot before `clearPaymentTakeover()` — dismissing the cover can tear down this view and reset `@State`,
            // so `enrichedBarberAvatarURL` would be lost and review would only get `payload.barberAvatarURL` (often nil).
            let barberAvatarForReview = enrichedBarberAvatarURL ?? payload.barberAvatarURL
            chatViewModel.clearPaymentTakeover()
            await Task.yield()
            // Refresh *before* presenting review so `@Published` booking updates don’t cancel the review view’s `.task`
            // mid-flight (which prevented avatar `resolveBarberAvatarURL` from completing).
            await chatViewModel.refreshConsumerBookingsAndSyncPayment(sessionManager: sessionManager)
            await Task.yield()
            chatViewModel.beginPostPaymentReview(from: payload, barberAvatarURLOverride: barberAvatarForReview)
        } catch {
            bannerError = "Payment went through, but confirmation failed: \(error.localizedDescription)"
            await chatViewModel.refreshConsumerBookingsAndSyncPayment(sessionManager: sessionManager)
        }
    }

    @MainActor
    private func completeCashPayment() async {
        bannerError = nil
        isConfirmingCash = true
        do {
            try await BookingSimplePaymentAPI.payWithCash(
                bookingId: payload.bookingId,
                tipAmountCents: tipAmountCents,
                bearerToken: sessionManager.currentSession?.token
            )
            isConfirmingCash = false
            // Dismiss the fullScreenCover on the next run loop tick so SwiftUI isn’t updating the presented view and toggling `activePaymentRequest` in the same frame (avoids black flash / broken dismissal).
            await Task.yield()
            NotificationCenter.default.post(name: .interaNavigateToConsumerHomeAfterPayment, object: nil)
            await Task.yield()
            let barberAvatarForReview = enrichedBarberAvatarURL ?? payload.barberAvatarURL
            chatViewModel.clearPaymentTakeover()
            await Task.yield()
            await chatViewModel.refreshConsumerBookingsAndSyncPayment(sessionManager: sessionManager)
            await Task.yield()
            chatViewModel.beginPostPaymentReview(from: payload, barberAvatarURLOverride: barberAvatarForReview)
        } catch {
            isConfirmingCash = false
            let ns = error as NSError
            if ns.domain == "BookingSimplePaymentAPI", ns.code == 401 {
                await sessionManager.recoverSessionAfterUnauthorized()
                return
            }
            bannerError = error.localizedDescription
        }
    }
}

private extension UIApplication {
    var interaKeyWindow: UIWindow? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let foreground = scenes.filter { $0.activationState == .foregroundActive }
        for scene in foreground + scenes {
            if let w = scene.windows.first(where: { $0.isKeyWindow }) {
                return w
            }
        }
        return foreground.flatMap(\.windows).last ?? scenes.flatMap(\.windows).last
    }

    /// Topmost `UIViewController` suitable for presenting PaymentSheet (SwiftUI `fullScreenCover` may not be the key window’s root).
    var interaPresentationRootViewController: UIViewController? {
        if let root = interaKeyWindow?.rootViewController {
            return root.interaTopPresented
        }
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            for window in scene.windows.reversed() {
                if let root = window.rootViewController {
                    return root.interaTopPresented
                }
            }
        }
        return nil
    }
}

private extension UIViewController {
    var interaTopPresented: UIViewController {
        var top = self
        while let p = top.presentedViewController { top = p }
        return top
    }
}
#else
struct ConsumerPaymentTakeoverView: View {
    let payload: BookingPaymentRequestPayload
    let sessionManager: AppSessionManager

    var body: some View {
        Text("Open \(payload.paymentUrl.absoluteString) to pay.")
    }
}
#endif
