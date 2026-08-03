//
//  ConsumerPaymentTakeoverView.swift
//  OnCuts
//
//  Full-screen payment: service confirm (ACCEPTED) or tip decision (COMPLETED).
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

/// Service price on the payment summary card.
private let paymentServicePriceFont = OnCutsFont.system(size: 48, weight: .bold, design: .default)
private let paymentModeTitleFont = OnCutsFont.system(size: 28, weight: .bold, design: .default)

/// Tip section typography (title + preset pills).
private let paymentTipPillFont = OnCutsFont.system(size: 17, weight: .semibold, design: .default)
private let paymentTipPillFontSelected = OnCutsFont.system(size: 17, weight: .bold, design: .default)

private enum PaymentTipButtonMetrics {
    static let pillHorizontalPadding: CGFloat = 20
    static let pillHorizontalPaddingSelected: CGFloat = 22
    static let pillVerticalPadding: CGFloat = 14
    static let pillVerticalPaddingSelected: CGFloat = 15
    static let pillSpacing: CGFloat = 12
}

/// Primary online payment CTAs (Apple Pay + Card).
private let paymentPrimaryActionLabelFont = OnCutsFont.system(size: 19, weight: .bold, design: .default)
private let paymentCashActionLabelFont = OnCutsFont.system(size: 16, weight: .semibold, design: .default)

private enum PaymentMethodButtonMetrics {
    static let primaryHeight: CGFloat = 58
    static let primaryCornerRadius: CGFloat = 14
    static let cashHorizontalPadding: CGFloat = 22
    static let cashVerticalPadding: CGFloat = 11
}

/// Fixed tip presets for tip-decide mode ($0 with custom, then $4/$5/$6).
private enum TipDollarPreset: Int, CaseIterable, Identifiable {
    case zero = 0
    case four = 400
    case five = 500
    case six = 600

    var id: Int { rawValue }

    var label: String {
        if rawValue == 0 { return "$0" }
        return "$\(rawValue / 100)"
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
    @State private var selectedTipPreset: TipDollarPreset?
    @State private var customTipText: String = ""
    @State private var bannerError: String?
    @State private var isPaying = false
    @State private var isStartingApplePay = false
    @State private var isConfirmingCash = false
    @State private var isConfirmingZeroTip = false
    /// When Admin enables cash (`cashPaymentEnabled`), user can select Cash — service pay only.
    @State private var prefersCashPayment = false
    @State private var frontendConfigStore = PlatformFrontendConfigStore.shared
    @State private var enrichedBarberAvatarURL: String?
    @State private var enrichedScheduledTime: String?
    @State private var validatedPublishableKeyForCheckout: String = ""
    @FocusState private var isCustomTipFocused: Bool

    private enum PaymentPhase: Equatable {
        case loading
        case ready
        case misconfigured(String)
    }

    private var isTipMode: Bool { payload.mode == .tipDecide }
    private var isServiceMode: Bool { payload.mode == .serviceConfirm }

    init(payload: BookingPaymentRequestPayload, sessionManager: AppSessionManager) {
        self.payload = payload
        self.sessionManager = sessionManager
        _tipAmountCents = State(initialValue: 0)
        _selectedTipPreset = State(initialValue: payload.mode == .tipDecide ? .zero : nil)
        _checkout = StateObject(
            wrappedValue: CheckoutViewModel(
                merchantDisplayName: "OnCuts",
                stripeReturnURL: "oncuts://stripe-redirect"
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OnCutsLavaLampBackground()

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
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    guard isCustomTipFocused else { return }
                    dismissCustomTipKeyboard()
                })
                #if os(iOS)
                .scrollDismissesKeyboard(isCustomTipFocused ? .immediately : .interactively)
                #endif
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Color.onCutsShellBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Pay later") {
                        dismissCustomTipKeyboard()
                        chatViewModel.dismissPaymentTakeoverForLater()
                    }
                    .font(OnCutsFont.body(weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                }
            }
        }
        .task {
            await frontendConfigStore.refresh()
            if !frontendConfigStore.cashPaymentEnabled || isTipMode {
                prefersCashPayment = false
            }
            // Pull operator photo in parallel with Stripe setup — tip/service pages need the
            // barber-detail avatar (socket / booking-row URLs are often missing or not loadable).
            async let avatarEnrichment: Void = enrichBookingMetadataIfNeeded()
            await configureStripeIfPossible()
            await avatarEnrichment
        }
        .onChange(of: checkout.destination) { _, new in
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
        .onChange(of: prefersCashPayment) { _, cash in
            if cash {
                selectedTipPreset = nil
                tipAmountCents = 0
                customTipText = ""
            }
        }
        .onChange(of: frontendConfigStore.cashPaymentEnabled) { _, enabled in
            if !enabled {
                prefersCashPayment = false
            }
        }
        .onChange(of: isCustomTipFocused) { _, focused in
            if focused {
                selectedTipPreset = nil
            }
        }
        .onChange(of: customTipText) { _, text in
            guard isTipMode, isCustomTipFocused || selectedTipPreset == nil else { return }
            tipAmountCents = Self.parseCustomTipCents(text)
        }
    }

    private var loadingBlock: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(Color.lavaShellCream)
            Text("Loading checkout…")
                .font(OnCutsFont.subheadline)
                .foregroundStyle(Color.lavaShellCreamSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func misconfiguredBlock(message: String) -> some View {
        VStack(spacing: 24) {
            paymentGlassCard {
                Text(message)
                    .font(OnCutsFont.subheadline)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Prefer enriched (barber-detail) URL; fall back to payload. Pass the raw stored string so
    /// `AvatarView` / `ProfileImageURLResolver.urlForAsyncImage` can resolve relative + S3 keys.
    private var resolvedBarberAvatarURLString: String? {
        let enriched = enrichedBarberAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !enriched.isEmpty { return enriched }
        let fromPayload = payload.barberAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fromPayload.isEmpty ? nil : fromPayload
    }

    private var resolvedScheduledTimeISO: String? {
        let enriched = enrichedScheduledTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !enriched.isEmpty { return enriched }
        let fromPayload = payload.scheduledTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fromPayload.isEmpty ? nil : fromPayload
    }

    /// Date + time line shown above the service price on Pay to Confirm.
    private var serviceConfirmScheduleLine: String? {
        guard let raw = resolvedScheduledTimeISO else { return nil }
        return BookingPacificSchedule.formattedDisplayScheduledTime(raw, fullMonthName: true)
    }

    private var displayBarberName: String {
        let t = payload.barberName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Your provider" : t
    }

    private var barberFirstName: String {
        let parts = displayBarberName.split(whereSeparator: \.isWhitespace)
        return parts.first.map(String.init) ?? displayBarberName
    }

    private var showsCashPaymentOption: Bool {
        isServiceMode && frontendConfigStore.cashPaymentEnabled
    }

    private var cashConfirmButtonTitle: String {
        "Confirm Cash Payment \(payload.priceFormatted)"
    }

    private static let paymentAvatarCorner: CGFloat = 12

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
                VStack(spacing: 32) {
                    Text(isTipMode ? "Consider a Tip" : "Pay to Confirm Booking")
                        .font(paymentModeTitleFont)
                        .foregroundStyle(Color.lavaShellCream)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

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
                                .stroke(Color.onCutsShellGlassStroke, lineWidth: 1)
                        )

                        Text(displayBarberName)
                            .font(OnCutsFont.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(Color.lavaShellCream)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: 260)

                        Text(payload.displayServiceName)
                            .font(OnCutsFont.system(size: 14, weight: .medium, design: .default))
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .kerning(paymentServiceTitleKerning)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .frame(maxWidth: 280)
                    }

                    if isServiceMode {
                        VStack(spacing: 10) {
                            if let scheduleLine = serviceConfirmScheduleLine {
                                Text(scheduleLine)
                                    .font(OnCutsFont.subheadline(weight: .semibold))
                                    .foregroundStyle(Color.lavaShellCreamSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(payload.priceFormatted)
                                .font(paymentServicePriceFont)
                                .foregroundStyle(Color.lavaShellCream)
                                .multilineTextAlignment(.center)
                        }
                    }

                    if isTipMode {
                        tipDecideSection
                    }

                    VStack(spacing: 20) {
                        if isServiceMode, prefersCashPayment {
                            Text("Please give cash directly to \(barberFirstName)")
                                .font(OnCutsFont.subheadline)
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            cashConfirmPrimaryButton

                            if showsCashPaymentOption {
                                Button("Pay with card instead") {
                                    prefersCashPayment = false
                                }
                                .font(OnCutsFont.footnote(weight: .semibold))
                                .foregroundStyle(Color.lavaShellCreamSecondary)
                                .disabled(isConfirmingCash)
                            }
                        } else if isTipMode, tipAmountCents == 0, selectedTipPreset == .zero, !isCustomTipFocused {
                            zeroTipConfirmButton
                        } else {
                            Text(
                                isApplePayConfigured
                                    ? "Pay with Apple Pay or Manually input card"
                                    : "Manually input card"
                            )
                            .font(OnCutsFont.subheadline)
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

                            if showsCashPaymentOption {
                                paymentCashPreferenceHint
                                    .padding(.top, 4)
                                cashSecondaryButton
                            }
                        }

                        if let bannerError {
                            Text(bannerError)
                                .font(OnCutsFont.caption)
                                .foregroundStyle(Color.red.opacity(0.92))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
        }
    }

    private var tipDecideSection: some View {
        VStack(alignment: .center, spacing: 16) {
            Text("Consider leaving a tip that best represents the quality of service")
                .font(OnCutsFont.subheadline)
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Top row: $0 + custom
            HStack(spacing: PaymentTipButtonMetrics.pillSpacing) {
                tipPill(.zero)
                customTipField
            }

            HStack(spacing: PaymentTipButtonMetrics.pillSpacing) {
                tipPill(.four)
                tipPill(.five)
                tipPill(.six)
            }

            if tipAmountCents > 0 {
                Text(Self.formatUSD(cents: tipAmountCents))
                    .font(OnCutsFont.title2(weight: .bold))
                    .foregroundStyle(Color.onCutsShellForeground)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var customTipField: some View {
        HStack(spacing: 2) {
            Text("$")
                .font(paymentTipPillFont)
                .foregroundStyle(Color.paymentFieldForeground)
                .accessibilityHidden(true)
            TextField("Custom", text: $customTipText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .font(paymentTipPillFont)
                .foregroundStyle(Color.paymentFieldForeground)
                .tint(Color.oliveGreen)
                .focused($isCustomTipFocused)
                .accessibilityLabel("Custom tip amount in dollars")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, PaymentTipButtonMetrics.pillVerticalPadding)
        .frame(minWidth: 96)
        .background(
            Capsule(style: .continuous)
                .fill(Color.paymentFieldBackground.opacity(0.55))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    isCustomTipFocused ? Color.oliveGreen : Color.paymentTipUnselectedStroke,
                    lineWidth: isCustomTipFocused ? 2 : 1.5
                )
        )
    }

    private var paymentMethodOrDivider: some View {
        Text("or")
            .font(OnCutsFont.subheadline(weight: .semibold))
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
        .font(OnCutsFont.footnote)
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
                    isEnabled: !isPaying && !isConfirmingCash && !isConfirmingZeroTip && canChargeCard,
                    action: { presentStandaloneApplePayCheckout() }
                )
                .frame(maxWidth: .infinity)
                .frame(height: PaymentMethodButtonMetrics.primaryHeight)
                .clipShape(RoundedRectangle(cornerRadius: PaymentMethodButtonMetrics.primaryCornerRadius, style: .continuous))
            }
        }
    }

    private var canChargeCard: Bool {
        if isTipMode { return tipAmountCents > 0 }
        return true
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
                        .font(OnCutsFont.title3(weight: .semibold))
                        .foregroundStyle(Color.paymentFilledButtonLabel)
                }
                Text(isPaying ? "Opening…" : "Input Card Details")
                    .font(paymentPrimaryActionLabelFont)
                    .foregroundStyle(Color.paymentFilledButtonLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: PaymentMethodButtonMetrics.primaryHeight)
            .background(Color.paymentFilledButtonFill)
            .clipShape(RoundedRectangle(cornerRadius: PaymentMethodButtonMetrics.primaryCornerRadius, style: .continuous))
        }
        .disabled(isPaying || isConfirmingCash || isStartingApplePay || isConfirmingZeroTip || !canChargeCard)
        .buttonStyle(BookButtonStyle())
    }

    private var zeroTipConfirmButton: some View {
        Button {
            Task { await completeZeroTip() }
        } label: {
            HStack(spacing: 12) {
                if isConfirmingZeroTip {
                    ProgressView()
                        .tint(Color.paymentFilledButtonLabel)
                }
                Text(isConfirmingZeroTip ? "Confirming…" : "Confirm $0 tip")
                    .font(paymentPrimaryActionLabelFont)
                    .foregroundStyle(Color.paymentFilledButtonLabel)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: PaymentMethodButtonMetrics.primaryHeight)
            .background(Color.paymentFilledButtonFill)
            .clipShape(RoundedRectangle(cornerRadius: PaymentMethodButtonMetrics.primaryCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PaymentMethodButtonMetrics.primaryCornerRadius, style: .continuous)
                    .stroke(Color.onCutsShellGlassStroke, lineWidth: 1)
            )
            .shadow(color: Color.primary.opacity(0.08), radius: 8, y: 2)
        }
        .disabled(isConfirmingZeroTip || isPaying || isStartingApplePay)
        .buttonStyle(BookButtonStyle())
    }

    private var cashSecondaryButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                prefersCashPayment = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "banknote")
                        .font(OnCutsFont.subheadline(weight: .semibold))
                    Text("Cash")
                        .font(paymentCashActionLabelFont)
                }
                .foregroundStyle(Color.paymentOutlineButtonLabel)
                .padding(.horizontal, PaymentMethodButtonMetrics.cashHorizontalPadding)
                .padding(.vertical, PaymentMethodButtonMetrics.cashVerticalPadding)
                .background(Color.clear)
                .clipShape(Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.paymentOutlineButtonLabel, lineWidth: 1)
                )
                .contentShape(Capsule(style: .continuous))
            }
            .disabled(isConfirmingCash || isPaying || isStartingApplePay)
            .buttonStyle(BookButtonStyle())
            Spacer(minLength: 0)
        }
    }

    private var cashConfirmPrimaryButton: some View {
        Button {
            Task { await completeCashPayment() }
        } label: {
            HStack(spacing: 12) {
                if isConfirmingCash {
                    ProgressView()
                        .tint(Color.paymentFilledButtonLabel)
                } else {
                    Image(systemName: "banknote.fill")
                        .font(OnCutsFont.title3(weight: .semibold))
                        .foregroundStyle(Color.paymentFilledButtonLabel)
                }
                Text(isConfirmingCash ? "Completing…" : cashConfirmButtonTitle)
                    .font(paymentPrimaryActionLabelFont)
                    .foregroundStyle(Color.paymentFilledButtonLabel)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: PaymentMethodButtonMetrics.primaryHeight)
            .padding(.horizontal, 12)
            .background(Color.paymentFilledButtonFill)
            .clipShape(RoundedRectangle(cornerRadius: PaymentMethodButtonMetrics.primaryCornerRadius, style: .continuous))
        }
        .disabled(isConfirmingCash || isPaying || isStartingApplePay)
        .buttonStyle(BookButtonStyle())
    }

    private func dismissCustomTipKeyboard() {
        isCustomTipFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func tipPill(_ preset: TipDollarPreset) -> some View {
        let selected = selectedTipPreset == preset && !isCustomTipFocused
        return Button {
            dismissCustomTipKeyboard()
            customTipText = ""
            if selected {
                selectedTipPreset = .zero
                tipAmountCents = 0
            } else {
                BookingSelectorTheme.triggerSelectionChangedIfNewSelection(wasSelected: false)
                selectedTipPreset = preset
                tipAmountCents = preset.rawValue
            }
        } label: {
            Text(preset.label)
                .font(selected ? paymentTipPillFontSelected : paymentTipPillFont)
                .foregroundStyle(selected ? Color.paymentTipSelectedLabel : Color.paymentOutlineButtonLabel)
                .padding(.horizontal, selected ? PaymentTipButtonMetrics.pillHorizontalPaddingSelected : PaymentTipButtonMetrics.pillHorizontalPadding)
                .padding(.vertical, selected ? PaymentTipButtonMetrics.pillVerticalPaddingSelected : PaymentTipButtonMetrics.pillVerticalPadding)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? Color.paymentTipSelectedFill : Color.paymentFieldBackground.opacity(0.45))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            selected ? Color.paymentTipSelectedFill : Color.paymentTipUnselectedStroke,
                            lineWidth: selected ? 2.5 : 1.5
                        )
                )
                .shadow(color: selected ? Color.oliveGreen.opacity(0.35) : .clear, radius: 10, y: 3)
                .scaleEffect(selected ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(BookingSelectorTheme.selectionSpring, value: selected)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

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
                    .stroke(Color.onCutsShellGlassStroke, lineWidth: 1)
            )
    }

    @MainActor
    private func enrichBookingMetadataIfNeeded() async {
        guard let token = sessionManager.currentSession?.token.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return }

        let needsSchedule =
            isServiceMode
            && (resolvedScheduledTimeISO == nil)

        if needsSchedule {
            do {
                let row = try await ConsumerBookingsSimpleAPI.fetchConsumerBookingById(
                    bookingId: payload.bookingId,
                    bearerToken: token
                )
                let scheduled = row.scheduledTime.trimmingCharacters(in: .whitespacesAndNewlines)
                if !scheduled.isEmpty {
                    enrichedScheduledTime = scheduled
                }
            } catch {
                // Schedule line stays hidden if fetch fails.
            }
        }

        // Always resolve via booking + barber detail (same source as browse cards).
        if enrichedBarberAvatarURL == nil,
           let url = await ConsumerBookingsSimpleAPI.resolveBarberAvatarURL(
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
        let fromServer: String? = {
            guard let s = serverTrimmed, s.hasPrefix("pk_") else { return nil }
            if Self.hostsProductionOnCutsAPI, s.hasPrefix("pk_test") {
                return nil
            }
            return s
        }()
        let pk = fromServer ?? fromPlist
        guard pk.hasPrefix("pk_"), !pk.contains("REPLACE"), !pk.contains("NOT_CONFIGURED") else {
            phase = .misconfigured(stripeMisconfiguredHint(actualValue: pk))
            return
        }
        if Self.hostsProductionOnCutsAPI, pk.hasPrefix("pk_test") {
            phase = .misconfigured(
                "This build uses a Stripe test publishable key (pk_test…) while the app is pointed at the production OnCuts API. " +
                    "Live PaymentIntents return 404 in that setup. Set STRIPE_PUBLISHABLE_KEY = pk_live… on the server (GET /api/v1/stripe/client-config) and/or in `Config/StripeKeys.xcconfig`, then Product → Clean Build Folder."
            )
            return
        }
        StripeService.setPublishableKey(pk)
        validatedPublishableKeyForCheckout = pk
        phase = .ready
    }

    private static var hostsProductionOnCutsAPI: Bool {
        AppConfiguration.hostsProductionAPI
    }

    private func stripeMisconfiguredHint(actualValue: String) -> String {
        if actualValue.isEmpty {
            return "No Stripe publishable key in the app Info.plist and none from GET /api/v1/stripe/client-config. Set STRIPE_PUBLISHABLE_KEY in `Config/StripeKeys.xcconfig` (and on the API host’s environment for client-config), then Product → Clean Build Folder and run again."
        }
        return "The app still has a placeholder Stripe key (or invalid value). For production payments set STRIPE_PUBLISHABLE_KEY = pk_live_… in `Config/StripeKeys.xcconfig` and on the server so client-config matches your Stripe secret mode, then Clean Build Folder."
    }

    private func presentStripePaymentSheet() {
        bannerError = nil
        guard canChargeCard else {
            bannerError = "Choose a tip amount greater than $0, or confirm $0 tip."
            return
        }
        isPaying = true
        checkout.resetNavigation()
        Task { @MainActor in
            do {
                let config = try await checkout.fetchPaymentParams(
                    bookingID: payload.bookingId,
                    stripeAccountID: payload.barberStripeAccountId,
                    tipAmountCents: isTipMode ? tipAmountCents : 0,
                    bearerToken: sessionManager.currentSession?.token,
                    apiBaseURLTrimmed: AppConfiguration.messagingAPIRootTrimmed,
                    publishableKeyValidatedByHost: validatedPublishableKeyForCheckout.isEmpty
                        ? nil
                        : validatedPublishableKeyForCheckout,
                    paymentSheetIncludesApplePay: false,
                    usesTipIntent: isTipMode
                )
                guard let presenter = UIApplication.shared.onCutsPresentationRootViewController else {
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
        guard canChargeCard else {
            bannerError = "Choose a tip amount greater than $0, or confirm $0 tip."
            return
        }
        isStartingApplePay = true
        checkout.resetNavigation()
        Task { @MainActor in
            do {
                let config = try await checkout.fetchPaymentParams(
                    bookingID: payload.bookingId,
                    stripeAccountID: payload.barberStripeAccountId,
                    tipAmountCents: isTipMode ? tipAmountCents : 0,
                    bearerToken: sessionManager.currentSession?.token,
                    apiBaseURLTrimmed: AppConfiguration.messagingAPIRootTrimmed,
                    publishableKeyValidatedByHost: validatedPublishableKeyForCheckout.isEmpty
                        ? nil
                        : validatedPublishableKeyForCheckout,
                    paymentSheetIncludesApplePay: false,
                    usesTipIntent: isTipMode
                )
                let window = UIApplication.shared.onCutsKeyWindow
                let started = checkout.presentStandaloneApplePay(
                    from: window,
                    paymentConfig: config,
                    serviceCents: isTipMode ? 0 : payload.priceCents,
                    tipCents: isTipMode ? tipAmountCents : 0
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
        if isTipMode {
            await confirmTipAndFinish(paymentIntentId: pi)
        } else {
            await confirmServiceAndFinish(paymentIntentId: pi)
        }
        checkout.resetNavigation()
    }

    @MainActor
    private func confirmServiceAndFinish(paymentIntentId: String) async {
        do {
            try await BookingSimplePaymentAPI.confirmPayment(
                bookingId: payload.bookingId,
                paymentIntentId: paymentIntentId,
                tipAmountCents: 0,
                bearerToken: sessionManager.currentSession?.token
            )
            await finishServicePaymentSuccess()
        } catch {
            bannerError = "Payment went through, but confirmation failed: \(error.localizedDescription)"
            await chatViewModel.refreshConsumerBookingsAndSyncPayment(sessionManager: sessionManager)
        }
    }

    @MainActor
    private func confirmTipAndFinish(paymentIntentId: String?) async {
        do {
            try await BookingSimplePaymentAPI.confirmTip(
                bookingId: payload.bookingId,
                tipAmountCents: tipAmountCents,
                paymentIntentId: paymentIntentId,
                bearerToken: sessionManager.currentSession?.token
            )
            await finishTipPaymentSuccess()
        } catch {
            bannerError = "Tip went through, but confirmation failed: \(error.localizedDescription)"
            await chatViewModel.refreshConsumerBookingsAndSyncPayment(sessionManager: sessionManager)
        }
    }

    @MainActor
    private func completeZeroTip() async {
        bannerError = nil
        isConfirmingZeroTip = true
        defer { isConfirmingZeroTip = false }
        tipAmountCents = 0
        await confirmTipAndFinish(paymentIntentId: nil)
    }

    @MainActor
    private func finishServicePaymentSuccess() async {
        await Task.yield()
        NotificationCenter.default.post(name: .onCutsNavigateToConsumerHomeAfterPayment, object: nil)
        await Task.yield()
        chatViewModel.clearPaymentTakeover()
        await Task.yield()
        await chatViewModel.pruneInboxAfterBookingConversationDeleted(
            bookingId: payload.bookingId,
            sessionManager: sessionManager
        )
        await chatViewModel.refreshConsumerBookingsAndSyncPayment(sessionManager: sessionManager)
    }

    @MainActor
    private func finishTipPaymentSuccess() async {
        await Task.yield()
        NotificationCenter.default.post(name: .onCutsNavigateToConsumerHomeAfterPayment, object: nil)
        await Task.yield()
        let barberAvatarForReview = enrichedBarberAvatarURL ?? payload.barberAvatarURL
        chatViewModel.clearPaymentTakeover()
        await Task.yield()
        await chatViewModel.pruneInboxAfterBookingConversationDeleted(
            bookingId: payload.bookingId,
            sessionManager: sessionManager
        )
        await chatViewModel.refreshConsumerBookingsAndSyncPayment(sessionManager: sessionManager)
        await Task.yield()
        chatViewModel.beginPostPaymentReview(from: payload, barberAvatarURLOverride: barberAvatarForReview)
    }

    @MainActor
    private func completeCashPayment() async {
        bannerError = nil
        guard isServiceMode else { return }
        guard frontendConfigStore.cashPaymentEnabled else {
            prefersCashPayment = false
            bannerError = "Cash payments are currently disabled"
            return
        }
        tipAmountCents = 0
        selectedTipPreset = nil
        isConfirmingCash = true
        do {
            try await BookingSimplePaymentAPI.payWithCash(
                bookingId: payload.bookingId,
                tipAmountCents: 0,
                bearerToken: sessionManager.currentSession?.token
            )
            isConfirmingCash = false
            await finishServicePaymentSuccess()
        } catch {
            isConfirmingCash = false
            if BookingSimplePaymentAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
                return
            }
            if BookingSimplePaymentAPI.isCashPaymentsDisabledHTTPError(error) {
                prefersCashPayment = false
                await frontendConfigStore.refresh()
                bannerError = "Cash payments are currently disabled"
                return
            }
            bannerError = error.localizedDescription
        }
    }

    private static func parseCustomTipCents(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
        guard !trimmed.isEmpty, let dollars = Double(trimmed), dollars >= 0 else { return 0 }
        return Int((dollars * 100).rounded())
    }

    private static func formatUSD(cents: Int) -> String {
        let d = Decimal(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSDecimalNumber(decimal: d)) ?? String(format: "$%.2f", Double(cents) / 100.0)
    }
}

private extension UIApplication {
    var onCutsKeyWindow: UIWindow? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let foreground = scenes.filter { $0.activationState == .foregroundActive }
        for scene in foreground + scenes {
            if let w = scene.windows.first(where: { $0.isKeyWindow }) {
                return w
            }
        }
        return foreground.flatMap(\.windows).last ?? scenes.flatMap(\.windows).last
    }

    var onCutsPresentationRootViewController: UIViewController? {
        if let root = onCutsKeyWindow?.rootViewController {
            return root.onCutsTopPresented
        }
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            for window in scene.windows.reversed() {
                if let root = window.rootViewController {
                    return root.onCutsTopPresented
                }
            }
        }
        return nil
    }
}

private extension UIViewController {
    var onCutsTopPresented: UIViewController {
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
