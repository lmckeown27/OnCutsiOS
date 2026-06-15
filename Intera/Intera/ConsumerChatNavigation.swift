//
//  ConsumerChatNavigation.swift
//  Intera
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
    /// When set (e.g. main hub tab), signed-out users see `HubGuestAuthPrompt` instead of a static empty state.
    var onRequestSignIn: (() -> Void)? = nil
    var onRequestSignUp: (() -> Void)? = nil
    /// Hub paged `TabView` should disable horizontal swiping while a thread is open so interactive back doesn’t change tabs. Second value is the open ``conversationId`` when `visible == true`.
    var onThreadPresentationChanged: ((Bool, String) -> Void)? = nil
    /// Hub Messages tab only: reset the wrapping `NavigationStack` identity before opening a thread from a **push tap** so a fresh stack presents ``ChatViewModel/hubMessagesThreadPresentation`` without stacking a second `MessagingConversationView` after resume from background.
    var onResetMessagesNavigationStackBeforePush: (() -> Void)? = nil

    @EnvironmentObject private var chatViewModel: ChatViewModel

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
        InteraLiquidMeshBackground()
        #endif
    }

    @ViewBuilder
    private var inboxMainContent: some View {
        if !sessionManager.isAuthenticated {
            if let onSignIn = onRequestSignIn, let onSignUp = onRequestSignUp {
                HubGuestAuthPrompt(
                    title: "Messages with your providers",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    signInCallout: "Sign in to read and send messages about your bookings.",
                    onSignIn: onSignIn,
                    onSignUp: onSignUp
                )
            } else {
                ContentUnavailableView(
                    "Sign in required",
                    systemImage: "message.badge",
                    description: Text("Sign in to see your conversations.")
                )
            }
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
            }
            #if os(iOS)
            .scrollBounceBehavior(.always, axes: .vertical)
            #endif
            .refreshable { await reloadInboxForPullToRefresh() }
        } else {
            inboxConversationRowsScroll
        }
    }

    /// Single `navigationDestination(item:)` for threads — **never** combine with `NavigationLink` to the same destination
    /// or SwiftUI stacks two `MessagingConversationView`s (split socket/REST state vs visible UI).
    private var inboxConversationRowsScroll: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
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
                        ConversationListTimelineRow(row: row, currentUserId: sessionManager.currentSession?.userId ?? "")
                    }
                    .buttonStyle(InboxRowLiquidPressStyle())
                }
            }
        }
        #if os(iOS)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.always, axes: .vertical)
        #endif
        .refreshable { await reloadInboxForPullToRefresh() }
    }

    private var inboxRootStack: some View {
        ZStack {
            inboxBackgroundLayer
            inboxMainContent
        }
    }

    private var inboxWithNavigationChrome: some View {
        inboxRootStack
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .tint(Color.oliveGreen)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
                    counterpartyUserId: handoff.counterpartyUserId
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
            await openConversationFromPushNotification(conversationId: cid)
        }
    }

    @MainActor
    private func openConversationFromPushNotification(conversationId: String) async {
        guard sessionManager.isAuthenticated else { return }
        let trimmed = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard MessagingCommunitySafety.hasAcceptedMessagingTerms else {
            pendingConversationOpenAfterTerms = trimmed
            showMessagingTermsGate = true
            return
        }
        if let open = chatViewModel.hubMessagesThreadPresentation,
           open.conversationId.caseInsensitiveCompare(trimmed) == .orderedSame {
            return
        }
        if chatViewModel.hubMessagesThreadPresentation == nil {
            chatViewModel.hubForegroundConversationId = nil
        }
        chatViewModel.prefetchThreadMessages(conversationId: trimmed, sessionManager: sessionManager)
        if chatViewModel.rows.first(where: { $0.id.caseInsensitiveCompare(trimmed) == .orderedSame }) == nil {
            await chatViewModel.reloadInboxSilently(sessionManager: sessionManager)
        }
        let row = chatViewModel.rows.first(where: { $0.id.caseInsensitiveCompare(trimmed) == .orderedSame })
        chatViewModel.presentHubMessagesThread(
            ChatViewModel.HubMessagesThreadPresentation.minimal(
                conversationId: trimmed,
                rowIfKnown: row
            )
        )
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
            if InteraRefreshCancellation.isBenignCancellation(error) { return }
            consumerBookings = []
        }
    }

    @MainActor
    private func reloadInboxForPullToRefresh() async {
        await InteraPullToRefresh.runMainActorAsyncIsolatedFromRefreshableCancellation {
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

// MARK: - Inbox timeline rows (LazyVStack + booking-style rail)

/// Typography aligned with `TimelineSectionHeader` (Today / Past) and `BookingTimelineRow` upcoming `compactLabels` service line.
private enum ConversationInboxTimelineTypography {
    /// `TimelineSectionHeader` “Today”.
    static let providerName = InteraFont.system(size: 28, weight: .bold, design: .default)
    /// Same size as `headlineSmall` (18pt) but **regular** weight for preview body over lava.
    static let messagePreview = InteraFont.system(size: 18, weight: .regular, design: .serif)
    static let messagePreviewLineSpacing: CGFloat = 4
    /// Occupation · service under the preview (leading).
    static let pastHeaderKerning: CGFloat = 2.2
    static let occupationKerning: CGFloat = pastHeaderKerning * 1.15
    static let occupationFont = InteraFont.system(size: 14, weight: .medium, design: .default)
    /// Caps preview width so the stack sits right of the enlarged avatar.
    static let messagePreviewMaxWidth: CGFloat = 300
}

private struct InboxRowLiquidPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.02 : 1.0)
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct ConversationListTimelineRow: View {
    let row: ChatViewModel.PreviewRow
    let currentUserId: String

    /// Provider avatar sits **outside** the preview card (same `imageUrl` pipeline as thread header / `AvatarView`).
    private static let rowAvatarSize: CGFloat = 92
    private static let rowAvatarCornerRadius: CGFloat = 16

    private var trimmedPreview: String {
        (row.lastMessagePreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hub **Messages** row: latest line from you or your provider (`ChatViewModel` + REST merge).
    private var messageBoxDisplayText: String {
        trimmedPreview.isEmpty ? "No messages yet" : trimmedPreview
    }

    private var messageBoxIsPlaceholder: Bool {
        trimmedPreview.isEmpty
    }

    private var rowTerminalDim: Bool {
        row.booking?.inboxRowIsTerminalPastContinuum == true
    }

    private var lastMessageIsFromCounterparty: Bool {
        let me = currentUserId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !me.isEmpty else { return (row.unreadCount ?? 0) > 0 }
        if let sid = row.lastMessageSenderId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !sid.isEmpty {
            return sid != me
        }
        return (row.unreadCount ?? 0) > 0
    }

    private var messagePreviewBoxIsLit: Bool {
        !messageBoxIsPlaceholder && lastMessageIsFromCounterparty
    }

    private var showsIncomingUnreadDot: Bool {
        messagePreviewBoxIsLit && (row.unreadCount ?? 0) > 0
    }

    private var messageBoxTextColor: Color {
        if messageBoxIsPlaceholder { return Color.lavaShellCreamTertiary }
        return messagePreviewBoxIsLit ? Color.lavaShellCream : Color.lavaShellCreamTertiary
    }

    private var messageBoxFill: Color {
        if messageBoxIsPlaceholder { return Color.white.opacity(0.06) }
        return messagePreviewBoxIsLit ? Color.white.opacity(0.18) : Color.white.opacity(0.07)
    }

    private var messageBoxStroke: Color {
        if messageBoxIsPlaceholder { return Color.lavaShellCream.opacity(0.14) }
        return messagePreviewBoxIsLit ? Color.lavaShellCream.opacity(0.42) : Color.lavaShellCream.opacity(0.16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(
                    imageUrl: row.inboxCounterpartyAvatarURLString,
                    name: row.inboxResolvedProviderTitle,
                    size: Self.rowAvatarSize,
                    fontSize: 34,
                    clipStyle: .square(cornerRadius: Self.rowAvatarCornerRadius)
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(row.inboxResolvedProviderTitle)
                        .font(ConversationInboxTimelineTypography.providerName)
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(rowTerminalDim ? 0.72 : 1)

                    HStack(alignment: .top, spacing: 10) {
                        Text(messageBoxDisplayText)
                            .font(ConversationInboxTimelineTypography.messagePreview)
                            .foregroundStyle(messageBoxTextColor)
                            .lineSpacing(ConversationInboxTimelineTypography.messagePreviewLineSpacing)
                            .lineLimit(5)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if showsIncomingUnreadDot {
                            MessagingInboxIncomingUnreadDot()
                                .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: ConversationInboxTimelineTypography.messagePreviewMaxWidth, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(messageBoxFill)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(messageBoxStroke, lineWidth: 1)
                    }
                    .accessibilityLabel(
                        messageBoxIsPlaceholder
                            ? "No messages yet"
                            : showsIncomingUnreadDot
                                ? "Unread message, \(trimmedPreview)"
                                : "Latest message, \(trimmedPreview)"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 2)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(MessagingProviderRoleLine.occupationAndServicePresentable(booking: row.booking))
                    .font(ConversationInboxTimelineTypography.occupationFont)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .kerning(ConversationInboxTimelineTypography.occupationKerning)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                if let sched = row.booking?.inboxCompactScheduledDisplay, !sched.isEmpty {
                    Spacer(minLength: 8)
                    Text(sched)
                        .font(ConversationInboxTimelineTypography.occupationFont)
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(rowTerminalDim ? 0.72 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .background {
            ZStack {
                Color.white.opacity(0.05)
                Color.black.opacity(0.1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.lavaShellCream.opacity(0.28))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

}

private extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
