//
//  ConsumerChatNavigation.swift
//  OnCuts
//
//  ConversationListView (global inbox) + booking-thread handoffs via `ChatViewModel` / `MessagingConversationView`.
//

import SwiftUI

// MARK: - Inbox

struct ConversationListView: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    /// Consumer shell: dismiss inbox and return to browse. Barber tab shell: omit to use `navigateToTab(.home)`.
    var onBrowseServiceProviders: (() -> Void)? = nil
    /// When set (e.g. main hub tab), signed-out users are kept on Home by the hub shell.
    /// Hub paged `TabView` should disable horizontal swiping while a thread is open so interactive back doesn’t change tabs. Second value is the open ``conversationId`` when `visible == true`.
    var onThreadPresentationChanged: ((Bool, String) -> Void)? = nil
    /// Hub Messages tab only: reset the wrapping `NavigationStack` identity before opening a thread from a **push tap** so a fresh stack presents ``ChatViewModel/hubMessagesThreadPresentation`` without stacking a second `MessagingConversationView` after resume from background.
    var onResetMessagesNavigationStackBeforePush: (() -> Void)? = nil
    /// Passed through to `ConsumerBookingDetailView` when opening booking detail from a thread.
    var hasActiveConsumerBooking: Bool = false
    var onShowLogin: (() -> Void)? = nil

    @EnvironmentObject private var chatViewModel: ChatViewModel
    @Environment(\.onCutsHubBarOverlayBottomInset) private var hubBarOverlayBottomInset

    @State private var consumerBookings: [ConsumerBookingSimpleRow] = []
    /// Cancels superseded push-open work when `pendingPushConversationId` changes or the hub stack is reset.
    @State private var pendingPushNavigationTask: Task<Void, Never>?
    @State private var showMessagingTermsGate = false
    /// When a push/deeplink opens a thread before terms are accepted, resume here after "I agree".
    @State private var pendingConversationOpenAfterTerms: String?
    /// Empty-inbox **Message** (same as hub home-shell booking message): resume after terms acceptance.
    @State private var pendingBookingMessagingAfterTerms: ConsumerBookingSimpleRow?
    @State private var quickThreadError: String?

    private var resolvedEmptyStatePhase: MessagesEmptyStatePhase {
        if let booking = Self.latestActiveBookingForEmptyInbox(from: consumerBookings) {
            return .activeBooking(booking)
        }
        return .noBookings
    }

    /// Match `ConsumerBookingsHubView` / hub shell: clear on iOS so `RootView`’s lava reads consistently.
    @ViewBuilder
    private var inboxBackgroundLayer: some View {
        #if os(iOS)
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        OnCutsLiquidMeshBackground()
        #endif
    }

    @ViewBuilder
    private var inboxMainContent: some View {
        if !sessionManager.isAuthenticated {
            ContentUnavailableView(
                "Sign in required",
                systemImage: "message.badge",
                description: Text("Sign in to see your conversations.")
            )
        } else if chatViewModel.rows.isEmpty {
            ScrollView {
                MessagesEmptyState(
                    phase: resolvedEmptyStatePhase,
                    onBrowseServiceProviders: {
                        if let onBrowseServiceProviders {
                            onBrowseServiceProviders()
                        } else {
                            coordinator.navigateToTab(.home)
                        }
                    },
                    onOpenBookingConversation: { booking in
                        Task { await openBookingThreadUsingHomeShellMessageFlow(booking: booking) }
                    }
                )
                .padding(.bottom, hubBarOverlayBottomInset)
            }
            #if os(iOS)
            .scrollBounceBehavior(.always, axes: .vertical)
            #endif
            .onCutsHubBarScrollOffsetReporting(pageIndex: 1)
            .refreshable { await reloadInboxForPullToRefresh() }
        } else {
            inboxConversationRowsScroll
        }
    }

    /// Single `navigationDestination(item:)` for threads — **never** combine with `NavigationLink` to the same destination
    /// or SwiftUI stacks two `MessagingConversationView`s (split socket/REST state vs visible UI).
    private var inboxConversationRowsScroll: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(chatViewModel.rows) { row in
                    Button {
                        let cid = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cid.isEmpty else { return }
                        if let open = chatViewModel.hubMessagesThreadPresentation,
                           open.conversationId.caseInsensitiveCompare(cid) == .orderedSame {
                            return
                        }
                        chatViewModel.prefetchThreadMessages(conversationId: cid, sessionManager: sessionManager)
                        chatViewModel.presentHubMessagesThread(ChatViewModel.HubMessagesThreadPresentation(row: row))
                    } label: {
                        ConversationInboxThreadCard(
                            model: MessageThreadDisplayModel(row: row),
                            currentUserId: sessionManager.currentSession?.userId ?? ""
                        )
                    }
                    .buttonStyle(ConversationCardPressStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, hubBarOverlayBottomInset)
        }
        #if os(iOS)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.always, axes: .vertical)
        #endif
        .onCutsHubBarScrollOffsetReporting(pageIndex: 1)
        .refreshable { await reloadInboxForPullToRefresh() }
    }

    private var inboxRootStack: some View {
        ZStack {
            inboxBackgroundLayer
            inboxMainContent
        }
    }

    private var inboxWithNavigationChrome: some View {
        let showingThread = chatViewModel.hubMessagesThreadPresentation != nil
        return inboxRootStack
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Match Home: hide the empty system bar and pad to the shared hub chrome line.
            .toolbar(showingThread ? .automatic : .hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .tint(Color.oliveGreen)
            .padding(.top, showingThread ? 0 : OnCutsHubChromeLayout.floatingChromeTopPadding())
            .ignoresSafeArea(edges: showingThread ? [] : .top)
    }

    private var inboxWithThreadAndHandoffObservers: some View {
        inboxWithNavigationChrome
            .navigationDestination(item: $chatViewModel.hubMessagesThreadPresentation) { handoff in
                MessagingConversationView(
                    conversationId: handoff.conversationId,
                    sessionManager: sessionManager,
                    coordinator: coordinator,
                    initialBooking: handoff.bookingSnapshot,
                    counterpartyAvatarURLString: handoff.counterpartyAvatarURLString,
                    counterpartyFallbackDisplayName: handoff.counterpartyName,
                    initialDraftText: handoff.initialDraft.isEmpty ? nil : handoff.initialDraft,
                    onRequestPopFromParent: nil,
                    onNavigationVisibilityChanged: { visible, conversationId in
                        if visible {
                            chatViewModel.hubForegroundConversationId = conversationId
                        } else if chatViewModel.hubForegroundConversationId?.caseInsensitiveCompare(conversationId) == .orderedSame {
                            chatViewModel.hubForegroundConversationId = nil
                        }
                        onThreadPresentationChanged?(visible, conversationId)
                    },
                    onInitialThreadHydrationComplete: nil,
                    onResyncSharedHubInboxSilently: {
                        await chatViewModel.reloadInboxSilently(sessionManager: sessionManager)
                    },
                    counterpartyUserId: handoff.counterpartyUserId,
                    hasActiveConsumerBooking: hasActiveConsumerBooking,
                    onShowLogin: onShowLogin
                )
            }
            .onChange(of: chatViewModel.pendingPushConversationId) { _, new in
                guard new != nil else { return }
                Task { @MainActor in
                    scheduleOpenConversationFromPushIfNeeded()
                }
            }
            .onAppear {
                Task { @MainActor in
                    if let cid = chatViewModel.pendingPushOpenBlockedByTerms?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !cid.isEmpty {
                        chatViewModel.pendingPushOpenBlockedByTerms = nil
                        pendingConversationOpenAfterTerms = cid
                        showMessagingTermsGate = true
                    }
                    scheduleOpenConversationFromPushIfNeeded()
                }
            }
        }

    private var inboxWithRefreshAndTask: some View {
        inboxWithThreadAndHandoffObservers
            .onAppear {
                if sessionManager.isAuthenticated, !MessagingCommunitySafety.hasAcceptedMessagingTerms {
                    showMessagingTermsGate = true
                }
            }
            // `TabView` removes off-screen tabs: each return to Messages re-instantiates this view and re-runs `.task`.
            .task(id: sessionManager.isAuthenticated) {
                guard sessionManager.isAuthenticated else { return }
                await chatViewModel.reloadInboxSilently(sessionManager: sessionManager)
                if chatViewModel.rows.isEmpty {
                    await loadConsumerBookingsForEmptyContext()
                    await reloadInboxOnceIfAcceptedButStillEmpty()
                }
            }
            .onChange(of: sessionManager.isAuthenticated) { _, authed in
                if !authed {
                    consumerBookings = []
                    pendingPushNavigationTask?.cancel()
                    pendingPushNavigationTask = nil
                    chatViewModel.clearHubMessagesThreadPresentation()
                    pendingBookingMessagingAfterTerms = nil
                }
            }
            .sheet(isPresented: $showMessagingTermsGate) {
                MessagingUGCTermsGateView(
                    onAccept: {
                        MessagingCommunitySafety.setMessagingTermsAccepted()
                        showMessagingTermsGate = false
                        if let booking = pendingBookingMessagingAfterTerms {
                            pendingBookingMessagingAfterTerms = nil
                            Task { await openBookingThreadUsingHomeShellMessageFlow(booking: booking) }
                        } else if let cid = pendingConversationOpenAfterTerms?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty {
                            pendingConversationOpenAfterTerms = nil
                            Task { await openConversationFromPushNotification(conversationId: cid) }
                        }
                    }
                )
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .messagingBlockedUserDidChange)) { _ in
                Task { await chatViewModel.reloadInboxSilently(sessionManager: sessionManager) }
            }
    }

    private var listLoadErrorBinding: Binding<Bool> {
        Binding(
            get: { chatViewModel.listLoadError != nil },
            set: { if !$0 { chatViewModel.listLoadError = nil } }
        )
    }

    private var quickThreadErrorBinding: Binding<Bool> {
        Binding(
            get: { quickThreadError != nil },
            set: { if !$0 { quickThreadError = nil } }
        )
    }

    var body: some View {
        inboxWithRefreshAndTask
            .alert("Couldn’t load conversations", isPresented: listLoadErrorBinding) {
                Button("OK") { chatViewModel.listLoadError = nil }
            } message: {
                Text(chatViewModel.listLoadError ?? "")
            }
            .alert("Couldn’t open chat", isPresented: quickThreadErrorBinding) {
                Button("OK") { quickThreadError = nil }
            } message: {
                Text(quickThreadError ?? "")
            }
    }

    @MainActor
    private func scheduleOpenConversationFromPushIfNeeded() {
        pendingPushNavigationTask?.cancel()
        guard chatViewModel.pendingPushConversationId != nil else { return }
        pendingPushNavigationTask = Task { @MainActor in
            guard let cid = chatViewModel.consumePendingPushConversationId() else { return }
            if let open = chatViewModel.hubMessagesThreadPresentation,
               open.conversationId.caseInsensitiveCompare(cid) == .orderedSame {
                return
            }
            guard chatViewModel.beginPushConversationOpenInFlight(cid) else { return }
            defer { chatViewModel.endPushConversationOpenInFlight(cid) }
            let needsStackReset = chatViewModel.hubMessagesThreadPresentation != nil
                || chatViewModel.hubForegroundConversationId != nil
            if needsStackReset, let reset = onResetMessagesNavigationStackBeforePush {
                chatViewModel.clearHubMessagesThreadPresentation()
                reset()
                await Task.yield()
                await Task.yield()
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            await chatViewModel.presentHubThreadFromMessagePush(
                conversationId: cid,
                sessionManager: sessionManager
            )
        }
    }

    @MainActor
    private func openConversationFromPushNotification(conversationId: String) async {
        await chatViewModel.presentHubThreadFromMessagePush(
            conversationId: conversationId,
            sessionManager: sessionManager
        )
        if chatViewModel.pendingPushOpenBlockedByTerms != nil {
            let cid = chatViewModel.pendingPushOpenBlockedByTerms?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cid.isEmpty else { return }
            chatViewModel.pendingPushOpenBlockedByTerms = nil
            pendingConversationOpenAfterTerms = cid
            showMessagingTermsGate = true
        }
    }

    /// Matches `ScreensConsumerHome.openUnifiedChatForBarberProfileId` → `presentMessagingThreadForBooking(..., .homeShellNavigation)` (hub outer `NavigationStack`, empty initial draft).
    @MainActor
    private func openBookingThreadUsingHomeShellMessageFlow(booking: ConsumerBookingSimpleRow) async {
        guard sessionManager.isAuthenticated else { return }

        guard MessagingCommunitySafety.hasAcceptedMessagingTerms else {
            pendingBookingMessagingAfterTerms = booking
            showMessagingTermsGate = true
            return
        }

        quickThreadError = nil
        await chatViewModel.presentMessagingThreadForBooking(
            row: booking,
            sessionManager: sessionManager,
            presentationStack: .homeShellNavigation
        )
        if chatViewModel.homeStackMessagingHandoff == nil {
            quickThreadError = "We couldn’t open this conversation yet. Try the Messages tab after a refresh, or check back shortly."
        }
    }

    @MainActor
    private func loadConsumerBookingsForEmptyContext() async {
        guard sessionManager.isAuthenticated else {
            consumerBookings = []
            return
        }
        do {
            consumerBookings = try await ConsumerBookingsSimpleAPI.fetchConsumerBookings(
                bearerToken: sessionManager.currentSession?.token,
                consumerUserId: sessionManager.currentSession?.userId
            )
        } catch {
            if OnCutsRefreshCancellation.isBenignCancellation(error) { return }
            consumerBookings = []
        }
    }

    @MainActor
    private func reloadInboxForPullToRefresh() async {
        await OnCutsPullToRefresh.runMainActorAsyncIsolatedFromRefreshableCancellation {
            await chatViewModel.reloadInboxSilently(sessionManager: sessionManager)
            if chatViewModel.rows.isEmpty {
                await loadConsumerBookingsForEmptyContext()
                await reloadInboxOnceIfAcceptedButStillEmpty()
            }
        }
    }

    /// Accepted bookings often get a conversation row moments after the first inbox fetch; a second reload avoids a stale “empty inbox” card.
    @MainActor
    private func reloadInboxOnceIfAcceptedButStillEmpty() async {
        guard chatViewModel.rows.isEmpty else { return }
        let hasAccepted = consumerBookings.contains {
            $0.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) == "ACCEPTED"
        }
        guard hasAccepted else { return }
        await chatViewModel.reloadInboxSilently(sessionManager: sessionManager)
    }

    /// PENDING / ACCEPTED bookings the consumer still cares about in messaging; used only when the inbox API returned no rows yet.
    private static func latestActiveBookingForEmptyInbox(from rows: [ConsumerBookingSimpleRow]) -> ConsumerBookingSimpleRow? {
        rows.filter { row in
            let s = row.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return s == "PENDING" || s == "ACCEPTED"
        }
        .sorted { a, b in
            let da = a.scheduledAtDate ?? .distantPast
            let db = b.scheduledAtDate ?? .distantPast
            if da != db { return da > db }
            return a.id > b.id
        }
        .first
    }
}
