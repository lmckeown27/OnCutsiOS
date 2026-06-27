//
//  ConsumerHomeScreen.swift
//  Intera
//
//  Main home screen for consumers to browse service providers and manage bookings
//

import CampusCutsModule
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Home shell (`CampusCutsChatManager`)

/// Where search + category chrome is drawn relative to the provider list and `GlassEffectContainer`.
private enum GuestAuthResumeAction {
    case none
    case signInOptions
    case signUp
}

private enum BrowseStickyChromePlacement {
    /// Chrome overlays the `ScrollView` (fine for solid cards; Liquid Glass can still paint above it).
    case overlayOnScroll
    /// Caller shows `StickyProviderBrowseChrome` **above** `GlassEffectContainer` so glass cards cannot occlude it.
    case externalAboveGlassContainer
}

private struct BrowseListStickyChromeModifier: ViewModifier {
    let placement: BrowseStickyChromePlacement
    @Binding var searchText: String
    @Binding var selectedCategory: ServiceProvider.ServiceCategory?
    let providers: [ServiceProvider]
    let onHeaderHeightChange: (CGFloat) -> Void
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if placement == .overlayOnScroll {
            content
                .overlay(alignment: .top) {
                    StickyProviderBrowseChrome(
                        searchText: $searchText,
                        selectedCategory: $selectedCategory,
                        providers: providers
                    )
                    .zIndex(1)
                }
                .onPreferenceChange(StickyBrowseHeaderHeightKey.self, perform: onHeaderHeightChange)
        } else {
            content
        }
    }
}

struct ConsumerHomeScreen: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator

    @EnvironmentObject private var chatViewModel: ChatViewModel
    
    @Namespace private var providerGlassNamespace

    @State private var providerVM = ProviderViewModel()
    /// Bookings list API not wired in the shell yet; empty avoids fake “active booking” gating on real barber data.
    @State private var bookings: [Booking] = []
    /// Live consumer rows for home activity pill + booking gating (`GET /bookings-simple`).
    @State private var consumerBookingRows: [ConsumerBookingSimpleRow] = []
    @State private var showProfileMenu = false
    @State private var showGuestAuthEntrySheet = false
    @State private var guestAuthResumeAction: GuestAuthResumeAction = .none
    @State private var oauthSignInShowsCreateAccountLink = true
    @State private var showOAuthSignInSheet = false
    @StateObject private var appleOAuthPostSignInCoordinator = AppleOAuthPostSignInCoordinator()
    @State private var showIntegratedSignUpSheet = false
    @State private var showLoginPrompt = false
    @State private var selectedProvider: ServiceProvider?
    /// When `false`, the browse list receives taps even if the detail overlay is still animating out.
    @State private var isProviderDetailCapturingTouches = false
    /// Stays `true` from open until overlay `onDisappear` (or fallback) so browse scroll/geometry stay locked through dismiss animation.
    @State private var isProviderDetailOverlayBlockingBrowse = false
    /// Fresh identity per open so overlay subtrees fully dismantle (avoids ghost hit blockers).
    @State private var providerDetailPresentationID = UUID()
    @State private var navigationPath = NavigationPath()
    @State private var selectedCategory: ServiceProvider.ServiceCategory? = nil // For filtering (pre–iOS 26 browse)
    @State private var searchText = ""
    @State private var showMessagesInbox = false
    @State private var showBookingChatsHub = false
    /// iOS: “maximum distance” sheet for geo-filtered `GET /barbers`.
    @State private var showMaxDistanceSheet = false
    /// New seed reshuffles list order (category change, pull-to-refresh).
    @State private var providerListShuffleSeed: UInt64 = UInt64.random(in: 1 ... UInt64.max)
    /// Measured height of the sticky search + category header (for scroll underlap).
    @State private var stickyBrowseHeaderHeight: CGFloat = 0
    
    private var providers: [ServiceProvider] { providerVM.providersForDisplay }
    
    private var isLoading: Bool { providerVM.isLoading }
    
    /// Category + search filter; shuffled when search is empty (mixed order for “All” and each tab).
    private var displayedProviders: [ServiceProvider] {
        let byCategory: [ServiceProvider] = {
            if #available(iOS 26.0, macOS 26.0, *) {
                return providerVM.providersFilteredByServiceType(providers)
            }
            guard let category = selectedCategory else {
                return providers
            }
            return providers.filter { $0.category == category }
        }()
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = byCategory.filter { $0.matchesConsumerSearch(query: searchText) }
        guard !q.isEmpty else {
            return matched.shuffledWithStableSeed(providerListShuffleSeed)
        }
        return matched.sorted {
            let p0 = $0.consumerSearchSortPriority(query: q)
            let p1 = $1.consumerSearchSortPriority(query: q)
            if p0 != p1 { return p0 < p1 }
            return $0.businessName.localizedCaseInsensitiveCompare($1.businessName) == .orderedAscending
        }
    }
    
    var upcomingBookings: [Booking] {
        bookings.filter { $0.status == .pending || $0.status == .accepted }
    }
    
    var currentBooking: Booking? {
        upcomingBookings.first
    }

    /// Any non-past PENDING/ACCEPTED booking from the simple API (drives provider detail “already booked” hints).
    private var hasActiveConsumerBooking: Bool {
        consumerBookingRows.contains { row in
            let u = row.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard u == "PENDING" || u == "ACCEPTED" else { return false }
            return row.scheduleSegment() != .past
        }
    }

    private var homeTodayBookingHighlight: HomeTodayBookingHighlight? {
        guard sessionManager.isAuthenticated else { return nil }
        return HomeTodayBookingHighlight.pickTodayHighlight(from: consumerBookingRows)
    }

    private var homePendingPaymentHighlight: HomePendingPaymentHighlight? {
        guard sessionManager.isAuthenticated else { return nil }
        return HomePendingPaymentHighlight.pickAwaitingPayment(from: consumerBookingRows)
    }

    /// Hub dot + aligns with app icon: **ACCEPTED** upcoming/today only (not your own outgoing PENDING request).
    private var upcomingBookingIndicatorCount: Int {
        guard sessionManager.isAuthenticated else { return 0 }
        return consumerBookingRows.upcomingBookingNotificationBadgeCount
    }
    
    var pastBookings: [Booking] {
        bookings.filter { $0.status == .completed || $0.status == .cancelled }
    }

    private func consumerHomeRow(bookingId: String) -> ConsumerBookingSimpleRow? {
        let key = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        return consumerBookingRows.first { $0.id == key }
    }

    /// Item-based thread only when the home stack has no path pushes (browse / barber chat).
    private var homeShellMessagingHandoffWhenPathEmpty: Binding<ChatViewModel.BookingMessagingThreadHandoff?> {
        Binding(
            get: {
                navigationPath.isEmpty ? chatViewModel.homeStackMessagingHandoff : nil
            },
            set: { chatViewModel.homeStackMessagingHandoff = $0 }
        )
    }

    @ViewBuilder
    private func homeMessagingThreadDestination(
        _ handoff: ChatViewModel.BookingMessagingThreadHandoff,
        onDismissClearHandoff: @escaping () -> Void
    ) -> some View {
        MessagingConversationView(
            conversationId: handoff.conversationId,
            sessionManager: sessionManager,
            coordinator: coordinator,
            initialBooking: handoff.bookingSnapshot,
            counterpartyAvatarURLString: handoff.counterpartyAvatarURLString,
            counterpartyFallbackDisplayName: handoff.counterpartyFallbackName,
            initialDraftText: handoff.initialDraft.isEmpty ? nil : handoff.initialDraft,
            onNavigationVisibilityChanged: { visible, _ in
                if !visible { onDismissClearHandoff() }
            },
            onResyncSharedHubInboxSilently: {
                await chatViewModel.reloadInboxSilently(sessionManager: sessionManager)
            },
            counterpartyUserId: handoff.counterpartyMessagingUserId
        )
        #if os(iOS)
        .interaNavigationShellBackgroundClear()
        #endif
    }

    @ViewBuilder
    private func consumerHomeBookingStackDestination(_ route: ConsumerHomeBookingStackRoute) -> some View {
        switch route {
        case .detail(let bookingId, let presentationID):
            if let row = consumerHomeRow(bookingId: bookingId) {
                ConsumerBookingDetailView(
                    row: row,
                    sessionManager: sessionManager,
                    coordinator: coordinator,
                    bookingDetailPresentationID: presentationID,
                    hasActiveConsumerBooking: hasActiveConsumerBooking,
                    onShowLogin: { showOAuthSignInSheet = true }
                )
                .id(presentationID)
                #if os(iOS)
                .interaNavigationShellBackgroundClear()
                #endif
            } else {
                ContentUnavailableView(
                    "Booking unavailable",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Pull to refresh on Home or reopen the booking from Bookings.")
                )
            }
        case .messagingThread:
            EmptyView()
        }
    }

    /// Split from `body` so the compiler can type-check the navigation stack in reasonable time.
    @ViewBuilder
    private var consumerHomeNavigationStackInner: some View {
        Group {
            // Development: Always show browse view
            if #available(iOS 26.0, macOS 26.0, *) {
                consumerBrowseLiquidGlassRoot
            } else {
                browseView()
                    #if os(iOS)
                    .background(Color.clear)
                    #else
                    .background(Color.neutral50.ignoresSafeArea())
                    #endif
            }
        }
        .navigationTitle(coordinator.selectedService?.name ?? "")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Back button to service selection
                ToolbarItem(placement: {
                    #if os(iOS)
                    return .topBarLeading
                    #else
                    return .automatic
                    #endif
                }()) {
                    Button {
                        coordinator.clearServiceSelection()
                    } label: {
                        HStack(spacing: .space1) {
                            Image(systemName: "chevron.left")
                                .font(InteraFont.body)
                                .foregroundStyleInteraShellIcon()
                            Text("Services")
                                .font(InteraFont.bodyMedium)
                                .foregroundStyleOliveGreen()
                        }
                    }
                }
                
                #if os(iOS)
                if sessionManager.isAuthenticated, showsLegacyNavigationProfileButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        profileButton
                    }
                }
                if #unavailable(iOS 26.0) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showMaxDistanceSheet = true
                        } label: {
                            Image(systemName: "location.circle")
                                .font(InteraFont.body.weight(.semibold))
                                .foregroundStyleInteraShellIcon()
                        }
                        .accessibilityLabel("Maximum search distance")
                    }
                }
                #else
                if sessionManager.isAuthenticated, showsLegacyNavigationProfileButton {
                    ToolbarItem(placement: .automatic) {
                        profileButton
                    }
                }
                #endif
            }
            #if os(iOS)
            .interaNavigationShellBackgroundClear()
            .sheet(isPresented: $showMaxDistanceSheet) {
                ConsumerBrowseDistanceSheet {
                    Task { await loadProviders() }
                }
            }
            #endif
            .sheet(isPresented: $showProfileMenu) {
                ProfileMenuSheet(
                    sessionManager: sessionManager,
                    coordinator: coordinator
                )
            }
            .sheet(isPresented: $showGuestAuthEntrySheet, onDismiss: {
                switch guestAuthResumeAction {
                case .signInOptions:
                    oauthSignInShowsCreateAccountLink = false
                    showOAuthSignInSheet = true
                case .signUp:
                    showIntegratedSignUpSheet = true
                case .none:
                    break
                }
                guestAuthResumeAction = .none
            }) {
                if #available(iOS 17.0, macOS 14.0, *) {
                    GuestAuthEntrySheet(
                        isPresented: $showGuestAuthEntrySheet,
                        onSignIn: { guestAuthResumeAction = .signInOptions },
                        onSignUp: { guestAuthResumeAction = .signUp }
                    )
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    #endif
                }
            }
            .sheet(isPresented: $showOAuthSignInSheet, onDismiss: {
                oauthSignInShowsCreateAccountLink = true
                let c = appleOAuthPostSignInCoordinator
                guard !c.appleBackendExchangeInProgress else { return }
                c.reset()
            }) {
                if #available(iOS 17.0, macOS 14.0, *) {
                    OAuthProviderSignInSheet(
                        sessionManager: sessionManager,
                        appleOAuthFollowUp: appleOAuthPostSignInCoordinator,
                        onFinished: { showOAuthSignInSheet = false },
                        onRequestEmailSignUp: {
                            showOAuthSignInSheet = false
                            showIntegratedSignUpSheet = true
                        },
                        showsCreateAccountLink: oauthSignInShowsCreateAccountLink
                    )
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    #endif
                }
            }
            .sheet(isPresented: $showIntegratedSignUpSheet) {
                if #available(iOS 17.0, macOS 14.0, *) {
                    IntegratedSignUpSheet(sessionManager: sessionManager, onFinished: {
                        showIntegratedSignUpSheet = false
                    })
                    #if os(iOS)
                    .presentationDetents([.large])
                    #endif
                }
            }
            .navigationDestination(isPresented: $showLoginPrompt) {
                LoginView(sessionManager: sessionManager)
            }
            .navigationDestination(for: ProviderDetailNavigationRoute.self) { route in
                if let provider = providers.first(where: { $0.id == route.providerId }) {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        ServiceProviderLiquidGlassNavigationDetailPage(
                            provider: provider,
                            sessionManager: sessionManager,
                            hasCurrentBooking: hasActiveConsumerBooking,
                            onShowLogin: {
                                showOAuthSignInSheet = true
                            }
                        )
                    }
                } else {
                    ContentUnavailableView(
                        "Provider unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Pull to refresh or go back and open this provider again.")
                    )
                }
            }
            .navigationDestination(for: ConsumerHomeBookingStackRoute.self) { route in
                consumerHomeBookingStackDestination(route)
            }
            .navigationDestination(item: homeShellMessagingHandoffWhenPathEmpty) { handoff in
                homeMessagingThreadDestination(handoff) {
                    chatViewModel.homeStackMessagingHandoff = nil
                }
            }
            .navigationDestination(isPresented: $showMessagesInbox) {
                ConversationListView(
                    sessionManager: sessionManager,
                    coordinator: coordinator,
                    onBrowseServiceProviders: { showMessagesInbox = false }
                )
            }
            .navigationDestination(isPresented: $showBookingChatsHub) {
                ConsumerBookingsHubView(
                    sessionManager: sessionManager,
                    coordinator: coordinator,
                    onShowLogin: { showOAuthSignInSheet = true }
                )
                #if os(iOS)
                .interaNavigationShellBackgroundClear()
                #endif
            }
            .overlay {
                if let provider = selectedProvider {
                    let overlayPresentationID = providerDetailPresentationID
                    if #available(iOS 26.0, macOS 26.0, *) {
                        ServiceProviderGlassMatchedDetailOverlay(
                            provider: provider,
                            namespace: providerGlassNamespace,
                            sessionManager: sessionManager,
                            hasCurrentBooking: hasActiveConsumerBooking,
                            capturesTouches: isProviderDetailCapturingTouches,
                            onDismiss: { dismissProviderDetail() },
                            onShowLogin: {
                                showOAuthSignInSheet = true
                            },
                            onBookingRequestCompleted: { dismissProviderDetail() },
                            onOverlayDidDisappear: {
                                finalizeProviderDetailOverlayTeardown(expectedPresentationID: overlayPresentationID)
                            }
                        )
                        .id(overlayPresentationID)
                        .zIndex(100)
                    } else {
                        ServiceProviderDetailPresentationOverlay(
                            provider: provider,
                            sessionManager: sessionManager,
                            hasCurrentBooking: hasActiveConsumerBooking,
                            capturesTouches: isProviderDetailCapturingTouches,
                            onDismiss: { dismissProviderDetail() },
                            onShowLogin: {
                                showOAuthSignInSheet = true
                            },
                            onBookingRequestCompleted: { dismissProviderDetail() },
                            onOverlayDidDisappear: {
                                finalizeProviderDetailOverlayTeardown(expectedPresentationID: overlayPresentationID)
                            }
                        )
                        .id(overlayPresentationID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(100)
                    }
                }
            }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            consumerHomeNavigationStackInner
        }
        .onChange(of: navigationPath.count) { _, count in
            if count == 0 {
                chatViewModel.clearPathBackedMessagingItemHandoffs()
            }
        }
        .task {
            await loadProviders()
            await loadConsumerBookingsForHome()
            await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager)
        }
        .onChange(of: sessionManager.isAuthenticated) { _, _ in
            Task { await loadProviders() }
            Task { await loadConsumerBookingsForHome() }
            Task { await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .messagingUnreadCountShouldRefresh)) { _ in
            Task { await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .campusCutsStartProviderChat)) { output in
            guard let id = output.userInfo?["providerID"] as? String else { return }
            Task { @MainActor in
                openChatForBarberProfileId(id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .interaOpenMessagingConversation)) { output in
            Task { @MainActor in
                guard let cid = InteraPushNavigationPayload.conversationId(from: output.userInfo) else { return }
                chatViewModel.pendingPushConversationId = cid
                showMessagesInbox = true
                await Task.yield()
                await Task.yield()
                await Task.yield()
                await chatViewModel.presentHubThreadFromMessagePush(
                    conversationId: cid,
                    sessionManager: sessionManager
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .interaOpenBookingDetail)) { output in
            guard let raw = output.userInfo?["bookingId"] else { return }
            let bid: String? = {
                if let s = raw as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let n = raw as? NSNumber { return n.stringValue }
                if let i = raw as? Int { return String(i) }
                return nil
            }()
            guard let bid, !bid.isEmpty else { return }
            Task { @MainActor in
                chatViewModel.pendingOpenBookingDetailId = bid
                showBookingChatsHub = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .interaNavigateToBookingsAfterBookingRequest)) { _ in
            Task { @MainActor in
                showBookingChatsHub = false
                await loadConsumerBookingsForHome()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .consumerBookingsListShouldRefresh)) { _ in
            Task { await loadConsumerBookingsForHome() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .interaNavigateToConsumerHomeAfterPayment)) { _ in
            Task { @MainActor in
                chatViewModel.pendingOpenBookingDetailId = nil
                chatViewModel.homeStackMessagingHandoff = nil
                navigationPath = NavigationPath()
                showBookingChatsHub = false
                showMessagesInbox = false
                await loadConsumerBookingsForHome()
            }
        }
        .onChange(of: showBookingChatsHub) { _, open in
            if open { navigationPath = NavigationPath() }
        }
        .onChange(of: showMessagesInbox) { _, open in
            if open { navigationPath = NavigationPath() }
        }
    }

    private func openChatForBarberProfileId(_ raw: String) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        if let row = consumerBookingRows.first(where: {
            ($0.barberId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(id) == .orderedSame
        }) {
            Task {
                await chatViewModel.presentMessagingThreadForBooking(
                    row: row,
                    sessionManager: sessionManager,
                    presentationStack: .homeShellNavigation
                )
            }
        } else {
            showMessagesInbox = true
        }
    }

    @MainActor
    private func loadConsumerBookingsForHome() async {
        guard sessionManager.isAuthenticated else {
            consumerBookingRows = []
            #if os(iOS)
            UpcomingBookingAppBadge.syncFromConsumerRows([])
            #endif
            return
        }
        do {
            consumerBookingRows = try await ConsumerBookingsSimpleAPI.fetchConsumerBookings(
                bearerToken: sessionManager.currentSession?.token,
                consumerUserId: sessionManager.currentSession?.userId
            )
            chatViewModel.syncPaymentTakeover(withBookings: consumerBookingRows)
            #if os(iOS)
            UpcomingBookingAppBadge.syncFromConsumerRows(consumerBookingRows)
            #endif
        } catch {
            if ConsumerBookingsSimpleAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
            }
        }
    }

    /// Navigation bar avatar is redundant when the iOS 26+ glass capsule toolbar shows profile.
    private var showsLegacyNavigationProfileButton: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return false
        }
        return true
    }

    #if os(iOS)
    private var consumerBrowseOnMaxDistanceTap: (() -> Void)? {
        { showMaxDistanceSheet = true }
    }
    #else
    private var consumerBrowseOnMaxDistanceTap: (() -> Void)? { nil }
    #endif
    
    // MARK: - iOS 26+ Liquid Glass browse + morphing detail
    
    @available(iOS 26.0, macOS 26.0, *)
    private var consumerBrowseLiquidGlassRoot: some View {
        GlassHeaderProviderBrowse(
            searchText: $searchText,
            selectedServiceType: Binding(
                get: { providerVM.selectedServiceType },
                set: { providerVM.selectedServiceType = $0 }
            ),
            displayedProviders: displayedProviders,
            isLoading: isLoading,
            glassNamespace: providerGlassNamespace,
            fallbackProfileImageURL: toolbarProfileFallbackURL,
            unreadMessageCount: chatViewModel.unreadMessageCount,
            upcomingBookingCount: upcomingBookingIndicatorCount,
            onMessagesTap: {
                if sessionManager.isAuthenticated {
                    showMessagesInbox = true
                } else {
                    showOAuthSignInSheet = true
                }
            },
            onBookingsTap: {
                if sessionManager.isAuthenticated {
                    showBookingChatsHub = true
                } else {
                    showOAuthSignInSheet = true
                }
            },
            onProfileTap: {
                if sessionManager.isAuthenticated {
                    showProfileMenu = true
                } else {
                    showGuestAuthEntrySheet = true
                }
            },
            onProviderTap: { handleProviderTap($0) },
            onRefresh: {
                await loadProviders()
                await loadConsumerBookingsForHome()
                await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager)
            },
            emptyContent: { emptyBrowseState },
            todayBookingActivity: homeTodayBookingHighlight,
            pendingPaymentBooking: homePendingPaymentHighlight,
            onMaxDistanceTap: consumerBrowseOnMaxDistanceTap,
            onTodayBookingReminderTap: { (row: ConsumerBookingSimpleRow) in
                if sessionManager.isAuthenticated {
                    navigationPath = NavigationPath()
                    navigationPath.append(ConsumerHomeBookingStackRoute.bookingsTabDetailPush(for: row))
                } else {
                    showOAuthSignInSheet = true
                }
            },
            onPendingPaymentReminderTap: { (row: ConsumerBookingSimpleRow) in
                guard sessionManager.isAuthenticated else {
                    showOAuthSignInSheet = true
                    return
                }
                chatViewModel.presentPaymentTakeover(forBookingRow: row)
            },
            sessionManager: sessionManager,
            mainCoordinator: coordinator,
            hasActiveConsumerBooking: hasActiveConsumerBooking,
            isProviderDetailCapturingTouches: isProviderDetailCapturingTouches,
            isProviderDetailOverlayPresented: isProviderDetailOverlayBlockingBrowse,
            homeHubPageIndex: .constant(0)
        )
        .onChange(of: providerVM.selectedServiceType) { _, _ in
            providerListShuffleSeed = UInt64.random(in: 1 ... UInt64.max)
        }
        .onChange(of: showMessagesInbox) { _, _ in
            Task { await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager) }
        }
        .onChange(of: showBookingChatsHub) { _, open in
            if !open {
                Task {
                    await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager)
                    await loadConsumerBookingsForHome()
                }
            }
        }
    }

    private var toolbarProfileFallbackURL: URL? {
        ProfileImageURLResolver.url(from: sessionManager.currentSession?.profileImageURL)
    }
    
    // MARK: - Toolbar Items
    
    private var profileButton: some View {
        Button {
            showProfileMenu = true
        } label: {
            AvatarView(
                imageUrl: sessionManager.currentSession?.profileImageURL,
                name: sessionManager.currentSession?.displayName ?? "User",
                size: 32
            )
        }
    }
    
    // MARK: - Browse View
    
    private func browseView(
        useGlassMorphCards: Bool = false,
        useInteractiveLiquidGlassCards: Bool = false,
        stickyChromePlacement: BrowseStickyChromePlacement = .overlayOnScroll
    ) -> some View {
        let morphNS = useGlassMorphCards ? providerGlassNamespace : nil
        let interactiveOnly = useInteractiveLiquidGlassCards && !useGlassMorphCards
        
        let headerInset = stickyBrowseHeaderHeight > 1
            ? stickyBrowseHeaderHeight + .space4
            : 130
        
        let chromeOutsideGlass = stickyChromePlacement == .externalAboveGlassContainer
        
        return VStack(spacing: 0) {
            // Service Provider List — full-screen loading only before we have any cached rows.
            // If `isLoading` alone drove this branch, pull-to-refresh would tear down the `ScrollView`
            // that owns `.refreshable`, cancelling the in-flight URLSession (NSURLErrorCancelled).
            if isLoading && providers.isEmpty {
                if chromeOutsideGlass {
                    VStack(spacing: 0) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CategoryFilterBar(
                        selectedCategory: $selectedCategory,
                        providers: providers
                    )
                    SearchBar(text: $searchText, placeholder: "Search providers")
                        .padding(.horizontal, .space4)
                        .padding(.top, .space3)
                        .padding(.bottom, .space2)
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                }
            } else if displayedProviders.isEmpty {
                if chromeOutsideGlass {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: headerInset)
                        emptyBrowseState
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CategoryFilterBar(
                        selectedCategory: $selectedCategory,
                        providers: providers
                    )
                    SearchBar(text: $searchText, placeholder: "Search providers")
                        .padding(.horizontal, .space4)
                        .padding(.top, .space3)
                        .padding(.bottom, .space2)
                    emptyBrowseState
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: .space4) {
                        ForEach(displayedProviders) { provider in
                            ServiceProviderCard(
                                provider: provider,
                                onTap: { handleProviderTap(provider) },
                                glassMorphNamespace: morphNS,
                                liquidGlassInteractiveWithoutMorph: interactiveOnly
                            )
                        }
                    }
                    .padding(.horizontal, .space4)
                    .padding(.top, headerInset)
                    .padding(.bottom, .space6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                #if os(iOS)
                .scrollBounceBehavior(.always, axes: .vertical)
                #endif
                .scrollDisabled(isProviderDetailOverlayBlockingBrowse)
                .refreshable {
                    await loadProvidersForPullToRefresh()
                }
                .modifier(BrowseListStickyChromeModifier(
                    placement: stickyChromePlacement,
                    searchText: $searchText,
                    selectedCategory: $selectedCategory,
                    providers: providers,
                    onHeaderHeightChange: { stickyBrowseHeaderHeight = $0 }
                ))
                .overlay {
                    if isLoading && !providers.isEmpty {
                        ZStack {
                            Color.black.opacity(0.1)
                            ProgressView()
                                .scaleEffect(1.25)
                                .tint(.white)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            providerListShuffleSeed = UInt64.random(in: 1 ... UInt64.max)
        }
    }
    
    @ViewBuilder
    private var emptyBrowseState: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let noProvidersInRadius = providers.isEmpty

        if trimmed.isEmpty, noProvidersInRadius {
            HomeNoBarbersInRadiusEmptyLabel()
        } else {
            VStack(spacing: .space4) {
                Spacer()

                Image(systemName: trimmed.isEmpty ? "scissors" : "magnifyingglass")
                    .font(InteraFont.system(size: 60))
                    .foregroundStyle(Color.lavaShellCreamTertiary)

                Text(trimmed.isEmpty ? "No providers available" : "No matching providers")
                    .font(InteraFont.headlineMedium)
                    .foregroundStyle(Color.lavaShellCream)

                Text(trimmed.isEmpty ? "Check back later for available service providers" : "Try a different search or category.")
                    .campusCutsStyle(.bodyMedium)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding()
        }
    }
    
    // MARK: - Current Booking View
    
    private var currentBookingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .space6) {
                // Current Booking
                if let current = currentBooking {
                    VStack(alignment: .leading, spacing: .space3) {
                        Text("YOUR BOOKING")
                            .font(InteraFont.labelSmall)
                            .foregroundStyle(Color.neutral500)
                            .padding(.horizontal, .space4)
                        
                        BookingCard(
                            booking: current,
                            showActions: true,
                            onCancel: {
                                cancelBooking(current)
                            },
                            onMessage: {
                                messageBarber(current)
                            }
                        )
                        .padding(.horizontal, .space4)
                    }
                    .padding(.top, .space4)
                }
                
                // Past Bookings (collapsed by default)
                if !pastBookings.isEmpty {
                    VStack(alignment: .leading, spacing: .space3) {
                        Text("HISTORY")
                            .font(InteraFont.labelSmall)
                            .foregroundStyle(Color.neutral500)
                            .padding(.horizontal, .space4)
                            .padding(.top, .space6)
                        
                        ForEach(pastBookings.prefix(3)) { booking in
                            BookingCard(booking: booking)
                                .padding(.horizontal, .space4)
                        }
                        
                        if pastBookings.count > 3 {
                            Text("+ \(pastBookings.count - 3) more")
                                .font(InteraFont.bodySmall)
                                .foregroundStyle(Color.neutral500)
                                .padding(.horizontal, .space4)
                                .padding(.top, .space2)
                        }
                    }
                }
            }
            .padding(.bottom, .space6)
        }
        .refreshable {
            await loadBookings()
        }
    }
    
    private var emptyBookingsState: some View {
        VStack(spacing: .space4) {
            Image(systemName: "calendar")
                .font(InteraFont.system(size: 60))
                .foregroundStyle(Color.lavaShellCreamTertiary)
            
            Text("No booking yet")
                .font(InteraFont.headlineMedium)
                .foregroundStyle(Color.lavaShellCream)
            
            Text("Select a service provider to book your appointment")
                .campusCutsStyle(.bodyMedium)
                .multilineTextAlignment(.center)
        }
        .padding()
        .padding(.top, .space12)
    }
    
    // MARK: - Actions
    
    private func loadProviders() async {
        CampusCutsSessionSync.appSessionManager = sessionManager
        await providerVM.loadProviders(bearerToken: sessionManager.currentSession?.token)
        providerListShuffleSeed = UInt64.random(in: 1 ... UInt64.max)
    }

    @MainActor
    private func loadProvidersForPullToRefresh() async {
        await InteraPullToRefresh.runMainActorAsyncIsolatedFromRefreshableCancellation {
            await loadProviders()
        }
    }
    
    private func loadBookings() async {
        // Simulate API call
        try? await Task.sleep(for: .seconds(1))
        // TODO: Fetch from API
    }
    
    private func cancelBooking(_ booking: Booking) {
        print("Cancel booking: \(booking.id)")
        // TODO: Show confirmation alert and cancel
    }
    
    private func messageBarber(_ booking: Booking) {
        print("Message provider for booking: \(booking.id)")
        // TODO: Open chat
    }
    
    private func presentProviderDetail(_ provider: ServiceProvider) {
        providerDetailPresentationID = UUID()
        isProviderDetailCapturingTouches = true
        isProviderDetailOverlayBlockingBrowse = true
        if #available(iOS 26.0, macOS 26.0, *) {
            withAnimation(LiquidGlassMotion.fluidSpring) {
                selectedProvider = provider
            }
        } else {
            withAnimation(ServiceProviderDetailOverlayAnimation.spring) {
                selectedProvider = provider
            }
        }
    }

    private func dismissProviderDetail() {
        isProviderDetailCapturingTouches = false
        NotificationCenter.default.post(name: .homeHubBrowseShouldResyncUtilityPill, object: nil)
        if #available(iOS 26.0, macOS 26.0, *) {
            withAnimation(LiquidGlassMotion.fluidSpring) {
                selectedProvider = nil
            }
        } else {
            withAnimation(ServiceProviderDetailOverlayAnimation.spring) {
                selectedProvider = nil
            }
        }
        scheduleProviderDetailOverlayTeardownFallback()
    }

    private func finalizeProviderDetailOverlayTeardown(expectedPresentationID: UUID) {
        guard expectedPresentationID == providerDetailPresentationID else { return }
        guard selectedProvider == nil else { return }
        isProviderDetailOverlayBlockingBrowse = false
        isProviderDetailCapturingTouches = false
        NotificationCenter.default.post(name: .homeHubBrowseShouldResyncUtilityPill, object: nil)
    }

    private func scheduleProviderDetailOverlayTeardownFallback() {
        let closingPresentationID = providerDetailPresentationID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 620_000_000)
            guard closingPresentationID == providerDetailPresentationID else { return }
            guard selectedProvider == nil else { return }
            isProviderDetailOverlayBlockingBrowse = false
            isProviderDetailCapturingTouches = false
            NotificationCenter.default.post(name: .homeHubBrowseShouldResyncUtilityPill, object: nil)
        }
    }

    private func handleProviderTap(_ provider: ServiceProvider) {
        presentProviderDetail(provider)
    }
}

// MARK: - Liquid Glass detail shell (iOS 26+)

@available(iOS 26.0, macOS 26.0, *)
private struct ServiceProviderGlassMatchedDetailOverlay: View {
    let provider: ServiceProvider
    let namespace: Namespace.ID
    let sessionManager: AppSessionManager
    let hasCurrentBooking: Bool
    let capturesTouches: Bool
    let onDismiss: () -> Void
    let onShowLogin: () -> Void
    var onBookingRequestCompleted: (() -> Void)? = nil
    var onOverlayDidDisappear: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard capturesTouches else { return }
                    onDismiss()
                }
                .transition(.opacity)

            ServiceProviderLiquidGlassDetailPanel(
                provider: provider,
                namespace: namespace,
                applyGlassEffectMorphID: false,
                applyGlassToEntirePanel: false,
                usesInnerNavigationStack: true,
                showsToolbarCloseButton: true,
                sessionManager: sessionManager,
                hasCurrentBooking: hasCurrentBooking,
                onDismiss: onDismiss,
                onShowLogin: onShowLogin,
                onBookingRequestCompleted: onBookingRequestCompleted
            )
            .padding(.horizontal, .space4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(
                .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(capturesTouches)
        .zIndex(100)
        .onDisappear {
            onOverlayDidDisappear?()
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct ServiceProviderLiquidGlassDetailPanel: View {
    let provider: ServiceProvider
    let namespace: Namespace.ID
    /// `glassEffectID` pairs with list cards inside the same `GlassEffectContainer` for Liquid Glass morph.
    var applyGlassEffectMorphID: Bool = true
    /// When `false` (detail popup), glass is scoped to the scroll area only so the footer + primary **Book** control stays opaque (no frosted layer on top of the button).
    var applyGlassToEntirePanel: Bool = true
    /// When `true`, wraps the sheet in its own `NavigationStack` (legacy overlay). When `false`, the parent supplies navigation (pushed destination).
    var usesInnerNavigationStack: Bool = true
    var showsToolbarCloseButton: Bool = false
    let sessionManager: AppSessionManager
    let hasCurrentBooking: Bool
    let onDismiss: () -> Void
    let onShowLogin: () -> Void
    var onBookingRequestCompleted: (() -> Void)? = nil

    private var panelCornerRadius: CGFloat { 12 }
    
    @ViewBuilder
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
        if applyGlassToEntirePanel {
            if applyGlassEffectMorphID {
                panelContent
                    .glassEffect(.regular, in: .rect(cornerRadius: panelCornerRadius, style: .continuous))
                    .glassEffectID(provider.id, in: namespace)
                    .clipShape(shape)
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 2)
            } else {
                panelContent
                    .glassEffect(.regular, in: .rect(cornerRadius: panelCornerRadius, style: .continuous))
                    .clipShape(shape)
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 2)
            }
        } else {
            panelContent
                .clipShape(shape)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 2)
        }
    }
    
    private var panelContent: some View {
        Group {
            if usesInnerNavigationStack {
                NavigationStack {
                    embeddedSheet
                }
            } else {
                embeddedSheet
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private var embeddedSheet: some View {
        ServiceProviderDetailSheet(
            provider: provider,
            sessionManager: sessionManager,
            hasCurrentBooking: hasCurrentBooking,
            onDismiss: onDismiss,
            onShowLogin: onShowLogin,
            useVibrantLiquidGlassStyling: true,
            useScrollScopedLiquidGlass: !applyGlassToEntirePanel,
            isPopupPresentation: !applyGlassToEntirePanel,
            embedsInParentNavigationStack: true,
            dismissesOnContentTap: false,
            showsToolbarCloseButton: showsToolbarCloseButton,
            onBookingRequestCompleted: onBookingRequestCompleted
        )
    }
}

// MARK: - Pushed Liquid Glass provider detail (iOS 26+)

@available(iOS 26.0, macOS 26.0, *)
private struct ServiceProviderLiquidGlassNavigationDetailPage: View {
    let provider: ServiceProvider
    let sessionManager: AppSessionManager
    let hasCurrentBooking: Bool
    let onShowLogin: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNamespace
    
    var body: some View {
        ZStack {
            #if os(iOS)
            InteraLavaLampBackground()
            #else
            ServiceProviderBrowseMeshBackdrop()
                .ignoresSafeArea()
            #endif
            GlassEffectContainer(spacing: 36) {
                ServiceProviderLiquidGlassDetailPanel(
                    provider: provider,
                    namespace: glassNamespace,
                    applyGlassEffectMorphID: false,
                    usesInnerNavigationStack: false,
                    sessionManager: sessionManager,
                    hasCurrentBooking: hasCurrentBooking,
                    onDismiss: { dismiss() },
                    onShowLogin: {
                        onShowLogin()
                    },
                    onBookingRequestCompleted: {
                        dismiss()
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Navigation route (provider detail push)

private struct ProviderDetailNavigationRoute: Hashable {
    let providerId: String
}

// MARK: - Profile Menu Sheet

/// Sheet opened from the avatar: full **Profile** experience with Account actions integrated in-scroll (not a stacked `Form`).
struct ProfileMenuSheet: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            UserProfileView(
                sessionManager: sessionManager,
                coordinator: coordinator,
                showsIntegratedAccountMenu: true,
                onAccountMenuSignOut: { dismiss() }
            )
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    doneButton
                }
                #else
                ToolbarItem(placement: .automatic) {
                    doneButton
                }
                #endif
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }

    private var doneButton: some View {
        Button("Done") {
            dismiss()
        }
    }
}

// MARK: - Service Provider Detail Presentation (tap outside to dismiss)

/// Spring used for overlay present/dismiss; aligned with system fluid motion.
private enum ServiceProviderDetailOverlayAnimation {
    static let spring = LiquidGlassMotion.fluidSpring
}

private struct ServiceProviderDetailPresentationOverlay: View {
    let provider: ServiceProvider
    let sessionManager: AppSessionManager
    let hasCurrentBooking: Bool
    let capturesTouches: Bool
    let onDismiss: () -> Void
    let onShowLogin: () -> Void
    var onBookingRequestCompleted: (() -> Void)? = nil
    var onOverlayDidDisappear: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            let sheetHeight = geometry.size.height * 0.92
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard capturesTouches else { return }
                        onDismiss()
                    }
                    .transition(.opacity)
                
                ServiceProviderDetailSheet(
                    provider: provider,
                    sessionManager: sessionManager,
                    hasCurrentBooking: hasCurrentBooking,
                    onDismiss: onDismiss,
                    onShowLogin: onShowLogin,
                    isPopupPresentation: true,
                    dismissesOnContentTap: false,
                    onBookingRequestCompleted: onBookingRequestCompleted
                )
                .frame(width: geometry.size.width, height: sheetHeight)
                .liquidGlassSheetChrome(cornerRadius: 16)
                .shadow(color: .black.opacity(0.18), radius: 24, y: -4)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    )
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(capturesTouches)
        .ignoresSafeArea()
        .zIndex(100)
        .onDisappear {
            onOverlayDidDisappear?()
        }
    }
}

// MARK: - Service Provider detail Reserve button (cream / deep charcoal, spring press + olive glow)

/// Label on the foreground-filled Book CTA (white on black in light mode, charcoal on cream in dark mode).
private var serviceProviderBookButtonLabelColor: Color { Color.interaShellBackground }

/// Same as `TimelineSectionHeader` “Today”: 28pt **bold** (system).
private let serviceProviderReserveTitleFont = InteraFont.system(size: 28, weight: .bold, design: .default)

/// Brief delay after finger lifts so the press spring can start before presenting booking (keep small for snappy navigation).
private let serviceProviderBookButtonSpringSettleSeconds: TimeInterval = 0.16

/// Footer Book CTA: explicit `DragGesture` press tracking so scale + booking fire even when `ButtonStyle.isPressed` is swallowed by overlay/sheet/glass.
private struct ProviderDetailBookFooterInteractive: View {
    let isBookActionPending: Bool
    let isBookNavigateScheduled: Bool
    let accessibilityReduceMotion: Bool
    let glowOpacity: Double
    let glowRadius: CGFloat
    let onBook: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if isBookActionPending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(serviceProviderBookButtonLabelColor)
                }
                Text("Book")
                    .font(serviceProviderReserveTitleFont)
                    .foregroundStyle(serviceProviderBookButtonLabelColor)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 54)
        .opacity(isBookActionPending ? 0.55 : 1)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.lavaShellCream)
        }
        .modifier(BookButtonPressAppearance(isPressed: isPressed, isEnabled: !isBookActionPending))
        .shadow(color: Color.oliveGreen.opacity(accessibilityReduceMotion ? 0.28 : glowOpacity), radius: glowRadius, y: 2)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        // High priority so scroll / sheet chrome does not swallow the press before we update `isPressed`.
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isBookActionPending else { return }
                    if !isPressed {
                        isPressed = true
                        #if os(iOS)
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.prepare()
                        impact.impactOccurred()
                        #endif
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    guard !isBookActionPending, !isBookNavigateScheduled else { return }
                    onBook()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Book")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) {
            guard !isBookActionPending, !isBookNavigateScheduled else { return }
            onBook()
        }
    }
}

// MARK: - Service Provider Detail Sheet Wrapper

struct ServiceProviderDetailSheet: View {
    let provider: ServiceProvider
    let sessionManager: AppSessionManager
    let hasCurrentBooking: Bool
    let onDismiss: () -> Void
    let onShowLogin: () -> Void
    /// iOS 26+ Liquid Glass detail: semantic foreground styles + glass button styles.
    var useVibrantLiquidGlassStyling: Bool = false
    /// When the parent panel omits full-sheet `glassEffect`, apply frost only to the scroll region (footer stays clear of stacked glass).
    var useScrollScopedLiquidGlass: Bool = false
    /// `true` for the floating sheet / overlay detail — footer is a single full-width **Book** bar (cream).
    var isPopupPresentation: Bool = false
    /// When `true`, omits an inner `NavigationStack` so this view can be pushed by a parent stack (or wrapped once by `ServiceProviderLiquidGlassDetailPanel`).
    var embedsInParentNavigationStack: Bool = false
    /// Full-screen overlay dismissed taps on scroll/footer; disable for a normal pushed detail page.
    var dismissesOnContentTap: Bool = true
    /// Hide trailing close when the system back button is used (pushed destination).
    var showsToolbarCloseButton: Bool = true
    /// After a successful booking request: close booking UI + run this (e.g. dismiss provider detail and open Bookings).
    var onBookingRequestCompleted: (() -> Void)? = nil

    @State private var showingBookingFlow = false
    @State private var showBookingLimitAlert = false
    @State private var showLiveDataStripeTestAlert = false
    @State private var showReviewsList = false
    @State private var isBookActionPending = false
    /// `true` after a valid Book tap while waiting for the press spring to settle before presenting `LiveBookingView`.
    @State private var isBookNavigateScheduled = false
    /// Drives subtle olive “glow” pulse on the reserve button while idle.
    @State private var reserveButtonGlowPhase: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// Popup/overlay detail: tapping scroll content must not dismiss (competes with the close control).
    private var effectiveDismissesOnContentTap: Bool {
        dismissesOnContentTap && !isPopupPresentation
    }

    private enum BarberReviewsFetchState: Equatable {
        case idle
        case loading
        case loaded([ProviderReview])
        case failed
    }

    @State private var barberReviewsState: BarberReviewsFetchState = .idle

    private var liveDataSafetyMode: Bool { AppConfiguration.campusCutsProductionLiveDataMode }

    /// After a successful fetch, API rows; otherwise embedded `customerReviews` while loading or if the request failed.
    private var displayReviews: [ProviderReview] {
        switch barberReviewsState {
        case .loaded(let rows):
            return rows
        case .failed, .idle, .loading:
            return provider.customerReviews ?? []
        }
    }

    private var isLoadingBarberReviews: Bool {
        if case .loading = barberReviewsState { return true }
        return false
    }

    /// Stars and booking-derived stats use this gate (lifetime completed count from list/detail API).
    private var providerHasCompletedBookings: Bool {
        (provider.completedBookings ?? 0) > 0
    }

    /// Pinned **Book** CTA: `ultraThinMaterial` bar + cream pill; olive glow pulses while idle (respects Reduce Motion).
    private var reserveStickyFooter: some View {
        let glowOpacity = 0.2 + Double(reserveButtonGlowPhase) * 0.18
        let glowRadius: CGFloat = accessibilityReduceMotion ? 7 : 5 + reserveButtonGlowPhase * 6

        return VStack(spacing: 0) {
            ProviderDetailBookFooterInteractive(
                isBookActionPending: isBookActionPending,
                isBookNavigateScheduled: isBookNavigateScheduled,
                accessibilityReduceMotion: accessibilityReduceMotion,
                glowOpacity: glowOpacity,
                glowRadius: glowRadius,
                onBook: { handleBookNow() }
            )
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .zIndex(100)
        .onAppear {
            guard !accessibilityReduceMotion else { return }
            reserveButtonGlowPhase = 0
            withAnimation(.easeInOut(duration: 1.65).repeatForever(autoreverses: true)) {
                reserveButtonGlowPhase = 1
            }
        }
    }

    private var detailHeadlineColor: Color {
        useVibrantLiquidGlassStyling ? .primary : .white
    }
    private var detailBodyColor: Color {
        useVibrantLiquidGlassStyling ? Color.secondary : Color.white.opacity(0.85)
    }
    private var detailSubtleColor: Color {
        useVibrantLiquidGlassStyling ? Color.secondary : Color.white.opacity(0.7)
    }
    private var detailCaptionColor: Color {
        useVibrantLiquidGlassStyling ? Color.secondary : Color.white.opacity(0.65)
    }
    private var detailEmphasisColor: Color {
        useVibrantLiquidGlassStyling ? Color.primary : Color.white.opacity(0.9)
    }
    
    var body: some View {
        Group {
            if embedsInParentNavigationStack {
                detailChrome
            } else {
                NavigationStack {
                    detailChrome
                }
            }
        }
        .onChange(of: showingBookingFlow) { _, isOpen in
            if isOpen {
                isBookActionPending = false
            } else {
                PendingPostLoginBooking.clearIfGuestClosedBooking(
                    providerId: provider.id,
                    isAuthenticated: sessionManager.isAuthenticated
                )
            }
        }
        .onChange(of: provider.id) { _, _ in
            barberReviewsState = .idle
        }
        .task(id: provider.id) {
            await fetchBarberReviewsForDetail()
        }
    }

    private func fetchBarberReviewsForDetail() async {
        barberReviewsState = .loading
        do {
            let rows = try await BarberReviewsAPI.fetchReviews(
                barberId: provider.id,
                bearerToken: sessionManager.currentSession?.token
            )
            barberReviewsState = .loaded(rows)
        } catch {
            if InteraRefreshCancellation.isBenignCancellation(error) {
                barberReviewsState = .idle
            } else {
                barberReviewsState = .failed
            }
        }
    }

    @ViewBuilder
    private var detailChrome: some View {
        ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                    // Header
                    VStack(spacing: 20) {
                        // Profile Image
                        ServiceProviderProfileThumbnail(
                            imageUrl: provider.profileImageUrl,
                            businessName: provider.businessName,
                            size: 120,
                            cornerRadius: 16
                        )
                        
                        // Name & availability only — rating lives in its own section below (not stacked on the hero).
                        VStack(spacing: 12) {
                            Text(provider.businessName)
                                .font(InteraFont.headlineLarge)
                                .foregroundStyle(detailHeadlineColor)

                            if let distanceLabel = provider.formattedDistanceFromUser {
                                HStack(spacing: 6) {
                                    Image(systemName: "location.circle.fill")
                                        .font(InteraFont.body.weight(.semibold))
                                        .accessibilityHidden(true)
                                    Text(distanceLabel)
                                        .font(InteraFont.subheadline.weight(.semibold))
                                }
                                .foregroundStyle(detailSubtleColor)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("About \(distanceLabel) from your location")
                            }
                            
                            if provider.isAvailableNow == true {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.success)
                                        .frame(width: 8, height: 8)
                                    Text("Available Now")
                                        .font(InteraFont.labelSmall)
                                }
                                .foregroundStyle(Color.success)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.success.opacity(0.1))
                                .cornerRadius(20)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Services stacked above About on the front of the detail card.
                    ProviderDetailAboutServicesSection(
                        provider: provider,
                        detailHeadlineColor: detailHeadlineColor,
                        detailEmphasisColor: detailEmphasisColor,
                        useVibrantLiquidGlassStyling: useVibrantLiquidGlassStyling
                    )

                    // Average stars only after at least one completed booking; hidden when preview rows exist below.
                    if displayReviews.isEmpty, providerHasCompletedBookings, let rating = provider.rating {
                        ProviderDetailRatingSummaryRow(
                            averageRating: rating,
                            detailHeadlineColor: detailHeadlineColor,
                            useVibrantLiquidGlassStyling: useVibrantLiquidGlassStyling
                        )
                    }
                    
                    // Instagram (opens in Instagram or Safari)
                    if let instagramURL = provider.instagramProfileURL {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Social")
                                .font(InteraFont.headlineSmall)
                                .foregroundStyle(detailHeadlineColor)
                            
                            Link(destination: instagramURL) {
                                HStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(InteraFont.body)
                                        .foregroundStyle(detailEmphasisColor)
                                        .accessibilityHidden(true)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Instagram")
                                            .font(InteraFont.caption)
                                            .foregroundStyle(detailCaptionColor)
                                        Text(provider.instagramDisplayHandle)
                                            .font(InteraFont.bodyMedium)
                                            .foregroundStyle(detailHeadlineColor)
                                    }
                                    
                                    Spacer(minLength: 8)
                                    
                                    Image(systemName: "arrow.up.right.circle.fill")
                                        .font(InteraFont.title3)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(detailBodyColor)
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(useVibrantLiquidGlassStyling ? Color.primary.opacity(0.06) : Color.white.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .modifier(InstagramLinkGlassButtonStyle(useVibrantLiquidGlassStyling: useVibrantLiquidGlassStyling))
                            .accessibilityLabel("Instagram")
                            .accessibilityValue(provider.instagramDisplayHandle)
                        }
                    }
                    
                    // Stats (bookings only — omit zero; review counts are not shown on this sheet)
                    if let bookingCount = provider.completedBookings, bookingCount > 0 {
                        HStack(spacing: 0) {
                            StatItem(
                                icon: "scissors",
                                value: "\(bookingCount)",
                                label: "Bookings",
                                useVibrantLiquidGlassStyling: useVibrantLiquidGlassStyling
                            )
                        }

                        Divider()
                    }
                    
                    // Availability (if available)
                    if let availability = provider.availability, !availability.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Availability")
                                .font(InteraFont.headlineSmall)
                                .foregroundStyle(detailHeadlineColor)
                            
                            // First row: Days 0-3 (Mon-Thu)
                            VStack(spacing: 12) {
                                // Day labels
                                HStack(spacing: 8) {
                                    ForEach(availability.prefix(4)) { day in
                                        Text(day.dayOfWeek)
                                            .font(InteraFont.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(detailEmphasisColor)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                
                                // Time slots for first 4 days
                                let maxSlotsFirst = availability.prefix(4).map { $0.timeSlots.count }.max() ?? 0
                                ForEach(0..<maxSlotsFirst, id: \.self) { slotIndex in
                                    HStack(spacing: 8) {
                                        ForEach(availability.prefix(4)) { day in
                                            if slotIndex < day.timeSlots.count {
                                                Text(day.timeSlots[slotIndex])
                                                    .font(InteraFont.caption2)
                                                    .foregroundStyle(detailBodyColor)
                                                    .frame(maxWidth: .infinity)
                                                    .multilineTextAlignment(.center)
                                            } else {
                                                Text("")
                                                    .frame(maxWidth: .infinity)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Second row: Days 4-6 (Fri-Sun)
                            if availability.count > 4 {
                                VStack(spacing: 12) {
                                    // Day labels
                                    HStack(spacing: 8) {
                                        ForEach(availability.suffix(from: 4)) { day in
                                            Text(day.dayOfWeek)
                                                .font(InteraFont.caption)
                                                .fontWeight(.medium)
                                                .foregroundStyle(detailEmphasisColor)
                                                .frame(maxWidth: .infinity)
                                        }
                                        // Add empty spacers to align with 4 columns
                                        if availability.count < 7 {
                                            ForEach(0..<(7 - availability.count), id: \.self) { _ in
                                                Text("")
                                                    .frame(maxWidth: .infinity)
                                            }
                                        }
                                    }
                                    
                                    // Time slots for last 3 days
                                    let maxSlotsSecond = availability.suffix(from: 4).map { $0.timeSlots.count }.max() ?? 0
                                    ForEach(0..<maxSlotsSecond, id: \.self) { slotIndex in
                                        HStack(spacing: 8) {
                                            ForEach(availability.suffix(from: 4)) { day in
                                                if slotIndex < day.timeSlots.count {
                                                    Text(day.timeSlots[slotIndex])
                                                        .font(InteraFont.caption2)
                                                        .foregroundStyle(detailBodyColor)
                                                        .frame(maxWidth: .infinity)
                                                        .multilineTextAlignment(.center)
                                                } else {
                                                    Text("")
                                                        .frame(maxWidth: .infinity)
                                                }
                                            }
                                            // Add empty cells to align with 4 columns
                                            if availability.count < 7 {
                                                ForEach(0..<(7 - availability.count), id: \.self) { _ in
                                                    Text("")
                                                        .frame(maxWidth: .infinity)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    /*
                    // Locations (if available)
                    if let locations = provider.locations, !locations.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Locations")
                                .font(InteraFont.headlineSmall)
                                .foregroundStyle(detailHeadlineColor)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(locations, id: \.self) { location in
                                    Text(location)
                                        .font(InteraFont.bodyMedium)
                                        .foregroundStyle(useVibrantLiquidGlassStyling ? Color.secondary : Color.white.opacity(0.9))
                                }
                            }
                        }
                    }
                    */
                    
                    // Reviews: preview rows from API (or list embed); tap to open full list
                    ProviderDetailReviewsPreviewSection(
                        reviews: displayReviews,
                        isLoadingReviews: isLoadingBarberReviews,
                        detailHeadlineColor: detailHeadlineColor,
                        detailEmphasisColor: detailEmphasisColor,
                        detailBodyColor: detailBodyColor,
                        detailSubtleColor: detailSubtleColor,
                        detailCaptionColor: detailCaptionColor,
                        useVibrantLiquidGlassStyling: useVibrantLiquidGlassStyling,
                        onShowAll: {
                            guard !displayReviews.isEmpty else { return }
                            showReviewsList = true
                        }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .contentShape(Rectangle())
                .modifier(TapDismissIfEnabled(enabled: effectiveDismissesOnContentTap, onDismiss: onDismiss))
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            #if os(iOS)
            .scrollClipDisabled(false)
            #endif
            .modifier(ProviderDetailScrollLiquidGlassAvailabilityModifier(
                active: useScrollScopedLiquidGlass && useVibrantLiquidGlassStyling
            ))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                reserveStickyFooter
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .navigationTitle(provider.businessName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if showsToolbarCloseButton {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    closeButton
                }
                #else
                ToolbarItem(placement: .automatic) {
                    closeButton
                }
                #endif
            }
        }
            .sheet(isPresented: $showReviewsList) {
                ProviderReviewsFullListView(reviews: displayReviews)
            }
            .sheet(isPresented: $showingBookingFlow) {
                LiveBookingView(
                    provider: provider,
                    sessionManager: sessionManager,
                    onShowLogin: onShowLogin,
                    onDismiss: { showingBookingFlow = false },
                    onBookingRequestSuccessfullySent: {
                        showingBookingFlow = false
                        onBookingRequestCompleted?()
                    }
                )
                .tint(Color.oliveGreen)
                .interaBookingFlowSheetPresentation()
            }
            .alert("Active Booking Exists", isPresented: $showBookingLimitAlert) {
                Button("View My Booking", role: .cancel) {
                    onDismiss()
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("You already have an active booking. Please complete or cancel it before making a new one.")
            }
            .alert("Stripe test mode", isPresented: $showLiveDataStripeTestAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Live Data Mode is on. Booking and live checkout are disabled so you do not email real service providers or charge real cards. Use a build with this flag off and Stripe test keys to exercise the full flow.")
            }
    }

    private var closeButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(InteraFont.system(size: 16, weight: .semibold))
                .foregroundStyle(useVibrantLiquidGlassStyling ? Color.primary : Color.white.opacity(0.92))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .modifier(ServiceProviderDetailCloseButtonStyle())
        .accessibilityLabel("Close")
    }
    
    private func handleBookNow() {
        guard !isBookActionPending, !isBookNavigateScheduled else { return }

        if liveDataSafetyMode {
            showLiveDataStripeTestAlert = true
            return
        }

        if sessionManager.isAuthenticated, hasCurrentBooking {
            showBookingLimitAlert = true
            return
        }

        // Finger lifted — spring scale-back runs; wait before presenting booking.
        let delay: TimeInterval = accessibilityReduceMotion ? 0.04 : serviceProviderBookButtonSpringSettleSeconds
        isBookNavigateScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            isBookNavigateScheduled = false
            isBookActionPending = true
            showingBookingFlow = true
        }
    }
}

// MARK: - Provider detail: Services + About (stacked on front-facing card)

/// Services listed first, About bio below — both visible when present.
private struct ProviderDetailAboutServicesSection: View {
    let provider: ServiceProvider
    let detailHeadlineColor: Color
    let detailEmphasisColor: Color
    var useVibrantLiquidGlassStyling: Bool = false

    private var bioText: String? {
        provider.bio?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private var orderedServices: [ServiceProvider.Service] {
        provider.displayOrderedServices
    }

    private var hasAbout: Bool { bioText != nil }
    private var hasServices: Bool { !orderedServices.isEmpty }

    var body: some View {
        Group {
            if hasAbout || hasServices {
                VStack(alignment: .leading, spacing: 20) {
                    if hasServices {
                        servicesSection
                    }
                    if hasAbout, let bioText {
                        aboutSection(bioText)
                    }
                }
            }
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Services")
                .font(InteraFont.headlineSmall)
                .foregroundStyle(detailHeadlineColor)

            VStack(spacing: 12) {
                ForEach(orderedServices) { service in
                    serviceRow(service)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func isPrimaryHaircutService(_ service: ServiceProvider.Service) -> Bool {
        service.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Haircut") == .orderedSame
    }

    private func serviceRow(_ service: ServiceProvider.Service) -> some View {
        let isPrimaryHaircut = isPrimaryHaircutService(service)
        let nameFont = isPrimaryHaircut ? InteraFont.headlineSmall : InteraFont.bodySmall
        let priceFont = isPrimaryHaircut
            ? InteraFont.headlineSmall.weight(.medium)
            : InteraFont.bodySmall.weight(.medium)

        return HStack(spacing: 4) {
            Text(service.name)
                .font(nameFont)
                .foregroundStyle(detailEmphasisColor)

            Text("•")
                .font(isPrimaryHaircut ? InteraFont.headlineSmall : InteraFont.bodySmall)
                .foregroundStyle(useVibrantLiquidGlassStyling ? Color.secondary.opacity(0.6) : Color.white.opacity(0.5))
                .padding(.leading, 4)

            Text(service.formattedPrice)
                .font(priceFont)
                .foregroundStyle(detailEmphasisColor)
        }
        .frame(maxWidth: .infinity)
    }

    private func aboutSection(_ bioText: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(InteraFont.headlineSmall)
                .foregroundStyle(detailHeadlineColor)

            Text(bioText)
                .font(InteraFont.bodyMedium)
                .foregroundStyle(useVibrantLiquidGlassStyling ? Color.secondary : Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Provider detail: rating + reviews UI

private struct ProviderDetailRatingSummaryRow: View {
    let averageRating: Double
    let detailHeadlineColor: Color
    var useVibrantLiquidGlassStyling: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(InteraFont.title3.weight(.semibold))
                .foregroundStyle(Color.yellow)
            Text(String(format: "%.1f", averageRating))
                .font(InteraFont.title3.weight(.semibold))
                .foregroundStyle(detailHeadlineColor)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(useVibrantLiquidGlassStyling ? Color.primary.opacity(0.06) : Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: "%.1f average stars", averageRating))
    }
}

private struct ProviderDetailReviewsPreviewSection: View {
    let reviews: [ProviderReview]
    var isLoadingReviews: Bool = false
    let detailHeadlineColor: Color
    let detailEmphasisColor: Color
    let detailBodyColor: Color
    let detailSubtleColor: Color
    let detailCaptionColor: Color
    var useVibrantLiquidGlassStyling: Bool = false
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoadingReviews && reviews.isEmpty {
                Text("Reviews")
                    .font(InteraFont.headlineSmall)
                    .foregroundStyle(detailHeadlineColor)
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading reviews…")
                        .font(InteraFont.bodyMedium)
                        .foregroundStyle(detailSubtleColor)
                }
            } else if reviews.isEmpty {
                Text("Reviews")
                    .font(InteraFont.headlineSmall)
                    .foregroundStyle(detailHeadlineColor)
                Text("No reviews yet")
                    .font(InteraFont.bodyMedium)
                    .foregroundStyle(detailSubtleColor)
            } else {
                Button(action: onShowAll) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Reviews")
                                .font(InteraFont.headlineSmall)
                                .foregroundStyle(detailHeadlineColor)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(InteraFont.subheadline.weight(.semibold))
                                .foregroundStyle(detailSubtleColor)
                        }

                        ForEach(Array(reviews.prefix(2).enumerated()), id: \.element.id) { index, review in
                            ProviderReviewRowContent(
                                review: review,
                                detailEmphasisColor: detailEmphasisColor,
                                detailBodyColor: detailBodyColor,
                                detailCaptionColor: detailCaptionColor,
                                multilineComment: false
                            )
                            if index == 0 && reviews.prefix(2).count > 1 {
                                Divider()
                                    .background(detailSubtleColor.opacity(0.35))
                            }
                        }

                        if reviews.count > 2 {
                            Text("See all reviews")
                                .font(InteraFont.subheadline.weight(.semibold))
                                .foregroundStyle(detailEmphasisColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(useVibrantLiquidGlassStyling ? Color.primary.opacity(0.06) : Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reviews, show full list")
            }
        }
    }
}

private struct ProviderReviewRowContent: View {
    let review: ProviderReview
    let detailEmphasisColor: Color
    let detailBodyColor: Color
    let detailCaptionColor: Color
    var multilineComment: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(review.authorDisplayName)
                    .font(InteraFont.bodyMedium.weight(.semibold))
                    .foregroundStyle(detailEmphasisColor)
                Spacer(minLength: 8)
                if let stars = review.rating {
                    ProviderReviewStarsRow(rating: stars)
                }
            }
            HStack(spacing: 6) {
                Text(review.relativeDate)
                    .font(InteraFont.caption)
                    .foregroundStyle(detailCaptionColor)
            }
            if let text = review.comment, !text.isEmpty {
                Text(text)
                    .font(InteraFont.bodySmall)
                    .foregroundStyle(detailBodyColor)
                    .lineLimit(multilineComment ? nil : 3)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

private struct ProviderReviewStarsRow: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< 5, id: \.self) { i in
                Image(systemName: i < rating ? "star.fill" : "star")
                    .font(InteraFont.caption.weight(.semibold))
                    .foregroundStyle(i < rating ? Color.yellow : Color.gray.opacity(0.45))
            }
        }
        .accessibilityLabel("\(rating) out of 5 stars")
    }
}

private struct ProviderReviewsFullListView: View {
    let reviews: [ProviderReview]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(reviews) { review in
                ProviderReviewRowContent(
                    review: review,
                    detailEmphasisColor: .primary,
                    detailBodyColor: .secondary,
                    detailCaptionColor: .secondary,
                    multilineComment: true
                )
                .listRowSeparator(.visible)
            }
            .navigationTitle("Reviews")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                #endif
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

/// Applies sheet frost only to the scroll column when the panel omits full-bleed `glassEffect` (detail popup).
@available(iOS 26.0, macOS 26.0, *)
private struct ProviderDetailScrollLiquidGlassModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.glassEffect(.regular, in: Rectangle())
        } else {
            content
        }
    }
}

private struct ProviderDetailScrollLiquidGlassAvailabilityModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.modifier(ProviderDetailScrollLiquidGlassModifier(active: active))
        } else {
            content
        }
    }
}

private struct TapDismissIfEnabled: ViewModifier {
    let enabled: Bool
    let onDismiss: () -> Void
    
    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture { onDismiss() }
        } else {
            content
        }
    }
}

// MARK: - Stat Item Helper View

private struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    var useVibrantLiquidGlassStyling: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(InteraFont.bodyMedium)
                .fontWeight(.semibold)
                .foregroundStyle(useVibrantLiquidGlassStyling ? Color.primary : Color.white)
            
            Text(label)
                .font(InteraFont.labelSmall)
                .foregroundStyle(useVibrantLiquidGlassStyling ? Color.secondary : Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct InstagramLinkGlassButtonStyle: ViewModifier {
    let useVibrantLiquidGlassStyling: Bool
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), useVibrantLiquidGlassStyling {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.plain)
        }
    }
}

/// Plain style so the dismiss control stays glyph-only (no system glass / grey disc behind the X).
private struct ServiceProviderDetailCloseButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Browse Tab") {
    let manager = AppSessionManager()
    manager.mockLogin(as: .student)
    
    return ConsumerHomeScreen(
        sessionManager: manager,
        coordinator: MainCoordinator(sessionManager: manager)
    )
    .environmentObject(ChatViewModel())
}

#Preview("Bookings Tab") {
    let manager = AppSessionManager()
    manager.mockLogin(as: .student)
    
    return ConsumerHomeScreen(
        sessionManager: manager,
        coordinator: MainCoordinator(sessionManager: manager)
    )
    .environmentObject(ChatViewModel())
}
// MARK: - Unified Provider Home Screen

struct UnifiedProviderHomeScreen: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    @ObservedObject var appleOAuthPostSignIn: AppleOAuthPostSignInCoordinator

    @EnvironmentObject private var chatViewModel: ChatViewModel
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif
    
    @Namespace private var providerGlassNamespace

    @State private var selectedCategory: ServiceProvider.ServiceCategory? = nil
    @State private var providerVM = ProviderViewModel()
    @State private var showProfileMenu = false
    @State private var showGuestAuthEntrySheet = false
    @State private var unifiedGuestAuthResumeAction: GuestAuthResumeAction = .none
    @State private var unifiedOAuthSignInShowsCreateAccountLink = true
    @State private var showOAuthSignInSheet = false
    @State private var showManualSignInSheet = false
    @State private var showIntegratedSignUpSheet = false
    @State private var showLoginPrompt = false
    @State private var selectedProvider: ServiceProvider?
    /// When `false`, the browse list receives taps even if the detail overlay is still animating out.
    @State private var isProviderDetailCapturingTouches = false
    /// Stays `true` from open until overlay `onDisappear` (or fallback) so browse scroll/geometry stay locked through dismiss animation.
    @State private var isProviderDetailOverlayBlockingBrowse = false
    /// Fresh identity per open so overlay subtrees fully dismantle (avoids ghost hit blockers).
    @State private var providerDetailPresentationID = UUID()
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var providerListShuffleSeed: UInt64 = UInt64.random(in: 1 ... UInt64.max)
    @State private var stickyUnifiedBrowseHeaderHeight: CGFloat = 0
    /// 0 = Home (feed), 1 = Messages, 2 = Bookings, 3 = Profile — single paged `TabView` for swipe between all.
    @State private var hubPageIndex = 0
    /// Bookings tab `NavigationStack` depth (`ConsumerBookingsHubView.detailNavigationPath.count`) — hides hub chrome while detail/chat is pushed so the thread isn’t covered.
    @State private var bookingsTabNavigationDepth = 0
    /// Outer-shell `navigationDestination(item:)` thread (same as Messages inbox) — not in `NavigationPath`.
    @State private var homeShellBookingThreadObscuresHubChrome = false
    /// Home outer stack pushed `.messagingThread` on `NavigationPath` (do not infer from `count` alone — path can desync after Bookings tab).
    @State private var homeOuterPushedMessagingThread = false
    @State private var consumerBookingRows: [ConsumerBookingSimpleRow] = []
    @State private var showMaxDistanceSheet = false
    /// Hides `ConsumerStickyHubBar` while the utility-pill search field is focused so it is not stacked above the keyboard.
    @State private var isBrowseUtilitySearchFocused = false
    /// Hides `ConsumerStickyHubBar` while Profile first/last name fields are focused (same reason as browse search).
    @State private var isProfileHubNameFieldFocused = false
    /// When `true`, miles slider, expanded search, or Tags strip — hub `TabView` horizontal swipe is disabled.
    @State private var isUtilityPillChromeExpanded = false
    /// Provider utility-pill search (expanded field / keyboard) — hub bar is unmounted, not merely hidden.
    private var browseProviderSearchSuppressesHubBar: Bool {
        isUtilityPillChromeExpanded || isBrowseUtilitySearchFocused
    }
    /// UIKit paging bridge + cream bubble driver (shared by scroll observer and hub bar).
    #if os(iOS)
    @State private var hubPagingCoordinator = HubPagingCoordinator()
    #endif
    /// After non-animated hub selection (e.g. bubble drag release), forces the paging `UIScrollView` to match — fixes adjacent single-step moves.
    @State private var hubTabSyncPagingScrollToSelection = false
    /// Cancels stale post-animation scroll reconcile tasks when the user taps another hub icon quickly.
    @State private var hubNavigateReconcileGeneration = 0
    /// Monotonic time of the last hub icon navigation — rapid hops snap instead of animating (no queue cooldown).
    @State private var lastHubNavigateUptime: UInt64 = 0
    /// While `true`, the cream bubble tracks `hubPageIndex` instead of a stale paging scroll offset (programmatic snap).
    @State private var hubBubbleAnchoredToPageIndex = false
    /// Briefly ignores paging-scroll KVO so a programmatic snap does not fight the bubble binding.
    @State private var hubTabSuppressScrollPublish = false
    /// When `true`, a scroll sync runs the full multi-frame reconcile (background / payment); light sync for icon snaps.
    @State private var hubTabSyncPagingScrollAggressive = true
    /// While dragging the hub bubble, suppresses scroll-offset publishing so the main `TabView` does not flicker.
    @State private var isHubBubbleDragging = false
    /// 0 = expanded floating hub bar; 1 = minimized while scrolling page content downward.
    @State private var hubBarCollapseProgress: CGFloat = 0
    @State private var hubBarLastScrollOffsetY: CGFloat = 0
    /// While a Messages thread is open on the hub Messages tab, horizontal hub tab swiping is disabled (conversation edge swipe is isolated).
    @State private var messagesThreadPresentedForHubPaging = false
    /// 0 = hub bar fully visible; 1 = slid away for utility chrome (mile slider, search, tags).
    @State private var hubBarUtilitySuppressionProgress: CGFloat = 0
    /// Bumped when a message push opens a thread so the Messages `NavigationStack` is recreated — avoids stacking two `MessagingConversationView`s after resume from background.
    @State private var messagesHubNavigationStackEpoch = 0
    /// Sticky browse chrome overlays the scroll view pre–iOS 26, hiding the system refresh spinner — mirror the glass path with an explicit wheel.
    @State private var showsUnifiedBrowsePullRefreshWheel = false

    private var serviceProviders: [ServiceProvider] { providerVM.providersForDisplay }
    private var isLoading: Bool { providerVM.isLoading }
    
    private var displayedProviders: [ServiceProvider] {
        let byCategory: [ServiceProvider] = {
            if #available(iOS 26.0, macOS 26.0, *) {
                return providerVM.providersFilteredByServiceType(serviceProviders)
            }
            guard let category = selectedCategory else {
                return serviceProviders
            }
            return serviceProviders.filter { $0.category == category }
        }()
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = byCategory.filter { $0.matchesConsumerSearch(query: searchText) }
        guard !q.isEmpty else {
            return matched.shuffledWithStableSeed(providerListShuffleSeed)
        }
        return matched.sorted {
            let p0 = $0.consumerSearchSortPriority(query: q)
            let p1 = $1.consumerSearchSortPriority(query: q)
            if p0 != p1 { return p0 < p1 }
            return $0.businessName.localizedCaseInsensitiveCompare($1.businessName) == .orderedAscending
        }
    }

    private var hasActiveConsumerBooking: Bool {
        consumerBookingRows.contains { row in
            let u = row.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard u == "PENDING" || u == "ACCEPTED" else { return false }
            return row.scheduleSegment() != .past
        }
    }

    private var homeTodayBookingHighlight: HomeTodayBookingHighlight? {
        guard sessionManager.isAuthenticated else { return nil }
        return HomeTodayBookingHighlight.pickTodayHighlight(from: consumerBookingRows)
    }

    private var homePendingPaymentHighlight: HomePendingPaymentHighlight? {
        guard sessionManager.isAuthenticated else { return nil }
        return HomePendingPaymentHighlight.pickAwaitingPayment(from: consumerBookingRows)
    }

    private var upcomingBookingIndicatorCount: Int {
        guard sessionManager.isAuthenticated else { return 0 }
        return consumerBookingRows.upcomingBookingNotificationBadgeCount
    }

    /// When a thread is open on Messages (`hubPageIndex == 1`), the hub’s page `UIScrollView` must not steal horizontal drags from interactive back.
    private var hubTabPagingInteractionEnabled: Bool {
        if !sessionManager.isAuthenticated { return false }
        if isUtilityPillChromeExpanded { return false }
        if hubPageIndex != 1 { return true }
        return !messagesThreadPresentedForHubPaging
    }

    /// Signed-out users stay on Home; hub bar is replaced by the guest sign-in overlay.
    private var guestHubNavigationLocked: Bool {
        !sessionManager.isAuthenticated
    }

    /// Structural gate for bottom hub chrome (inset height). When `false`, no bottom inset (e.g. browse search, pushed routes).
    /// Bookings detail / thread keeps the hub visible so **Pay later** (dismisses `fullScreenCover` while still pushed)
    /// does not leave the user without Home / Messages / Bookings / Profile until they change hub pages.
    ///
    /// Only **Home** (page 0) uses this screen’s outer `navigationPath`. Messages / Bookings / Profile use inner
    /// `NavigationStack`s; gating on `navigationPath` for every tab could collapse the hub for a frame during inner
    /// pop transitions and make the selector disappear while returning to the inbox.
    private var hubShellAllowsBottomChromeInset: Bool {
        if hubPageIndex == 0, homeOuterPushedMessagingThread { return false }
        if homeShellBookingThreadObscuresHubChrome { return false }
        return true
    }

    @MainActor
    private func clearHomeShellHubSuppressionFlags() {
        homeOuterPushedMessagingThread = false
        homeShellBookingThreadObscuresHubChrome = false
    }

    /// Drops a stale `.messagingThread` segment if the user already popped the conversation (path `count` can stay `>= 2`).
    @MainActor
    private func stripHomeOuterMessagingThreadFromNavigationPathIfNeeded() {
        guard navigationPath.count > 1 else { return }
        while navigationPath.count > 1 {
            navigationPath.removeLast()
        }
        homeOuterPushedMessagingThread = false
    }

    /// Hub rail or guest sign-in overlay visible and tappable.
    private var unifiedShowsHubBottomChrome: Bool {
        guard hubShellAllowsBottomChromeInset else { return false }
        if guestHubNavigationLocked {
            return hubPageIndex == 0
        }
        return !(hubPageIndex == 3 && isProfileHubNameFieldFocused)
    }

    private var unifiedShowsConsumerStickyHubBar: Bool {
        sessionManager.isAuthenticated && unifiedShowsHubBottomChrome
    }

    private var unifiedShowsGuestSignInBar: Bool {
        guestHubNavigationLocked && unifiedShowsHubBottomChrome
    }

    /// Visible refresh wheel above sticky / glass chrome (system `UIRefreshControl` is easy to miss under overlays).
    private var unifiedBrowsePullRefreshWheelOverlay: some View {
        Group {
            if showsUnifiedBrowsePullRefreshWheel {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.oliveGreen)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var unifiedHubHomePage: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                unifiedBrowseLiquidGlassRoot
            } else {
                unifiedBrowseStack()
                    #if os(iOS)
                    .background(Color.clear)
                    #else
                    .background(Color.neutral50.ignoresSafeArea())
                    #endif
                    .overlay(alignment: .top) { unifiedBrowsePullRefreshWheelOverlay }
            }
        }
    }

    /// Swipeable Home ↔ Messages ↔ Bookings ↔ Profile (page index matches `ConsumerStickyHubBar`).
    private var unifiedHubPagedContent: some View {
        TabView(selection: $hubPageIndex) {
            unifiedHubHomePage
                .tag(0)
                .interaHubPageInteractionLock(pageIndex: 0, coordinator: hubPagingCoordinator)

            NavigationStack {
                ConversationListView(
                    sessionManager: sessionManager,
                    coordinator: coordinator,
                    onBrowseServiceProviders: {
                        navigateHubPage(0, animated: true)
                    },
                    onThreadPresentationChanged: { visible, _ in messagesThreadPresentedForHubPaging = visible },
                    onResetMessagesNavigationStackBeforePush: {
                        messagesHubNavigationStackEpoch += 1
                    },
                    hasActiveConsumerBooking: hasActiveConsumerBooking,
                    onShowLogin: { showOAuthSignInSheet = true }
                )
                #if os(iOS)
                .interaNavigationShellBackgroundClear()
                #endif
            }
            .id(messagesHubNavigationStackEpoch)
            .tag(1)
            .interaHubPageInteractionLock(pageIndex: 1, coordinator: hubPagingCoordinator)

            ConsumerBookingsHubView(
                sessionManager: sessionManager,
                coordinator: coordinator,
                onShowLogin: { showOAuthSignInSheet = true },
                onNavigationDepthChange: { bookingsTabNavigationDepth = $0 }
            )
            #if os(iOS)
            .interaNavigationShellBackgroundClear()
            #endif
            .tag(2)
            .interaHubPageInteractionLock(pageIndex: 2, coordinator: hubPagingCoordinator)

            NavigationStack {
                UserProfileView(
                    sessionManager: sessionManager,
                    coordinator: coordinator,
                    showsIntegratedAccountMenu: true,
                    hubBottomBarSuppressionWhileFocused: $isProfileHubNameFieldFocused
                )
                #if os(iOS)
                .interaNavigationShellBackgroundClear()
                #endif
            }
            .tag(3)
            .interaHubPageInteractionLock(pageIndex: 3, coordinator: hubPagingCoordinator)
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(nil, value: hubPageIndex)
        .background {
            HubPageViewControllerSurfaceTint()
        }
        #endif
        .background(Color.clear)
    }

    #if os(iOS)
    /// Off the paged `TabView` subtree so scroll KVO does not call `updateUIView` on the pager every frame.
    private var hubPagingScrollObserver: some View {
        HubPagingScrollOffsetReader(
            coordinator: hubPagingCoordinator,
            hubPageIndex: hubPageIndex,
            isPagingInteractionEnabled: hubTabPagingInteractionEnabled,
            syncPagingScrollToSelection: $hubTabSyncPagingScrollToSelection,
            syncPagingScrollAggressive: $hubTabSyncPagingScrollAggressive,
            suppressScrollPublishingFromObserver: isHubBubbleDragging || hubTabSuppressScrollPublish
        )
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    #endif

    #if os(iOS)
    private func resyncHubTabPagingScroll() {
        hubTabSyncPagingScrollAggressive = true
        hubTabSyncPagingScrollToSelection = true
    }

    /// Re-align hub `TabView` paging after outer Home `NavigationPath` pops (conversation → detail → browse).
    private func syncHubPagingAfterHomeShellNavigationChange(pathDepth: Int) {
        guard hubPageIndex == 0 else { return }
        if pathDepth < 2 {
            clearHomeShellHubSuppressionFlags()
        }
        if pathDepth <= 1 {
            stripHomeOuterMessagingThreadFromNavigationPathIfNeeded()
        }
        resyncHubTabPagingScroll()
    }
    #else
    private func syncHubPagingAfterHomeShellNavigationChange(pathDepth: Int) {
        if pathDepth < 2 {
            clearHomeShellHubSuppressionFlags()
        }
        if pathDepth <= 1 {
            stripHomeOuterMessagingThreadFromNavigationPathIfNeeded()
        }
    }
    #endif

    private func navigateHubPage(_ page: Int, animated: Bool = true) {
        guard sessionManager.isAuthenticated || page == 0 else { return }
        if page != 3 {
            isProfileHubNameFieldFocused = false
        }
        #if os(iOS)
        let now = DispatchTime.now().uptimeNanoseconds
        let rapidReselect = lastHubNavigateUptime != 0 && now &- lastHubNavigateUptime < 350_000_000
        lastHubNavigateUptime = now
        hubNavigateReconcileGeneration += 1
        let generation = hubNavigateReconcileGeneration
        #else
        let rapidReselect = false
        let generation = 0
        #endif

        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                hubPageIndex = page
            }
            #if os(iOS)
            let target = page
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard hubNavigateReconcileGeneration == generation else { return }
                guard hubPageIndex == target else { return }
                hubTabSyncPagingScrollAggressive = true
                hubTabSyncPagingScrollToSelection = true
            }
            #endif
        } else {
            // Icon taps / bubble release: page content snaps immediately; only the cream bubble may spring.
            #if os(iOS)
            hubTabSuppressScrollPublish = true
            hubPagingCoordinator.suppressScrollPublish = true
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            if rapidReselect || reduceMotion {
                hubBubbleAnchoredToPageIndex = true
                hubPagingCoordinator.bubbleAnchoredToPageIndex = true
                hubPagingCoordinator.animateBubbleToPage(page, animated: false)
            } else {
                hubBubbleAnchoredToPageIndex = false
                hubPagingCoordinator.bubbleAnchoredToPageIndex = false
                hubPagingCoordinator.animateBubbleToPage(page, animated: true)
            }
            #endif
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                hubPageIndex = page
            }
            #if os(iOS)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: (rapidReselect || reduceMotion) ? 80_000_000 : 280_000_000)
                guard hubNavigateReconcileGeneration == generation else { return }
                guard hubPageIndex == page else { return }
                hubTabSuppressScrollPublish = false
                hubPagingCoordinator.suppressScrollPublish = false
                hubBubbleAnchoredToPageIndex = false
                hubPagingCoordinator.bubbleAnchoredToPageIndex = false
                let expected = CGFloat(page) * max(1, hubPagingCoordinator.pageWidth)
                if abs(hubPagingCoordinator.scrollOffsetX - expected) > 2 {
                    hubTabSyncPagingScrollAggressive = false
                    hubTabSyncPagingScrollToSelection = true
                }
            }
            #endif
        }
    }
    
    @MainActor
    private func handleHubPageVerticalScrollOffset(pageIndex: Int, offsetY: CGFloat, resyncLastSample: Bool = false) {
        guard pageIndex == hubPageIndex else { return }
        #if os(iOS)
        if !resyncLastSample, hubPagingCoordinator.isUserScrolling {
            let w = max(1, hubPagingCoordinator.pageWidth)
            let pageProgress = hubPagingCoordinator.scrollOffsetX / w
            guard abs(pageProgress - CGFloat(hubPageIndex)) < 0.02 else { return }
        }
        #endif
        guard unifiedShowsHubBottomChrome else {
            hubBarCollapseProgress = 0
            hubBarLastScrollOffsetY = 0
            return
        }
        if resyncLastSample {
            InteraHubBarCollapseController.resyncLastOffsetY(
                lastOffsetY: &hubBarLastScrollOffsetY,
                offsetY: offsetY
            )
            return
        }
        InteraHubBarCollapseController.update(
            progress: &hubBarCollapseProgress,
            lastOffsetY: &hubBarLastScrollOffsetY,
            offsetY: offsetY
        )
    }

    #if os(iOS)
    /// Hub bar remount is async — defer bubble layout until `HubBubbleUIKitHost` attaches.
    private func resyncHubBubbleAfterMount() {
        DispatchQueue.main.async {
            guard !browseProviderSearchSuppressesHubBar else { return }
            hubPagingCoordinator.syncBubbleAfterHubBarMount(page: hubPageIndex)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard !browseProviderSearchSuppressesHubBar else { return }
            hubPagingCoordinator.syncBubbleAfterHubBarMount(page: hubPageIndex)
        }
    }
    #endif

    private var hubBarOverlayBottomInset: CGFloat {
        guard hubShellAllowsBottomChromeInset else { return 0 }
        let expandedInset: CGFloat = {
            if guestHubNavigationLocked {
                return GuestHubSignInMetrics.overlayContentBottomInset(collapseProgress: hubBarCollapseProgress)
            }
            return ConsumerStickyHubMetrics.overlayContentBottomInset(collapseProgress: hubBarCollapseProgress)
        }()
        return expandedInset * (1.0 - hubBarUtilitySuppressionProgress)
    }

    /// Matches the home utility-pill mile-slider morph spring so chrome moves in sync.
    private static var hubBarUtilitySuppressionSpring: Animation {
        .spring(response: 0.4, dampingFraction: 0.7)
    }

    @ViewBuilder
    private var hubStickyBarOverlay: some View {
        if hubShellAllowsBottomChromeInset {
            Group {
                if unifiedShowsGuestSignInBar {
                    GuestHubSignInBar(
                        sessionManager: sessionManager,
                        appleOAuthFollowUp: appleOAuthPostSignIn,
                        onRequestManualSignIn: { showManualSignInSheet = true },
                        onRequestEmailSignUp: { showIntegratedSignUpSheet = true },
                        collapseProgress: hubBarCollapseProgress
                    )
                } else if unifiedShowsConsumerStickyHubBar {
                    #if os(iOS)
                    ConsumerStickyHubBar(
                        hubPageIndex: $hubPageIndex,
                        pagingCoordinator: hubPagingCoordinator,
                        unreadMessageCount: chatViewModel.unreadMessageCount,
                        upcomingBookingCount: upcomingBookingIndicatorCount,
                        onNavigateToPage: { page, animated in navigateHubPage(page, animated: animated) },
                        bubbleAnchoredToPageIndex: hubBubbleAnchoredToPageIndex,
                        collapseProgress: hubBarCollapseProgress,
                        isHubBubbleDragging: $isHubBubbleDragging
                    )
                    #else
                    ConsumerStickyHubBar(
                        hubPageIndex: $hubPageIndex,
                        unreadMessageCount: chatViewModel.unreadMessageCount,
                        upcomingBookingCount: upcomingBookingIndicatorCount,
                        onNavigateToPage: { page, animated in navigateHubPage(page, animated: animated) },
                        bubbleAnchoredToPageIndex: hubBubbleAnchoredToPageIndex,
                        collapseProgress: hubBarCollapseProgress,
                        isHubBubbleDragging: $isHubBubbleDragging
                    )
                    #endif
                }
            }
            .scaleEffect(1.0 - 0.12 * hubBarUtilitySuppressionProgress, anchor: .bottom)
            .offset(y: 24 * hubBarUtilitySuppressionProgress)
            .opacity((unifiedShowsHubBottomChrome ? 1 : 0) * (1.0 - 0.96 * hubBarUtilitySuppressionProgress))
            .allowsHitTesting(unifiedShowsHubBottomChrome && hubBarUtilitySuppressionProgress < 0.04)
            .accessibilityHidden(!unifiedShowsHubBottomChrome || hubBarUtilitySuppressionProgress > 0.96)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .animation(Self.hubBarUtilitySuppressionSpring, value: hubBarUtilitySuppressionProgress)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: unifiedShowsHubBottomChrome)
        }
    }

    /// Hub shell (background, hub bar, toolbar) — split for type checker.
    @ViewBuilder
    private var unifiedProviderHubShell: some View {
        ZStack {
            InteraHubTabShellBackground()
                .ignoresSafeArea()
            InteraHubPagerRenderGate(
                hubPageIndex: hubPageIndex,
                messagesHubNavigationStackEpoch: messagesHubNavigationStackEpoch
            ) {
                unifiedHubPagedContent
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
            .background(Color.clear)
            .overlay(alignment: .bottom) {
                hubStickyBarOverlay
                    .zIndex(50)
            }
            #if os(iOS)
            .overlay {
                InteraHubScrollBridgeRenderGate(
                    hubPageIndex: hubPageIndex,
                    isPagingInteractionEnabled: hubTabPagingInteractionEnabled,
                    syncPagingScrollToSelection: hubTabSyncPagingScrollToSelection,
                    suppressScrollPublishingFromObserver: isHubBubbleDragging || hubTabSuppressScrollPublish
                ) {
                    hubPagingScrollObserver
                }
            }
            #endif
            .environment(\.interaHubBarOverlayBottomInset, hubBarOverlayBottomInset)
            .environment(\.interaHubBarScrollOffsetHandler, InteraHubBarScrollOffsetHandler(
                onOffsetChange: { pageIndex, offsetY in
                    handleHubPageVerticalScrollOffset(pageIndex: pageIndex, offsetY: offsetY)
                },
                onResyncLastSample: { pageIndex, offsetY in
                    handleHubPageVerticalScrollOffset(pageIndex: pageIndex, offsetY: offsetY, resyncLastSample: true)
                }
            ))
            #if os(iOS)
            .environment(\.interaHubPagingCoordinator, hubPagingCoordinator)
            #endif
            .animation(Self.hubBarUtilitySuppressionSpring, value: hubBarUtilitySuppressionProgress)
            #if os(iOS)
            .onAppear {
                hubBarUtilitySuppressionProgress = browseProviderSearchSuppressesHubBar ? 1 : 0
                hubPagingCoordinator.setHubBarBubblePresentationEnabled(!browseProviderSearchSuppressesHubBar)
            }
            .onChange(of: browseProviderSearchSuppressesHubBar) { _, suppressed in
                withAnimation(Self.hubBarUtilitySuppressionSpring) {
                    hubBarUtilitySuppressionProgress = suppressed ? 1 : 0
                }
                hubPagingCoordinator.setHubBarBubblePresentationEnabled(!suppressed)
                if suppressed {
                    hubBubbleAnchoredToPageIndex = true
                    hubPagingCoordinator.bubbleAnchoredToPageIndex = true
                } else {
                    hubBubbleAnchoredToPageIndex = false
                    hubPagingCoordinator.bubbleAnchoredToPageIndex = false
                    resyncHubBubbleAfterMount()
                }
            }
            .onChange(of: chatViewModel.activePaymentRequest) { _, new in
                // After payment `fullScreenCover` tears down, the paged hub `UIScrollView` can keep a stale offset;
                // syncing here restores the sticky hub rail without forcing the user to swipe tabs.
                if new == nil {
                    hubTabSyncPagingScrollAggressive = true
                    hubTabSyncPagingScrollToSelection = true
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Backgrounding mid–hub-bubble drag leaves `isHubBubbleDragging` true and suppresses scroll
                // KVO — the cream bubble stops tracking the pager until foreground resync.
                guard phase == .active else { return }
                isHubBubbleDragging = false
                hubTabSyncPagingScrollAggressive = true
                hubTabSyncPagingScrollToSelection = true
            }
            #endif
            .onChange(of: hubPageIndex) { old, new in
                if guestHubNavigationLocked, new != 0 {
                    var reset = Transaction()
                    reset.disablesAnimations = true
                    withTransaction(reset) {
                        hubPageIndex = 0
                    }
                    #if os(iOS)
                    hubTabSyncPagingScrollAggressive = true
                    hubTabSyncPagingScrollToSelection = true
                    #endif
                    return
                }
                var collapseReset = Transaction()
                collapseReset.disablesAnimations = true
                withTransaction(collapseReset) {
                    hubBarCollapseProgress = 0
                    hubBarLastScrollOffsetY = 0
                }
                // If scroll observation was suppressed (hub bubble drag), clear so the rail isn’t stuck
                // desynced from the pager after deep links / notification navigation.
                isHubBubbleDragging = false
                if new != 3 {
                    isProfileHubNameFieldFocused = false
                }
                // Bookings tab: same reload as pull-to-refresh (timeline `ScrollView` owns `.refreshable`).
                if new == 2, old != 2, sessionManager.isAuthenticated {
                    NotificationCenter.default.post(name: .consumerBookingsListShouldRefresh, object: nil)
                }
                // Messages tab: dismiss any pushed booking detail / thread on the Bookings stack so it doesn’t linger off-screen.
                if new == 1, old != 1 {
                    NotificationCenter.default.post(name: .consumerBookingsHubShouldPopToRoot, object: nil)
                }
                if new != 0 {
                    // Outer-stack pushes (reminder detail, provider nav, chat) must not linger while
                    // another tab owns its own NavigationStack (e.g. Bookings timeline links).
                    // Snap teardown without implicit navigation “pop” animation so it doesn’t compete
                    // with the hub `TabView` page spring on the same frame.
                    var tearDown = Transaction()
                    tearDown.disablesAnimations = true
                    withTransaction(tearDown) {
                        chatViewModel.clearPathBackedMessagingItemHandoffs()
                        clearHomeShellHubSuppressionFlags()
                        navigationPath = NavigationPath()
                    }
                }
                if new == 0 {
                    clearHomeShellHubSuppressionFlags()
                    stripHomeOuterMessagingThreadFromNavigationPathIfNeeded()
                    #if os(iOS)
                    NotificationCenter.default.post(name: .homeHubBrowseShouldResyncUtilityPill, object: nil)
                    // Adjacent swipe (e.g. Messages → Home) already drives the page `UIScrollView`;
                    // aggressive reconcile snaps offset without animation and fights the gesture.
                    if abs(old - new) != 1 {
                        resyncHubTabPagingScroll()
                    }
                    #endif
                    if old != 0, sessionManager.isAuthenticated {
                        Task {
                            await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager)
                            await loadUnifiedConsumerBookingsForHome()
                        }
                    }
                }
            }
            .onChange(of: bookingsTabNavigationDepth) { _, depth in
                // After popping booking detail, re-sync the paging `UIScrollView` with `hubPageIndex` so the
                // sticky hub rail doesn’t stay invisible / misaligned (common after reminder → detail → back).
                guard depth == 0, hubPageIndex == 2 else { return }
                #if os(iOS)
                resyncHubTabPagingScroll()
                #endif
            }
            .onChange(of: selectedCategory) { _, _ in
                providerListShuffleSeed = UInt64.random(in: 1 ... UInt64.max)
            }
            .onChange(of: providerVM.selectedServiceType) { _, _ in
                providerListShuffleSeed = UInt64.random(in: 1 ... UInt64.max)
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                if sessionManager.isAuthenticated, unifiedShowsLegacyNavigationProfileButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        profileButton
                    }
                }
                if #unavailable(iOS 26.0) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showMaxDistanceSheet = true
                        } label: {
                            Image(systemName: "location.circle")
                                .font(InteraFont.body.weight(.semibold))
                                .foregroundStyleInteraShellIcon()
                        }
                        .accessibilityLabel("Maximum search distance")
                    }
                }
                #else
                if sessionManager.isAuthenticated, unifiedShowsLegacyNavigationProfileButton {
                    ToolbarItem(placement: .automatic) {
                        profileButton
                    }
                }
                #endif
            }
    }

    private func unifiedConsumerHomeRow(bookingId: String) -> ConsumerBookingSimpleRow? {
        let key = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        return consumerBookingRows.first { $0.id == key }
    }

    private var unifiedHomeShellMessagingHandoffWhenPathEmpty: Binding<ChatViewModel.BookingMessagingThreadHandoff?> {
        Binding(
            get: {
                navigationPath.isEmpty ? chatViewModel.homeStackMessagingHandoff : nil
            },
            set: { chatViewModel.homeStackMessagingHandoff = $0 }
        )
    }

    @ViewBuilder
    private func unifiedHomeMessagingThreadDestination(
        _ handoff: ChatViewModel.BookingMessagingThreadHandoff,
        onDismissClearHandoff: @escaping () -> Void,
        obscuresHubChromeWhileVisible: Bool = false
    ) -> some View {
        MessagingConversationView(
            conversationId: handoff.conversationId,
            sessionManager: sessionManager,
            coordinator: coordinator,
            initialBooking: handoff.bookingSnapshot,
            counterpartyAvatarURLString: handoff.counterpartyAvatarURLString,
            counterpartyFallbackDisplayName: handoff.counterpartyFallbackName,
            initialDraftText: handoff.initialDraft.isEmpty ? nil : handoff.initialDraft,
            onRequestPopFromParent: nil,
            onNavigationVisibilityChanged: { visible, _ in
                if obscuresHubChromeWhileVisible {
                    homeShellBookingThreadObscuresHubChrome = visible
                } else if visible {
                    homeOuterPushedMessagingThread = true
                } else {
                    clearHomeShellHubSuppressionFlags()
                    stripHomeOuterMessagingThreadFromNavigationPathIfNeeded()
                }
                if !visible { onDismissClearHandoff() }
            },
            onInitialThreadHydrationComplete: nil,
            onResyncSharedHubInboxSilently: {
                await chatViewModel.reloadInboxSilently(sessionManager: sessionManager)
            },
            counterpartyUserId: handoff.counterpartyMessagingUserId
        )
        #if os(iOS)
        .interaNavigationShellBackgroundClear()
        #endif
        .onDisappear {
            clearHomeShellHubSuppressionFlags()
            stripHomeOuterMessagingThreadFromNavigationPathIfNeeded()
        }
    }

    @ViewBuilder
    private func unifiedBookingStackDestination(_ route: ConsumerHomeBookingStackRoute) -> some View {
        switch route {
        case .detail(let bookingId, let presentationID):
            if let row = unifiedConsumerHomeRow(bookingId: bookingId) {
                ConsumerBookingDetailView(
                    row: row,
                    sessionManager: sessionManager,
                    coordinator: coordinator,
                    bookingDetailPresentationID: presentationID,
                    hasActiveConsumerBooking: hasActiveConsumerBooking,
                    onShowLogin: { showOAuthSignInSheet = true }
                )
                .id(presentationID)
                #if os(iOS)
                .interaNavigationShellBackgroundClear()
                #endif
            } else {
                ContentUnavailableView(
                    "Booking unavailable",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Pull to refresh on Home or reopen the booking from Bookings.")
                )
            }
        case .messagingThread:
            EmptyView()
        }
    }

    @ViewBuilder
    private var unifiedProviderHomeNavigationStackInner: some View {
        unifiedProviderHubShell
            #if os(iOS)
            .interaNavigationShellBackgroundClear()
            .sheet(isPresented: $showMaxDistanceSheet) {
                ConsumerBrowseDistanceSheet {
                    Task { await loadProviders() }
                }
            }
            #endif
            .sheet(isPresented: $showProfileMenu) {
                ProfileMenuSheet(
                    sessionManager: sessionManager,
                    coordinator: coordinator
                )
            }
            .sheet(isPresented: $showGuestAuthEntrySheet, onDismiss: {
                switch unifiedGuestAuthResumeAction {
                case .signInOptions:
                    unifiedOAuthSignInShowsCreateAccountLink = false
                    showOAuthSignInSheet = true
                case .signUp:
                    showIntegratedSignUpSheet = true
                case .none:
                    break
                }
                unifiedGuestAuthResumeAction = .none
            }) {
                if #available(iOS 17.0, macOS 14.0, *) {
                    GuestAuthEntrySheet(
                        isPresented: $showGuestAuthEntrySheet,
                        onSignIn: { unifiedGuestAuthResumeAction = .signInOptions },
                        onSignUp: { unifiedGuestAuthResumeAction = .signUp }
                    )
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    #endif
                }
            }
            .sheet(isPresented: $showOAuthSignInSheet, onDismiss: {
                unifiedOAuthSignInShowsCreateAccountLink = true
                let c = appleOAuthPostSignIn
                guard !c.appleBackendExchangeInProgress else { return }
                c.reset()
            }) {
                if #available(iOS 17.0, macOS 14.0, *) {
                    OAuthProviderSignInSheet(
                        sessionManager: sessionManager,
                        appleOAuthFollowUp: appleOAuthPostSignIn,
                        onFinished: { showOAuthSignInSheet = false },
                        onRequestEmailSignUp: {
                            showOAuthSignInSheet = false
                            showIntegratedSignUpSheet = true
                        },
                        showsCreateAccountLink: unifiedOAuthSignInShowsCreateAccountLink
                    )
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    #endif
                }
            }
            .sheet(isPresented: $showManualSignInSheet) {
                if #available(iOS 17.0, macOS 14.0, *) {
                    ManualEmailSignInSheet(
                        sessionManager: sessionManager,
                        onFinished: { showManualSignInSheet = false },
                        onRequestEmailSignUp: {
                            showManualSignInSheet = false
                            showIntegratedSignUpSheet = true
                        }
                    )
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    #endif
                }
            }
            .sheet(isPresented: $showIntegratedSignUpSheet) {
                if #available(iOS 17.0, macOS 14.0, *) {
                    IntegratedSignUpSheet(sessionManager: sessionManager, onFinished: {
                        showIntegratedSignUpSheet = false
                    })
                    #if os(iOS)
                    .presentationDetents([.large])
                    #endif
                }
            }
            .navigationDestination(isPresented: $showLoginPrompt) {
                LoginView(sessionManager: sessionManager)
            }
            .navigationDestination(for: ProviderDetailNavigationRoute.self) { route in
                if let provider = serviceProviders.first(where: { $0.id == route.providerId }) {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        ServiceProviderLiquidGlassNavigationDetailPage(
                            provider: provider,
                            sessionManager: sessionManager,
                            hasCurrentBooking: hasActiveConsumerBooking,
                            onShowLogin: {
                                showOAuthSignInSheet = true
                            }
                        )
                    }
                } else {
                    ContentUnavailableView(
                        "Provider unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Pull to refresh or go back and open this provider again.")
                    )
                }
            }
            .navigationDestination(for: ConsumerHomeBookingStackRoute.self) { route in
                unifiedBookingStackDestination(route)
            }
            .navigationDestination(item: unifiedHomeShellMessagingHandoffWhenPathEmpty) { handoff in
                unifiedHomeMessagingThreadDestination(handoff, onDismissClearHandoff: {
                    chatViewModel.promoteOrInsertConversationFromHandoff(handoff)
                    chatViewModel.homeStackMessagingHandoff = nil
                }, obscuresHubChromeWhileVisible: true)
            }
            .overlay {
                if let provider = selectedProvider {
                    let overlayPresentationID = providerDetailPresentationID
                    if #available(iOS 26.0, macOS 26.0, *) {
                        ServiceProviderGlassMatchedDetailOverlay(
                            provider: provider,
                            namespace: providerGlassNamespace,
                            sessionManager: sessionManager,
                            hasCurrentBooking: hasActiveConsumerBooking,
                            capturesTouches: isProviderDetailCapturingTouches,
                            onDismiss: { dismissProviderDetail() },
                            onShowLogin: {
                                showOAuthSignInSheet = true
                            },
                            onBookingRequestCompleted: { dismissProviderDetail() },
                            onOverlayDidDisappear: {
                                finalizeProviderDetailOverlayTeardown(expectedPresentationID: overlayPresentationID)
                            }
                        )
                        .id(overlayPresentationID)
                        .zIndex(100)
                    } else {
                        ServiceProviderDetailPresentationOverlay(
                            provider: provider,
                            sessionManager: sessionManager,
                            hasCurrentBooking: hasActiveConsumerBooking,
                            capturesTouches: isProviderDetailCapturingTouches,
                            onDismiss: { dismissProviderDetail() },
                            onShowLogin: {
                                showOAuthSignInSheet = true
                            },
                            onBookingRequestCompleted: { dismissProviderDetail() },
                            onOverlayDidDisappear: {
                                finalizeProviderDetailOverlayTeardown(expectedPresentationID: overlayPresentationID)
                            }
                        )
                        .id(overlayPresentationID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(100)
                    }
                }
            }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            unifiedProviderHomeNavigationStackInner
        }
        .onChange(of: navigationPath.count) { _, count in
            if count < 2 {
                clearHomeShellHubSuppressionFlags()
            }
            if count <= 1 {
                stripHomeOuterMessagingThreadFromNavigationPathIfNeeded()
            }
            if count == 0 {
                chatViewModel.clearPathBackedMessagingItemHandoffs()
            }
            syncHubPagingAfterHomeShellNavigationChange(pathDepth: count)
        }
        .task {
            await loadProviders()
            await loadUnifiedConsumerBookingsForHome()
            await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager)
        }
        .onChange(of: sessionManager.isAuthenticated) { _, authed in
            Task { await loadProviders() }
            Task { await loadUnifiedConsumerBookingsForHome() }
            Task { await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager) }
            if !authed {
                hubPageIndex = 0
                #if os(iOS)
                hubTabSyncPagingScrollAggressive = true
                hubTabSyncPagingScrollToSelection = true
                #endif
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .messagingUnreadCountShouldRefresh)) { _ in
            Task { await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .campusCutsStartProviderChat)) { output in
            guard let id = output.userInfo?["providerID"] as? String else { return }
            Task { @MainActor in
                openUnifiedChatForBarberProfileId(id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .interaOpenMessagingConversation)) { output in
            Task { @MainActor in
                await handleOpenMessagingConversationFromNotification(userInfo: output.userInfo)
            }
        }
        .onChange(of: hubPageIndex) { _, page in
            guard page == 1 else { return }
            guard let raw = chatViewModel.pendingPushConversationId?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return }
            Task { @MainActor in
                await Task.yield()
                await chatViewModel.presentHubThreadFromMessagePush(
                    conversationId: raw,
                    sessionManager: sessionManager
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .interaOpenBookingDetail)) { output in
            guard let raw = output.userInfo?["bookingId"] else { return }
            let bid: String? = {
                if let s = raw as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let n = raw as? NSNumber { return n.stringValue }
                if let i = raw as? Int { return String(i) }
                return nil
            }()
            guard let bid, !bid.isEmpty else { return }
            Task { @MainActor in
                chatViewModel.pendingOpenBookingDetailId = bid
                navigateHubPage(2, animated: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .interaNavigateToBookingsAfterBookingRequest)) { _ in
            Task { @MainActor in
                navigateHubPage(0, animated: true)
                await loadUnifiedConsumerBookingsForHome()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .consumerBookingsListShouldRefresh)) { _ in
            Task { await loadUnifiedConsumerBookingsForHome() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .interaNavigateToConsumerHomeAfterPayment)) { notification in
            let snapHub = (notification.userInfo?[InteraBookingsUserInfoKeys.snapHubNoAnimation] as? Bool) == true
            Task { @MainActor in
                chatViewModel.pendingOpenBookingDetailId = nil
                chatViewModel.homeStackMessagingHandoff = nil
                homeShellBookingThreadObscuresHubChrome = false
                navigationPath = NavigationPath()
                navigateHubPage(0, animated: !snapHub)
                await loadUnifiedConsumerBookingsForHome()
            }
        }
    }

    /// Home pull-to-refresh: provider list, bookings snapshot, and message unread badge — aligned with Messages (`reloadInbox` + badge) and Bookings (`load`).
    @MainActor
    private func refreshUnifiedHomeSurface() async {
        await loadProviders()
        await loadUnifiedConsumerBookingsForHome()
        await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager)
    }

    @MainActor
    private func refreshUnifiedHomeSurfaceForPullToRefresh() async {
        showsUnifiedBrowsePullRefreshWheel = true
        defer { showsUnifiedBrowsePullRefreshWheel = false }
        await InteraPullToRefresh.runMainActorAsyncIsolatedFromRefreshableCancellation {
            await refreshUnifiedHomeSurface()
        }
    }

    private func openUnifiedChatForBarberProfileId(_ raw: String) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        if let row = consumerBookingRows.first(where: {
            ($0.barberId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(id) == .orderedSame
        }) {
            Task {
                await chatViewModel.presentMessagingThreadForBooking(
                    row: row,
                    sessionManager: sessionManager,
                    presentationStack: .homeShellNavigation
                )
            }
        } else {
            navigateHubPage(1, animated: true)
        }
    }

    /// Message push tap → Messages tab + open thread with the provider who sent the notification.
    @MainActor
    private func handleOpenMessagingConversationFromNotification(userInfo: [AnyHashable: Any]?) async {
        guard sessionManager.isAuthenticated else { return }
        guard let cid = InteraPushNavigationPayload.conversationId(from: userInfo) else { return }

        chatViewModel.pendingPushConversationId = cid

        let needsStackReset = chatViewModel.hubMessagesThreadPresentation != nil
            || chatViewModel.hubForegroundConversationId != nil
        if needsStackReset {
            chatViewModel.clearHubMessagesThreadPresentation()
            messagesHubNavigationStackEpoch += 1
            await Task.yield()
            await Task.yield()
            await Task.yield()
        }

        navigateHubPage(1, animated: true)

        await Task.yield()
        await Task.yield()
        await Task.yield()

        await chatViewModel.presentHubThreadFromMessagePush(
            conversationId: cid,
            sessionManager: sessionManager
        )
    }

    @MainActor
    private func loadUnifiedConsumerBookingsForHome() async {
        guard sessionManager.isAuthenticated else {
            consumerBookingRows = []
            #if os(iOS)
            UpcomingBookingAppBadge.syncFromConsumerRows([])
            #endif
            return
        }
        do {
            consumerBookingRows = try await ConsumerBookingsSimpleAPI.fetchConsumerBookings(
                bearerToken: sessionManager.currentSession?.token,
                consumerUserId: sessionManager.currentSession?.userId
            )
            #if os(iOS)
            UpcomingBookingAppBadge.syncFromConsumerRows(consumerBookingRows)
            #endif
            chatViewModel.ensureRealtimeConnected(
                bearerToken: sessionManager.currentSession?.token,
                userId: sessionManager.currentSession?.userId
            )
            chatViewModel.syncPaymentTakeover(withBookings: consumerBookingRows)
        } catch {
            if ConsumerBookingsSimpleAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
            }
        }
    }

    private var unifiedShowsLegacyNavigationProfileButton: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return false
        }
        return true
    }

    #if os(iOS)
    private var unifiedBrowseOnMaxDistanceTap: (() -> Void)? {
        { showMaxDistanceSheet = true }
    }
    #else
    private var unifiedBrowseOnMaxDistanceTap: (() -> Void)? { nil }
    #endif

    private var unifiedToolbarProfileFallbackURL: URL? {
        ProfileImageURLResolver.url(from: sessionManager.currentSession?.profileImageURL)
    }
    
    @available(iOS 26.0, macOS 26.0, *)
    private var unifiedBrowseLiquidGlassRoot: some View {
        GlassHeaderProviderBrowse(
            searchText: $searchText,
            selectedServiceType: Binding(
                get: { providerVM.selectedServiceType },
                set: { providerVM.selectedServiceType = $0 }
            ),
            displayedProviders: displayedProviders,
            isLoading: isLoading,
            glassNamespace: providerGlassNamespace,
            fallbackProfileImageURL: unifiedToolbarProfileFallbackURL,
            unreadMessageCount: chatViewModel.unreadMessageCount,
            upcomingBookingCount: upcomingBookingIndicatorCount,
            onMessagesTap: {
                navigateHubPage(1)
            },
            onBookingsTap: {
                navigateHubPage(2)
            },
            onProfileTap: {
                navigateHubPage(3)
            },
            onProviderTap: { presentProviderDetail($0) },
            onRefresh: {
                await refreshUnifiedHomeSurface()
            },
            emptyContent: { emptyState },
            todayBookingActivity: homeTodayBookingHighlight,
            pendingPaymentBooking: homePendingPaymentHighlight,
            onMaxDistanceTap: unifiedBrowseOnMaxDistanceTap,
            hidesQuickNavigationIcons: true,
            utilitySearchFieldFocused: $isBrowseUtilitySearchFocused,
            utilityPillSuppressesHubPaging: $isUtilityPillChromeExpanded,
            onTodayBookingReminderTap: { (row: ConsumerBookingSimpleRow) in
                guard sessionManager.isAuthenticated else {
                    showOAuthSignInSheet = true
                    return
                }
                navigateHubPage(0, animated: false)
                navigationPath = NavigationPath()
                navigationPath.append(ConsumerHomeBookingStackRoute.bookingsTabDetailPush(for: row))
            },
            onPendingPaymentReminderTap: { (row: ConsumerBookingSimpleRow) in
                chatViewModel.presentPaymentTakeover(forBookingRow: row)
            },
            sessionManager: sessionManager,
            mainCoordinator: coordinator,
            hasActiveConsumerBooking: hasActiveConsumerBooking,
            isProviderDetailCapturingTouches: isProviderDetailCapturingTouches,
            isProviderDetailOverlayPresented: isProviderDetailOverlayBlockingBrowse,
            homeHubPageIndex: $hubPageIndex
        )
    }

    private func presentProviderDetail(_ provider: ServiceProvider) {
        providerDetailPresentationID = UUID()
        isProviderDetailCapturingTouches = true
        isProviderDetailOverlayBlockingBrowse = true
        withAnimation(LiquidGlassMotion.fluidSpring) {
            selectedProvider = provider
        }
    }

    private func dismissProviderDetail() {
        isProviderDetailCapturingTouches = false
        #if os(iOS)
        hubPagingCoordinator.releaseSuspendedVerticalScrollsIfNeeded()
        hubPagingCoordinator.refreshPageInteractionLocksAfterSelectionChange()
        #endif
        NotificationCenter.default.post(name: .homeHubBrowseShouldResyncUtilityPill, object: nil)
        withAnimation(LiquidGlassMotion.fluidSpring) {
            selectedProvider = nil
        }
        scheduleProviderDetailOverlayTeardownFallback()
    }

    private func finalizeProviderDetailOverlayTeardown(expectedPresentationID: UUID) {
        #if os(iOS)
        hubPagingCoordinator.releaseSuspendedVerticalScrollsIfNeeded()
        hubPagingCoordinator.refreshPageInteractionLocksAfterSelectionChange()
        #endif
        guard expectedPresentationID == providerDetailPresentationID else { return }
        guard selectedProvider == nil else { return }
        isProviderDetailOverlayBlockingBrowse = false
        isProviderDetailCapturingTouches = false
        NotificationCenter.default.post(name: .homeHubBrowseShouldResyncUtilityPill, object: nil)
    }

    private func scheduleProviderDetailOverlayTeardownFallback() {
        let closingPresentationID = providerDetailPresentationID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 620_000_000)
            guard closingPresentationID == providerDetailPresentationID else { return }
            guard selectedProvider == nil else { return }
            isProviderDetailOverlayBlockingBrowse = false
            isProviderDetailCapturingTouches = false
            #if os(iOS)
            hubPagingCoordinator.releaseSuspendedVerticalScrollsIfNeeded()
            hubPagingCoordinator.refreshPageInteractionLocksAfterSelectionChange()
            #endif
            NotificationCenter.default.post(name: .homeHubBrowseShouldResyncUtilityPill, object: nil)
        }
    }

    private func unifiedBrowseStack(
        useGlassMorphCards: Bool = false,
        useInteractiveLiquidGlassCards: Bool = false,
        stickyChromePlacement: BrowseStickyChromePlacement = .overlayOnScroll
    ) -> some View {
        let morphNS = useGlassMorphCards ? providerGlassNamespace : nil
        let interactiveOnly = useInteractiveLiquidGlassCards && !useGlassMorphCards
        
        let headerInset = stickyUnifiedBrowseHeaderHeight > 1
            ? stickyUnifiedBrowseHeaderHeight + .space4
            : 130
        
        let chromeOutsideGlass = stickyChromePlacement == .externalAboveGlassContainer
        
        return VStack(spacing: 0) {
            // Same as consumer browse: avoid swapping away the refreshable ScrollView while reloading
            // when cached `serviceProviders` is non-empty (pull-to-refresh).
            if isLoading && serviceProviders.isEmpty {
                if chromeOutsideGlass {
                    ScrollView {
                        ProviderGlassSkeletonList()
                            .padding(.horizontal, .space4)
                            .padding(.top, headerInset)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(iOS)
                    .scrollBounceBehavior(.always, axes: .vertical)
                    #endif
                    .refreshable {
                        await refreshUnifiedHomeSurfaceForPullToRefresh()
                    }
                } else {
                    CategoryFilterBar(
                        selectedCategory: $selectedCategory,
                        providers: serviceProviders
                    )
                    SearchBar(text: $searchText, placeholder: "Search providers")
                        .padding(.horizontal, .space4)
                        .padding(.top, .space3)
                        .padding(.bottom, .space2)
                    ScrollView {
                        ProviderGlassSkeletonList()
                            .padding(.horizontal, .space4)
                            .padding(.bottom, .space6)
                    }
                    #if os(iOS)
                    .scrollBounceBehavior(.always, axes: .vertical)
                    #endif
                    .refreshable {
                        await refreshUnifiedHomeSurfaceForPullToRefresh()
                    }
                }
            } else if displayedProviders.isEmpty {
                if chromeOutsideGlass {
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer()
                                .frame(height: headerInset)
                            emptyState
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(iOS)
                    .scrollBounceBehavior(.always, axes: .vertical)
                    #endif
                    .refreshable {
                        await refreshUnifiedHomeSurfaceForPullToRefresh()
                    }
                } else {
                    CategoryFilterBar(
                        selectedCategory: $selectedCategory,
                        providers: serviceProviders
                    )
                    SearchBar(text: $searchText, placeholder: "Search providers")
                        .padding(.horizontal, .space4)
                        .padding(.top, .space3)
                        .padding(.bottom, .space2)
                    ScrollView {
                        emptyState
                            .frame(maxWidth: .infinity)
                    }
                    #if os(iOS)
                    .scrollBounceBehavior(.always, axes: .vertical)
                    #endif
                    .refreshable {
                        await refreshUnifiedHomeSurfaceForPullToRefresh()
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: .space4) {
                        ForEach(displayedProviders) { provider in
                            ServiceProviderCard(
                                provider: provider,
                                onTap: {
                                    if #available(iOS 26.0, macOS 26.0, *) {
                                        navigationPath.append(ProviderDetailNavigationRoute(providerId: provider.id))
                                    } else {
                                        presentProviderDetail(provider)
                                    }
                                },
                                glassMorphNamespace: morphNS,
                                liquidGlassInteractiveWithoutMorph: interactiveOnly,
                                allowsInteraction: !isProviderDetailCapturingTouches
                            )
                        }
                    }
                    .padding(.horizontal, .space4)
                    .padding(.top, headerInset)
                    .padding(.bottom, .space6)
                    .interaHubBarScrollContentBottomInset()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                #if os(iOS)
                .scrollBounceBehavior(.always, axes: .vertical)
                #endif
                .scrollDisabled(isProviderDetailOverlayBlockingBrowse)
                .interaHubBarScrollOffsetReporting(pageIndex: 0)
                .refreshable {
                    await refreshUnifiedHomeSurfaceForPullToRefresh()
                }
                .modifier(BrowseListStickyChromeModifier(
                    placement: stickyChromePlacement,
                    searchText: $searchText,
                    selectedCategory: $selectedCategory,
                    providers: serviceProviders,
                    onHeaderHeightChange: { stickyUnifiedBrowseHeaderHeight = $0 }
                ))
                .overlay {
                    if isLoading && !serviceProviders.isEmpty {
                        ZStack {
                            Color.black.opacity(0.1)
                            ProgressView()
                                .scaleEffect(1.25)
                                .tint(.white)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }
    
    private var profileButton: some View {
        Button {
            showProfileMenu = true
        } label: {
            AvatarView(
                imageUrl: sessionManager.currentSession?.profileImageURL,
                name: sessionManager.currentSession?.displayName ?? "User",
                size: 32
            )
        }
    }
    
    @ViewBuilder
    private var emptyState: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let noProvidersInRadius = serviceProviders.isEmpty

        if trimmed.isEmpty, noProvidersInRadius {
            HomeNoBarbersInRadiusEmptyLabel()
        } else {
            VStack(spacing: .space4) {
                Spacer()
                Image(systemName: trimmed.isEmpty ? "person.2" : "magnifyingglass")
                    .font(InteraFont.system(size: 60))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                Text(trimmed.isEmpty ? "No providers available" : "No matching providers")
                    .font(InteraFont.headlineMedium)
                    .foregroundStyle(Color.lavaShellCream)
                Text(trimmed.isEmpty ? "Check back later" : "Try a different search or category.")
                    .campusCutsStyle(.bodyMedium)
                Spacer()
            }
            .padding()
        }
    }
    
    private func loadProviders() async {
        CampusCutsSessionSync.appSessionManager = sessionManager
        await providerVM.loadProviders(bearerToken: sessionManager.currentSession?.token)
        providerListShuffleSeed = UInt64.random(in: 1 ... UInt64.max)
    }
}

// MARK: - Deterministic shuffle (list order stable until seed changes)

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEADBEEF : seed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private extension Array {
    func shuffledWithStableSeed(_ seed: UInt64) -> [Element] {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return shuffled(using: &rng)
    }
}

private struct StickyBrowseHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Category chips on top; search row below with an **opaque** backing so list content is hidden when it scrolls under the field.
private struct StickyProviderBrowseChrome: View {
    @Binding var searchText: String
    @Binding var selectedCategory: ServiceProvider.ServiceCategory?
    let providers: [ServiceProvider]
    
    var body: some View {
        VStack(spacing: 0) {
            CategoryFilterBar(
                selectedCategory: $selectedCategory,
                providers: providers
            )
            VStack(spacing: 0) {
                SearchBar(
                    text: $searchText,
                    placeholder: "Search providers",
                    fillsSearchFieldBackground: false
                )
                .padding(.horizontal, .space4)
                .padding(.top, .space3)
                .padding(.bottom, .space2)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .background {
                Group {
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                    } else {
                        Rectangle()
                            .fill(Color.white)
                    }
                    #else
                    Rectangle()
                        .fill(Color.white)
                    #endif
                }
                .shadow(color: Color.black.opacity(0.07), radius: 4, y: 2)
            }
            .compositingGroup()
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: StickyBrowseHeaderHeightKey.self,
                    value: geo.size.height
                )
            }
        )
    }
}

struct CategoryFilterBar: View {
    @Binding var selectedCategory: ServiceProvider.ServiceCategory?
    let providers: [ServiceProvider]
    
    private func hasProviders(for category: ServiceProvider.ServiceCategory) -> Bool {
        providers.contains { $0.category == category }
    }
    
    private var chipScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .space3) {
                // "All" chip
                CategoryChip(
                    title: "All",
                    isSelected: selectedCategory == nil,
                    isEnabled: true
                ) {
                    selectedCategory = nil
                }
                
                // Category chips
                ForEach(ServiceProvider.ServiceCategory.allCases) { category in
                    let isEnabled = hasProviders(for: category)
                    
                    CategoryChip(
                        title: category.displayName,
                        isSelected: selectedCategory == category,
                        isEnabled: isEnabled
                    ) {
                        if isEnabled {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, .space4)
            .padding(.vertical, .space3)
        }
    }
    
    var body: some View {
        chipScroll
    }
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(InteraFont.bodySmall)
            .fontWeight(isSelected ? .semibold : .medium)
            .foregroundStyle(
                isEnabled
                    ? (isSelected ? Color.white : Color.lavaShellCream)
                    : Color.lavaShellCreamTertiary
            )
            .padding(.horizontal, .space4)
            .padding(.vertical, .space2)
            .background(
                isEnabled 
                    ? (isSelected ? Color.oliveGreen : Color.oliveTint)
                    : Color.neutral200
            )
            .clipShape(Capsule())
            .opacity(isEnabled ? 1.0 : 0.6)
        }
        .disabled(!isEnabled)
    }
}

/// Shown when `GET /barbers` returns no providers within the consumer’s distance preference.
private struct HomeNoBarbersInRadiusEmptyLabel: View {
    var body: some View {
        Text("No service providers in your selectable radius")
            .font(InteraFont.headlineMedium)
            .foregroundStyle(Color.lavaShellCream)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 280)
            .padding(.horizontal, .space4)
            .padding(.bottom, .space6)
            .frame(minHeight: 520, alignment: .top)
    }
}


