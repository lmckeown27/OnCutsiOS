//
//  UserProfileView.swift
//  OnCuts
//
//  Role-aware profile: glass header, tabbed content (student vs barber), S3 portfolio grid,
//  settings glass bottom sheet, matched-geometry tab highlight for barber tabs.
//

import SwiftUI
import OnCutsModule
#if canImport(UIKit)
import UIKit
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

// MARK: - Profile domain (lightweight; replace with API models when wired)

struct UserProfileAppointment: Identifiable, Hashable {
    let id: String
    let serviceName: String
    let providerName: String
    let scheduledAt: Date
    /// Short label from **bookings-simple** `status` (e.g. Pending, Confirmed).
    var statusNote: String? = nil
    var isPast: Bool { scheduledAt < Date() }
}

struct UserProfileServiceRow: Identifiable, Hashable {
    let id: String
    let name: String
    let priceUsd: Int
    let durationMinutes: Int
}

struct UserProfileReviewSnippet: Identifiable, Hashable {
    let id: String
    let authorName: String
    let rating: Int
    let body: String
    let createdAt: Date
}

// MARK: - Live data helpers

private enum UserProfileBarberIdCache {
    private static let prefix = "userProfile.barberRecordId."

    static func load(for userId: String) -> String? {
        let raw = UserDefaults.standard.string(forKey: prefix + userId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    static func save(_ barberId: String, for userId: String) {
        UserDefaults.standard.set(barberId, forKey: prefix + userId)
    }

    static func clear(for userId: String) {
        UserDefaults.standard.removeObject(forKey: prefix + userId)
    }
}

// MARK: - Main view

struct UserProfileView: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    /// When true (e.g. profile sheet from avatar), Privacy / Terms / Sign Out appear as one glass “Account” block below the edit tabs.
    var showsIntegratedAccountMenu: Bool = false
    /// Called after sign out from the integrated Account section (e.g. dismiss the hosting sheet).
    var onAccountMenuSignOut: (() -> Void)? = nil
    /// When set (e.g. main hub tab), signed-out users are kept on Home by the hub shell.
    var hubBottomBarSuppressionWhileFocused: Binding<Bool>? = nil

    /// Barber bio from API (fallback when editing profile before remote profile loads).
    @State private var barberBioFromAPI: String?

    private var session: UserSession? { sessionManager.currentSession }

    var body: some View {
        Group {
            // Match Messages / Bookings: `isAuthenticated` is false when `expiresAt` has passed even if `currentSession` is non-nil until the next validation tick clears it.
            if sessionManager.isAuthenticated, let session {
                UserProfileSettingsDrawerOverlay(
                    session: session,
                    sessionManager: sessionManager,
                    coordinator: coordinator,
                    barberBioFallback: barberBioFromAPI,
                    showsIntegratedAccountMenu: showsIntegratedAccountMenu,
                    onAccountMenuSignOut: onAccountMenuSignOut,
                    onDismiss: {},
                    onSaved: {
                        await loadLiveProfileData()
                    },
                    hubBottomBarSuppressionWhileFocused: hubBottomBarSuppressionWhileFocused
                )
            } else {
                ContentUnavailableView(
                    "Not signed in",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Sign in to view your profile.")
                )
                .padding(.top, 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(Color.oliveGreen)
        .task(id: sessionManager.isAuthenticated ? session?.userId : nil) {
            await loadLiveProfileData()
        }
    }

    private func onCutsClient() -> OnCutsClient {
        OnCutsClient(
            session: OnCutsUserSessionAdapter(manager: sessionManager),
            environment: .production,
            isProduction: AppConfiguration.onCutsProductionLiveDataMode
        )
    }

    /// Loads barber bio for edit-form fallback; students/admins do not need extra data here.
    @MainActor
    private func loadLiveProfileData() async {
        guard sessionManager.isAuthenticated, let session else { return }

        switch session.role {
        case .student, .admin:
            barberBioFromAPI = nil

        case .barber:
            let client = onCutsClient()
            do {
                var barberId = UserProfileBarberIdCache.load(for: session.userId)
                if barberId == nil {
                    barberId = try await client.inferCurrentBarberId()
                    if let barberId {
                        UserProfileBarberIdCache.save(barberId, for: session.userId)
                    }
                }
                if let barberId {
                    barberBioFromAPI = try await client.fetchBarberBio(barberId: barberId)
                } else {
                    barberBioFromAPI = nil
                }
            } catch {
                barberBioFromAPI = nil
            }
        }
    }
}

// MARK: - Bio persistence (barber / non-student profile edit only)
//
// Consumers (students) are not asked for a self-bio in-app at this time; `UserProfileBioStore` is only
// used when `session.role != .student` (see `loadRemoteProfile` / `applyLocalFallbacks` / `saveProfile`).
private enum UserProfileBioStore {
    private static let prefix = "userProfile.bio."

    static func bio(for userId: String) -> String {
        UserDefaults.standard.string(forKey: prefix + userId) ?? ""
    }

    static func setBio(_ text: String, for userId: String) {
        UserDefaults.standard.set(text, forKey: prefix + userId)
    }
}

// MARK: - Student tabs

private enum StudentProfileTab: String, CaseIterable, Identifiable {
    case past
    case today
    case upcoming

    var id: String { rawValue }
    var title: String {
        switch self {
        case .past: return "Past"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        }
    }
}

// MARK: - Barber tabs (matched geometry between selections)

private enum BarberProfileTab: String, CaseIterable, Identifiable {
    case portfolio
    case services
    case reviews

    var id: String { rawValue }
    var title: String {
        switch self {
        case .portfolio: return "Portfolio"
        case .services: return "Services"
        case .reviews: return "Reviews"
        }
    }
}

private struct BarberTabSwitcher: View {
    @Binding var selection: BarberProfileTab
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BarberProfileTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        selection = tab
                    }
                } label: {
                    ZStack {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.oliveGreen.opacity(0.28))
                                .matchedGeometryEffect(id: "barberTabPill", in: namespace)
                        }
                        Text(tab.title)
                            .font(OnCutsFont.subheadline(weight: .semibold))
                            .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
    }
}

// MARK: - Glass header

private struct UserProfileGlassHeaderCard: View {
    let session: UserSession
    // Consumer self-bio (disabled at this time — was `let bioText: String` + block below).

    private var showVerified: Bool {
        session.isValid && (session.stripeCustomerId != nil || session.role == .barber)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                avatar

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(session.displayName)
                            .font(OnCutsFont.headlineSmall)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if showVerified {
                            Label("Verified", systemImage: "checkmark.seal.fill")
                                .font(OnCutsFont.caption(weight: .bold))
                                .foregroundStyleOliveGreen()
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background {
                                    Capsule()
                                        .fill(Color.oliveGreen.opacity(0.15))
                                }
                        }
                    }

                    Text(session.role.displayName)
                        .font(OnCutsFont.caption(weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.oliveGreen.opacity(0.12))
                        .foregroundStyleOliveGreen()
                        .clipShape(Capsule())
                }
            }

            /*
             // Consumer self-bio preview (disabled — not required at this time).
             VStack(alignment: .leading, spacing: 6) {
                 Text("Bio")
                     .font(OnCutsFont.caption(weight: .semibold))
                     .foregroundStyle(.secondary)
                 Text(bioText.isEmpty ? "Add a short bio in settings." : bioText)
                     .font(OnCutsFont.bodyMedium)
                     .foregroundStyle(bioText.isEmpty ? Color.secondary : Color.primary)
                     .fixedSize(horizontal: false, vertical: true)
             }
             .padding(.top, 4)
             */
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        }
    }

    private var avatar: some View {
        AvatarView(
            imageUrl: session.profileImageURL,
            name: session.displayName,
            size: 88,
            clipStyle: .square(cornerRadius: 15)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        }
    }
}

// MARK: - Student lists

private struct UserProfileAppointmentList: View {
    let appointments: [UserProfileAppointment]
    let emptyMessage: String

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        if appointments.isEmpty {
            Text(emptyMessage)
                .font(OnCutsFont.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)
        } else {
            VStack(spacing: 12) {
                ForEach(appointments) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.serviceName)
                                .font(OnCutsFont.headlineSmall)
                            if let note = item.statusNote, !note.isEmpty {
                                Text(note)
                                    .font(OnCutsFont.caption2(weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                            }
                        }
                        Text(item.providerName)
                            .font(OnCutsFont.subheadline)
                            .foregroundStyle(.secondary)
                        Text(Self.df.string(from: item.scheduledAt))
                            .font(OnCutsFont.caption)
                            .foregroundStyleOliveGreen()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    }
                }
            }
        }
    }
}

// MARK: - Portfolio grid

private struct UserProfilePortfolioGrid: View {
    let urls: [URL]
    @Binding var pressedIndex: Int?

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 10)]

    var body: some View {
        if urls.isEmpty {
            Text("No portfolio images on your profile yet. They appear here when `portfolioImages` is set on your barber record.")
                .font(OnCutsFont.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                Color.gray.opacity(0.2)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                        }
                        .frame(minWidth: 108, minHeight: 108)
                        .clipped()
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .scaleEffect(pressedIndex == index ? 0.96 : 1)
                        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: pressedIndex == index)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in pressedIndex = index }
                            .onEnded { _ in pressedIndex = nil }
                    )
                }
            }
        }
    }
}

// MARK: - Services & reviews

private struct UserProfileServicesList: View {
    let rows: [UserProfileServiceRow]

    var body: some View {
        if rows.isEmpty {
            Text("No services listed yet. Add them in your barber dashboard or backend.")
                .font(OnCutsFont.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else {
        VStack(spacing: 10) {
            ForEach(rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.name)
                            .font(OnCutsFont.headlineSmall)
                        Text("\(row.durationMinutes) min")
                            .font(OnCutsFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("$\(row.priceUsd)")
                        .font(OnCutsFont.bodyLarge(weight: .semibold))
                        .foregroundStyleOliveGreen()
                }
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                }
            }
        }
        }
    }
}

private struct UserProfileReviewsList: View {
    let reviews: [UserProfileReviewSnippet]

    var body: some View {
        if reviews.isEmpty {
            Text("No reviews yet.")
                .font(OnCutsFont.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else {
        VStack(spacing: 12) {
            ForEach(reviews) { r in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(r.authorName)
                            .font(OnCutsFont.subheadline(weight: .semibold))
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { i in
                                Image(systemName: i < r.rating ? "star.fill" : "star")
                                    .font(OnCutsFont.caption2)
                                    .foregroundStyle(i < r.rating ? Color.primary : Color.secondary.opacity(0.4))
                            }
                        }
                    }
                    Text(r.body)
                        .font(OnCutsFont.bodyMedium)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                }
            }
        }
        }
    }
}

// MARK: - Edit profile overlay (glass tabs)

#if os(iOS)
private struct ProfileUtilityPillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

private enum ProfileUtilityPillHaptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()

    static func lightTap() {
        light.prepare()
        light.impactOccurred()
    }

    static func selectionChanged() {
        selection.prepare()
        selection.selectionChanged()
    }
}
#endif

/// Feeds hub bar collapse + Account utility pill hide/show from one scroll observer.
private struct ProfileAccountScrollReportingModifier: ViewModifier {
    let reportsProfileUtilityPillCollapse: Bool
    let hubPageIndex: Int
    let onProfileScrollOffset: (CGFloat) -> Void
    @Environment(\.onCutsHubBarScrollOffsetHandler) private var hubBarScrollHandler

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, newValue in
                hubBarScrollHandler.onOffsetChange?(hubPageIndex, newValue)
                if reportsProfileUtilityPillCollapse {
                    onProfileScrollOffset(newValue)
                }
            }
        } else {
            content
        }
    }
}

private enum EditProfileMainTab: String, CaseIterable, Identifiable {
    case profileInfo
    case security

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profileInfo: return "Profile Info"
        case .security: return "Delete Account"
        }
    }
}

private struct UserProfileGlassSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(OnCutsFont.system(.subheadline, design: .serif))
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UserProfileGlassTile<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            }
    }
}

private struct UserProfileSettingsDrawerOverlay: View {
    let session: UserSession
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    let barberBioFallback: String?
    let showsIntegratedAccountMenu: Bool
    let onAccountMenuSignOut: (() -> Void)?
    let onDismiss: () -> Void
    let onSaved: () async -> Void
    var hubBottomBarSuppressionWhileFocused: Binding<Bool>? = nil

    @State private var tab: EditProfileMainTab = .profileInfo
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    /// Editable self-bio for **non-student** roles (e.g. barber). Consumers do not provide this in-app for now.
    @State private var bio: String = ""
    @State private var avatarURLString: String?

    @State private var isLoadingRemote = false
    @State private var isSaving = false
    /// Avoids redundant PATCH when name fields match what we last loaded or saved.
    @State private var lastPersistedFirst: String = ""
    @State private var lastPersistedLast: String = ""
    @State private var profileNameAutosaveTask: Task<Void, Never>?
    @Environment(\.onCutsHubBarOverlayBottomInset) private var hubBarOverlayBottomInset
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var profileScrollContentOffsetY: CGFloat = 0
    @State private var profileUtilityPillCollapseOffset: CGFloat = 0
    @State private var isDeleting = false
    @State private var formError: String?
    @State private var showDeleteConfirm = false
    @State private var deletePassword = ""
    @State private var deletePasswordVisible = false
    @State private var deleteAccountError: String?
    /// From `GET /auth/me`: `true` means the user has not set an OnCuts password (e.g. Sign in with Apple only) — use device confirmation instead of password when deleting.
    @State private var needsPlatformPasswordForDeletion: Bool = false
    @State private var showSignOutConfirm = false
    @State private var showApplePayReviewerInfo = false

    /// Shown in the Account → Apple Pay & payments sheet (numbered checklist for reviewers and users).
    private static let applePayInstructionSteps: [String] = [
        "Your service provider marks the service Completed in the \(AppBranding.companyName) provider platform (their provider-facing \(AppBranding.companyName) app).",
        "\(AppBranding.displayName) may open the payment screen automatically; you can tap Pay later to return to the app, then go to Bookings → open that booking → Pay for this service.",
        "On the payment screen, use the Apple Pay button (or Card / Cash). Apple Pay appears when Wallet has a card and merchant configuration is active.",
        "If checkout never appeared, open Bookings, select the completed booking, and tap Pay for this service.",
    ]

    private enum ProfileNameField: Hashable {
        case firstName
        case lastName
    }

    /// App Store Guideline 4: no manual name/email fields after Sign in with Apple — only Authentication Services + server profile.
    private var profileNameManagedBySignInWithApple: Bool {
        session.signInProvider == .apple
    }

    /// Keeps keyboard resize on the scroll surface only so the Profile Info / Delete Account bar does not ride up with the keyboard.
    @FocusState private var focusedProfileNameField: ProfileNameField?

    private func dismissProfileNameKeyboard() {
        focusedProfileNameField = nil
        #if canImport(UIKit)
        UIApplication.shared.sendAction(NSSelectorFromString("resignFirstResponder"), to: nil, from: nil, for: nil)
        #endif
    }

    private static let profileUtilityPillBarHeight: CGFloat = 56
    private static let profileUtilityPillVerticalPadding: CGFloat = 20
    private static let profileUtilityPillChromeHideRange: CGFloat = 88

    private var profileUtilityPillReservedTopInset: CGFloat {
        Self.profileUtilityPillBarHeight + Self.profileUtilityPillVerticalPadding
    }

    private var shouldTrackProfileUtilityPillScrollCollapse: Bool {
        guard showsIntegratedAccountMenu else { return false }
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad { return false }
        #endif
        if focusedProfileNameField != nil { return false }
        if accessibilityReduceMotion { return false }
        return true
    }

    /// 1 = utility pill fully visible; 0 = slid off-screen (matches home browse chrome).
    private var profileUtilityChromeProgress: CGFloat {
        guard shouldTrackProfileUtilityPillScrollCollapse else { return 1 }
        let range = Self.profileUtilityPillChromeHideRange
        guard range > 0 else { return 1 }
        return min(1, max(0, 1 - profileUtilityPillCollapseOffset / range))
    }

    private var profileUtilityPillHideTravel: CGFloat {
        profileUtilityPillReservedTopInset * (1 - profileUtilityChromeProgress)
    }

    private var profileScrollTopInset: CGFloat {
        guard showsIntegratedAccountMenu else { return 0 }
        let minTop: CGFloat = 10
        return minTop + (profileUtilityPillReservedTopInset - minTop) * profileUtilityChromeProgress
    }

    private func handleProfileScrollOffsetChange(_ offsetY: CGFloat) {
        let previousOffsetY = profileScrollContentOffsetY
        profileScrollContentOffsetY = offsetY

        guard shouldTrackProfileUtilityPillScrollCollapse else {
            profileUtilityPillCollapseOffset = 0
            return
        }
        if offsetY <= 0 {
            profileUtilityPillCollapseOffset = 0
            return
        }
        let range = Self.profileUtilityPillChromeHideRange
        let delta = offsetY - previousOffsetY
        profileUtilityPillCollapseOffset = min(range, max(0, profileUtilityPillCollapseOffset + delta))
    }

    var body: some View {
        Group {
            if isLoadingRemote {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let formError, !formError.isEmpty {
                            Text(formError)
                                .font(OnCutsFont.caption)
                                .foregroundStyle(.red)
                        }
                        tabContent
                        if showsIntegratedAccountMenu {
                            integratedAccountMenuSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, profileScrollTopInset)
                    .padding(.bottom, 28 + hubBarOverlayBottomInset)
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .modifier(
                    ProfileAccountScrollReportingModifier(
                        reportsProfileUtilityPillCollapse: showsIntegratedAccountMenu,
                        hubPageIndex: 3,
                        onProfileScrollOffset: handleProfileScrollOffsetChange
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .overlay {
            ProfileNameFieldOutsideTapOverlay(
                isActive: focusedProfileNameField != nil && !isLoadingRemote,
                onOutsideTap: { dismissProfileNameKeyboard() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(focusedProfileNameField != nil && !isLoadingRemote)
        }
        #endif
        .overlay(alignment: .top) {
            if showsIntegratedAccountMenu, !isLoadingRemote {
                profileUtilityPillChrome
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !showsIntegratedAccountMenu, !isLoadingRemote {
                editTabBar
                    .padding(.horizontal, .space4)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .background {
                        #if canImport(UIKit)
                        Color(uiColor: .systemGroupedBackground)
                        #else
                        Color.gray.opacity(0.08)
                        #endif
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if showsIntegratedAccountMenu {
                Color.clear
            } else {
                #if canImport(UIKit)
                Color(uiColor: .systemGroupedBackground)
                #else
                Color.gray.opacity(0.08)
                #endif
            }
        }
        .task {
            await loadRemoteProfile()
        }
        .onChange(of: tab) { _, _ in
            dismissProfileNameKeyboard()
        }
        .onChange(of: focusedProfileNameField) { _, new in
            hubBottomBarSuppressionWhileFocused?.wrappedValue = (new != nil)
            if new != nil {
                profileUtilityPillCollapseOffset = 0
            }
            if new == nil {
                flushProfileNameAutosave()
            }
        }
        .onDisappear {
            hubBottomBarSuppressionWhileFocused?.wrappedValue = false
            profileNameAutosaveTask?.cancel()
        }
        .sheet(isPresented: $showDeleteConfirm, onDismiss: {
            deletePassword = ""
            deletePasswordVisible = false
            deleteAccountError = nil
        }) {
            deleteAccountConfirmationSheet
        }
        .onChange(of: showDeleteConfirm) { _, isPresented in
            guard isPresented else { return }
            Task { await refreshNeedsPlatformPasswordForDeletion() }
        }
        .sheet(isPresented: $showApplePayReviewerInfo) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pay with Apple Pay")
                            .font(OnCutsFont.title3(weight: .bold))
                        Text("Typical flow after your provider completes the service:")
                            .font(OnCutsFont.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)

                        ForEach(Array(Self.applePayInstructionSteps.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(OnCutsFont.caption(weight: .bold))
                                    .foregroundStyle(Color.white)
                                    .frame(width: 26, height: 26)
                                    .background {
                                        Circle().fill(Color.oliveGreen)
                                    }
                                    .accessibilityHidden(true)
                                Text(line)
                                    .font(OnCutsFont.body)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 10)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Step \(index + 1): \(line)")
                        }
                    }
                    .padding(22)
                }
                .navigationTitle("Apple Pay & payments")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showApplePayReviewerInfo = false }
                    }
                }
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
        }
        .alert("Are you sure?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                performConfirmedSignOut()
            }
        } message: {
            Text("You will be signed out and need to sign in again to use your account.")
        }
    }

    #if canImport(UIKit)
    private var deleteAccountPasswordFieldFill: Color {
        Color(uiColor: UIColor.secondarySystemGroupedBackground)
    }
    
    private var deleteAccountPasswordFieldBorderColor: Color {
        Color(uiColor: UIColor.separator)
    }
    #else
    private var deleteAccountPasswordFieldFill: Color {
        Color.gray.opacity(0.14)
    }
    
    private var deleteAccountPasswordFieldBorderColor: Color {
        Color.neutral200
    }
    #endif

    /// Same password visibility pattern as `EmailPasswordSignInView` (eye icon, not a separate toggle).
    private var deleteAccountConfirmationSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if needsPlatformPasswordForDeletion {
                    Text("This permanently removes your account. Because you use Sign in with Apple without a \(AppBranding.displayName) password, the next step asks for Face ID, Touch ID, or your device passcode to confirm.")
                        .font(OnCutsFont.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This permanently removes your account. Enter your password to confirm.")
                        .font(OnCutsFont.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let deleteAccountError, !deleteAccountError.isEmpty {
                    Text(deleteAccountError)
                        .font(OnCutsFont.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !needsPlatformPasswordForDeletion {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(OnCutsFont.caption(weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Group {
                                if deletePasswordVisible {
                                    TextField("Password", text: $deletePassword)
                                } else {
                                    SecureField("Password", text: $deletePassword)
                                }
                            }
                            .textContentType(.password)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .foregroundStyle(Color.primary)
                            .tint(Color.accentColor)

                            Button {
                                deletePasswordVisible.toggle()
                            } label: {
                                Image(systemName: deletePasswordVisible ? "eye.slash.fill" : "eye.fill")
                                    .font(OnCutsFont.body(weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 28, minHeight: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(deletePasswordVisible ? "Hide password" : "Show password")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: .radiusMedium)
                                .fill(deleteAccountPasswordFieldFill)
                                .overlay {
                                    RoundedRectangle(cornerRadius: .radiusMedium)
                                        .strokeBorder(deleteAccountPasswordFieldBorderColor, lineWidth: 1)
                                }
                        }
                    }
                }

                Button(role: .destructive) {
                    Task { await performDeleteAccount() }
                } label: {
                    Text("Delete account")
                        .font(OnCutsFont.body(weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled((!needsPlatformPasswordForDeletion && deletePassword.isEmpty) || isDeleting)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Delete account?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showDeleteConfirm = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func performConfirmedSignOut() {
        UserProfileBarberIdCache.clear(for: session.userId)
        sessionManager.logout()
        onAccountMenuSignOut?()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .profileInfo:
            profileInfoTab
        case .security:
            securityTab
        }
    }

    private var profileUtilityPillChrome: some View {
        editTabBar
            .padding(.horizontal, .space4)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .top)
            .opacity(Double(profileUtilityChromeProgress))
            .offset(y: -profileUtilityPillHideTravel)
            .animation(nil, value: profileUtilityChromeProgress)
            .allowsHitTesting(profileUtilityChromeProgress > 0.12)
    }

    private var editTabBar: some View {
        HStack(spacing: 4) {
            ForEach(EditProfileMainTab.allCases) { item in
                profileUtilityPillSegment(item)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule()
                .stroke(Color.lavaShellCream, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func profileUtilityPillSegmentFill(_ item: EditProfileMainTab) -> Color {
        switch item {
        case .profileInfo:
            return Color.lavaShellCream.opacity(0.22)
        case .security:
            return Color.red.opacity(0.24)
        }
    }

    private func profileUtilityPillSegment(_ item: EditProfileMainTab) -> some View {
        let isSelected = tab == item
        return Button {
            dismissProfileNameKeyboard()
            guard !isSelected else { return }
            #if os(iOS)
            ProfileUtilityPillHaptics.selectionChanged()
            #endif
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                tab = item
            }
        } label: {
            Text(item.title)
                .font(OnCutsFont.system(size: 14, weight: isSelected ? .semibold : .medium, design: .default))
                .foregroundStyle(profileUtilityPillSegmentForeground(item, isSelected: isSelected))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(profileUtilityPillSegmentFill(item))
                    }
                }
                .contentShape(Capsule())
        }
        #if os(iOS)
        .buttonStyle(ProfileUtilityPillPressStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func profileUtilityPillSegmentForeground(_ item: EditProfileMainTab, isSelected: Bool) -> Color {
        switch item {
        case .security:
            return isSelected ? .red : .red.opacity(0.55)
        case .profileInfo:
            return isSelected ? Color.lavaShellCream : Color.lavaShellCream.opacity(0.55)
        }
    }

    private var profileInfoTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            avatarSection
                .onTapGesture { dismissProfileNameKeyboard() }

            UserProfileGlassSectionHeader(title: "Basic Information")
                .onTapGesture { dismissProfileNameKeyboard() }

            if profileNameManagedBySignInWithApple {
                signInWithAppleReadOnlyProfileSection
            } else {
                UserProfileGlassTile {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("First Name")
                            .font(OnCutsFont.caption(weight: .semibold))
                            .foregroundStyle(.secondary)
                            .onTapGesture { dismissProfileNameKeyboard() }
                        TextField("First name", text: $firstName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedProfileNameField, equals: .firstName)
                            .submitLabel(.done)
                            .onSubmit { focusedProfileNameField = nil }
                    }
                }
                UserProfileGlassTile {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Last Name")
                            .font(OnCutsFont.caption(weight: .semibold))
                            .foregroundStyle(.secondary)
                            .onTapGesture { dismissProfileNameKeyboard() }
                        TextField("Last name", text: $lastName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedProfileNameField, equals: .lastName)
                            .submitLabel(.done)
                            .onSubmit { focusedProfileNameField = nil }
                    }
                }
            }
        }
        .onChange(of: firstName) { _, _ in
            guard !profileNameManagedBySignInWithApple else { return }
            scheduleProfileNameAutosave()
        }
        .onChange(of: lastName) { _, _ in
            guard !profileNameManagedBySignInWithApple else { return }
            scheduleProfileNameAutosave()
        }
    }

    private var signInWithAppleReadOnlyProfileSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UserProfileGlassTile {
                VStack(alignment: .leading, spacing: 10) {
                    Text("First Name")
                        .font(OnCutsFont.caption(weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(signInWithAppleReadOnlyFirstLine)
                        .font(OnCutsFont.body)
                        .foregroundStyle(.primary)
                }
            }
            UserProfileGlassTile {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Last Name")
                        .font(OnCutsFont.caption(weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(signInWithAppleReadOnlyLastLine)
                        .font(OnCutsFont.body)
                        .foregroundStyle(.primary)
                }
            }
            Text("Your name comes from Sign in with Apple. To change it, update your Apple ID in Settings.")
                .font(OnCutsFont.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signInWithAppleReadOnlyFirstLine: String {
        let t = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let split = splitDisplayName(session.displayName)
        let s = split.0.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "—" : s
    }

    private var signInWithAppleReadOnlyLastLine: String {
        let t = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let split = splitDisplayName(session.displayName)
        let s = split.1.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "—" : s
    }

    private var securityTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            UserProfileGlassSectionHeader(title: "Account security")
            if !showsIntegratedAccountMenu {
                UserProfileGlassTile {
                    NavigationLink {
                        ProfileBlockedMessagingUsersView(sessionManager: sessionManager)
                    } label: {
                        integratedAccountRow(
                            title: "Blocked people"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button(role: .destructive) {
                    showSignOutConfirm = true
                } label: {
                    Text("Sign Out")
                        .font(OnCutsFont.body(weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
            }

            Text("Deleting your account removes your profile and associated data from \(AppBranding.displayName) where supported by the server.")
                .font(OnCutsFont.caption)
                .foregroundStyle(.secondary)
            Button(role: .destructive) {
                deleteAccountError = nil
                showDeleteConfirm = true
            } label: {
                Text("Delete Account")
                    .font(OnCutsFont.body(weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private func integratedAccountRow(
        title: String,
        emphasizeSignOut: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(OnCutsFont.body)
                .foregroundStyle(emphasizeSignOut ? Color.red : Color.primary)
            Spacer(minLength: 8)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var integratedAccountMenuSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            UserProfileGlassSectionHeader(title: "Account")
            UserProfileGlassTile {
                VStack(spacing: 0) {
                    Link(destination: AppBranding.privacyPolicyURL) {
                        integratedAccountRow(
                            title: "Privacy Policy"
                        )
                    }

                    integratedAccountDivider()

                    Link(destination: AppBranding.termsOfServiceURL) {
                        integratedAccountRow(
                            title: "Terms of Service"
                        )
                    }

                    integratedAccountDivider()

                    NavigationLink {
                        ProfileBlockedMessagingUsersView(sessionManager: sessionManager)
                    } label: {
                        integratedAccountRow(
                            title: "Blocked people"
                        )
                    }
                    .buttonStyle(.plain)

                    integratedAccountDivider()

                    Button {
                        showApplePayReviewerInfo = true
                    } label: {
                        integratedAccountRow(
                            title: "Apple Pay & payments"
                        )
                    }
                    .buttonStyle(.plain)

                    integratedAccountDivider()

                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        integratedAccountRow(
                            title: "Sign Out",
                            emphasizeSignOut: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func integratedAccountDivider() -> some View {
        Divider()
            .opacity(0.35)
    }

    private var avatarSection: some View {
        LiquidProfileUpload(
            imageURL: resolvedAvatarURL,
            onUpload: { data in
                try await uploadProfileImageThrowing(data)
            }
        )
    }

    private var resolvedAvatarURL: URL? {
        if let avatarURLString, let u = ProfileImageURLResolver.url(from: avatarURLString) { return u }
        if let u = ProfileImageURLResolver.url(from: session.profileImageURL) { return u }
        return nil
    }

    @MainActor
    private func loadRemoteProfile() async {
        isLoadingRemote = true
        formError = nil
        defer {
            syncLastPersistedNameBaseline()
            isLoadingRemote = false
        }

        applyLocalFallbacks()

        do {
            let remote = try await UserProfileAPI.fetchProfile(userId: session.userId, bearerToken: sessionManager.currentSession?.token)
            guard idsMatch(remote.id.stringValue, session.userId) else {
                formError = "Profile response did not match the signed-in user."
                return
            }
            if let f = remote.first_name {
                firstName = f.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let l = remote.last_name {
                lastName = l.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            email = remote.email
            // Consumer (student): do not load self-bio for editing — not required at this time.
            // if let b = remote.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
            //     bio = b
            // }
            if session.role != .student, let b = remote.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
                bio = b
            }
            if let u = remote.profile_picture_url?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                avatarURLString = u
            }
            await refreshNeedsPlatformPasswordForDeletion()
        } catch {
            if UserProfileAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
                onDismiss()
                return
            }
            applyLocalFallbacks()
            await refreshNeedsPlatformPasswordForDeletion()
        }
    }

    /// Drives password vs Face ID / Touch ID / passcode confirmation for account deletion.
    private func refreshNeedsPlatformPasswordForDeletion() async {
        guard let t = sessionManager.currentSession?.token, !t.isEmpty else {
            needsPlatformPasswordForDeletion = false
            return
        }
        do {
            needsPlatformPasswordForDeletion = try await UserProfileAPI.authMeIndicatesNeedsPlatformPassword(bearerToken: t)
        } catch {
            needsPlatformPasswordForDeletion = false
        }
    }

    private func applyLocalFallbacks() {
        let split = splitDisplayName(session.displayName)
        // Only seed both names from `session.displayName` when we have no local values yet.
        // Filling a single empty field from split would prevent editing first and last independently
        // (e.g. last name only, or a cleared field would keep being restored from the combined name).
        if firstName.isEmpty && lastName.isEmpty {
            firstName = split.0
            lastName = split.1
        }
        if email.isEmpty { email = session.email }
        // Consumer (student): no local self-bio fallback — see `UserProfileBioStore` (barber / non-student only).
        if session.role != .student, bio.isEmpty {
            var local = UserProfileBioStore.bio(for: session.userId)
            if local.isEmpty, session.role == .barber, let api = barberBioFallback?.trimmingCharacters(in: .whitespacesAndNewlines), !api.isEmpty {
                local = api
            }
            bio = local
        }
        if avatarURLString == nil {
            avatarURLString = session.profileImageURL
        }
    }

    @MainActor
    private func uploadProfileImageThrowing(_ data: Data) async throws {
        do {
            let url = try await UserProfileAPI.uploadProfilePhoto(
                imageData: data,
                fileName: "profile.jpg",
                mimeType: "image/jpeg",
                bearerToken: sessionManager.currentSession?.token
            )
            avatarURLString = url
            sessionManager.applyProfileFromServer(
                displayName: composedDisplayName(),
                email: email.isEmpty ? session.email : email,
                profileImageURL: url
            )
        } catch {
            if UserProfileAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
                onDismiss()
                return
            }
            throw error
        }
    }

    private func normalizedNamePair() -> (String, String) {
        let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (f, l)
    }

    private func syncLastPersistedNameBaseline() {
        let p = normalizedNamePair()
        lastPersistedFirst = p.0
        lastPersistedLast = p.1
    }

    private func scheduleProfileNameAutosave() {
        guard !profileNameManagedBySignInWithApple else { return }
        guard !isLoadingRemote else { return }
        profileNameAutosaveTask?.cancel()
        profileNameAutosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            await saveProfile()
        }
    }

    private func flushProfileNameAutosave() {
        guard !isLoadingRemote else { return }
        profileNameAutosaveTask?.cancel()
        profileNameAutosaveTask = nil
        Task { await saveProfile() }
    }

    @MainActor
    private func saveProfile() async {
        guard !profileNameManagedBySignInWithApple else { return }
        while true {
            let p = normalizedNamePair()
            if p.0 == lastPersistedFirst && p.1 == lastPersistedLast { return }

            if isSaving {
                try? await Task.sleep(nanoseconds: 60_000_000)
                continue
            }

            isSaving = true
            formError = nil
            defer { isSaving = false }

            let display = composedDisplayName()
            // Consumers: never persist a self-bio from this screen; API still expects `bio` — send empty.
            let bioForAPI = session.role == .student ? "" : bio
            do {
                try await UserProfileAPI.updateProfile(
                    userId: session.userId,
                    bearerToken: sessionManager.currentSession?.token,
                    firstName: p.0,
                    lastName: p.1,
                    displayName: display,
                    bio: bioForAPI
                )
                if session.role != .student {
                    UserProfileBioStore.setBio(bio, for: session.userId)
                }
                sessionManager.applyProfileFromServer(
                    displayName: display,
                    email: email.isEmpty ? session.email : email,
                    profileImageURL: avatarURLString ?? session.profileImageURL
                )
                lastPersistedFirst = p.0
                lastPersistedLast = p.1
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                await onSaved()
            } catch {
                if UserProfileAPI.isUnauthorizedHTTPError(error) {
                    await sessionManager.recoverSessionAfterUnauthorized()
                    onDismiss()
                    return
                }
                formError = error.localizedDescription
                return
            }

            // If the user edited a name while this save was in flight, loop and persist the latest values.
        }
    }

    @MainActor
    private func performDeleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        deleteAccountError = nil
        defer { isDeleting = false }
        do {
            if needsPlatformPasswordForDeletion {
                #if canImport(LocalAuthentication)
                do {
                    try await DeleteAccountDeviceOwnerGate.confirmForAccountDeletion()
                } catch {
                    if let laErr = error as? LAError, laErr.code == .userCancel {
                        deleteAccountError = "Deletion cancelled."
                    } else {
                        deleteAccountError = error.localizedDescription
                    }
                    return
                }
                #else
                deleteAccountError = "This platform cannot confirm with Face ID or Touch ID."
                return
                #endif
                try await UserProfileAPI.deleteAccount(userId: session.userId, bearerToken: sessionManager.currentSession?.token, password: nil)
            } else {
                try await UserProfileAPI.deleteAccount(userId: session.userId, bearerToken: sessionManager.currentSession?.token, password: deletePassword)
            }
            deletePassword = ""
            showDeleteConfirm = false
            onDismiss()
            sessionManager.logout()
        } catch {
            deleteAccountError = error.localizedDescription
        }
    }

    private func composedDisplayName() -> String {
        let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = [f, l].filter { !$0.isEmpty }.joined(separator: " ")
        if !joined.isEmpty { return joined }
        return session.displayName
    }

    private func splitDisplayName(_ s: String) -> (String, String) {
        let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.isEmpty { return ("", "") }
        if parts.count == 1 { return (String(parts[0]), "") }
        return (String(parts[0]), String(parts[1]))
    }

    private func idsMatch(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines) == b.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if canImport(LocalAuthentication)
private enum DeleteAccountDeviceOwnerGate {
    static func confirmForAccountDeletion() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var nsErr: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &nsErr) else {
            throw nsErr ?? NSError(
                domain: LAErrorDomain,
                code: LAError.authenticationFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "This device cannot confirm with Face ID, Touch ID, or passcode right now."]
            )
        }
        let reason = "Confirm permanent deletion of your \(AppBranding.displayName) account."
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(
                        throwing: NSError(domain: "OnCuts", code: -1, userInfo: [NSLocalizedDescriptionKey: "Authentication failed."])
                    )
                }
            }
        }
    }
}
#endif

#if canImport(UIKit)
/// Full-screen invisible overlay while a profile name field is focused: passes taps through to `UITextField` / `UIControl`,
/// and ends editing when the user taps elsewhere (SwiftUI-only gestures are unreliable here).
private final class ProfileNameFieldOutsideTapOverlayView: UIView {
    var onOutsideTap: (() -> Void)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        guard bounds.contains(point) else { return nil }
        guard let window else { return nil }
        let pInWindow = convert(point, to: window)

        isUserInteractionEnabled = false
        let hitBelow = window.hitTest(pInWindow, with: event)
        isUserInteractionEnabled = true

        guard let hit = hitBelow else { return self }

        var v: UIView? = hit
        while let cur = v {
            if cur is UITextField || cur is UITextView { return nil }
            if cur is UIControl { return nil }
            let traits = cur.accessibilityTraits
            if traits.contains(.link) || traits.contains(.button) { return nil }
            v = cur.superview
        }
        return self
    }

    @objc func handleOutsideTap() {
        onOutsideTap?()
    }
}

private struct ProfileNameFieldOutsideTapOverlay: UIViewRepresentable {
    var isActive: Bool
    var onOutsideTap: () -> Void

    func makeUIView(context: Context) -> ProfileNameFieldOutsideTapOverlayView {
        let v = ProfileNameFieldOutsideTapOverlayView()
        v.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: v, action: #selector(ProfileNameFieldOutsideTapOverlayView.handleOutsideTap))
        tap.cancelsTouchesInView = false
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ uiView: ProfileNameFieldOutsideTapOverlayView, context: Context) {
        uiView.isHidden = !isActive
        uiView.isUserInteractionEnabled = isActive
        uiView.onOutsideTap = onOutsideTap
    }
}
#endif

// MARK: - Previews

#Preview("Student profile") {
    let m = AppSessionManager()
    m.mockLogin(as: .student)
    return NavigationStack {
        UserProfileView(sessionManager: m, coordinator: MainCoordinator(sessionManager: m))
    }
}

#Preview("Barber profile") {
    let m = AppSessionManager()
    m.mockLogin(as: .barber)
    return NavigationStack {
        UserProfileView(sessionManager: m, coordinator: MainCoordinator(sessionManager: m))
    }
}
