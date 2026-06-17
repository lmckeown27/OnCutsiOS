//
//  ChatViewModel.swift
//  Intera
//
//  Shared inbox previews + one Socket.IO connection for `new-message` (list + open thread).
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    struct PreviewRow: Identifiable {
        let id: String
        var booking: MessagingBookingDTO?
        var otherUser: MessagingConversationOtherUserDTO?
        var lastMessagePreview: String?
        var lastMessageSenderId: String?
        var updatedAt: String?
        var unreadCount: Int?

        init(dto: MessagingConversationRowDTO) {
            id = dto.id
            booking = dto.booking
            otherUser = dto.otherUser
            lastMessagePreview = dto.lastMessagePreview
            lastMessageSenderId = dto.lastMessageSenderId
            updatedAt = dto.updatedAt
            unreadCount = dto.unreadCount
        }

        init(
            id: String,
            booking: MessagingBookingDTO?,
            lastMessagePreview: String?,
            otherUser: MessagingConversationOtherUserDTO? = nil,
            updatedAt: String? = nil,
            unreadCount: Int? = nil,
            lastMessageSenderId: String? = nil
        ) {
            self.id = id
            self.booking = booking
            self.otherUser = otherUser
            self.lastMessagePreview = lastMessagePreview
            self.lastMessageSenderId = lastMessageSenderId
            self.updatedAt = updatedAt
            self.unreadCount = unreadCount
        }

        /// Same rules as `MessagingConversationRowDTO.inboxResolvedProviderTitle`.
        var inboxResolvedProviderTitle: String {
            if let n = booking?.inboxProviderNameIfKnown { return n }
            if let n = otherUser?.resolvedDisplayName() { return n }
            return "Conversation"
        }

        /// Same rules as `MessagingConversationRowDTO.inboxCounterpartyAvatarURLString`.
        var inboxCounterpartyAvatarURLString: String? {
            MessagingNonEmptyURL.first(booking?.barberProfileImageUrl, [otherUser?.profilePicture])
        }
    }

    @Published private(set) var rows: [PreviewRow] = []
    @Published var listLoadError: String?
    /// Drives the Messages toolbar/tab badges (`GET /api/v1/messages/unread-count`).
    @Published private(set) var unreadMessageCount: Int = 0

    /// Set when the user opens a message push; `ConversationListView` consumes this to push the thread.
    @Published var pendingPushConversationId: String?
    /// While a push deep-link is opening a hub thread, blocks duplicate work when the Messages `NavigationStack` identity resets.
    private(set) var pushConversationOpenInFlight: String?

    /// Single source of truth for the hub / embedded inbox `navigationDestination(item:)` → `MessagingConversationView`. Row taps, push opens, and post–stack-reset resume all set this (never duplicate local `NavigationLink` handoffs).
    struct HubMessagesThreadPresentation: Hashable, Identifiable {
        let nonce: UUID
        let conversationId: String
        let initialDraft: String
        let bookingSnapshot: MessagingBookingDTO?
        let counterpartyAvatarURLString: String?
        let counterpartyName: String?
        let counterpartyUserId: String?

        var id: UUID { nonce }

        init(
            nonce: UUID = UUID(),
            conversationId: String,
            initialDraft: String = "",
            bookingSnapshot: MessagingBookingDTO?,
            counterpartyAvatarURLString: String?,
            counterpartyName: String?,
            counterpartyUserId: String?
        ) {
            self.nonce = nonce
            self.conversationId = conversationId
            self.initialDraft = initialDraft
            self.bookingSnapshot = bookingSnapshot
            self.counterpartyAvatarURLString = counterpartyAvatarURLString
            self.counterpartyName = counterpartyName
            self.counterpartyUserId = counterpartyUserId
        }

        init(row: PreviewRow) {
            let cid = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
            self.init(
                conversationId: cid,
                bookingSnapshot: row.booking,
                counterpartyAvatarURLString: row.inboxCounterpartyAvatarURLString,
                counterpartyName: row.inboxResolvedProviderTitle,
                counterpartyUserId: row.otherUser?.id
            )
        }

        /// Push / deep link: prefer inbox row metadata when `rows` already contains this thread; otherwise bare `conversationId` until the thread hydrates.
        static func minimal(conversationId: String, rowIfKnown: PreviewRow?) -> HubMessagesThreadPresentation {
            let trimmed = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
            if let row = rowIfKnown {
                return HubMessagesThreadPresentation(row: row)
            }
            return HubMessagesThreadPresentation(
                conversationId: trimmed,
                bookingSnapshot: nil,
                counterpartyAvatarURLString: nil,
                counterpartyName: nil,
                counterpartyUserId: nil
            )
        }
    }

    @Published var hubMessagesThreadPresentation: HubMessagesThreadPresentation?

    /// Bumped whenever a ``MessagingConversationView`` appears. Deferred `onDisappear` teardown on a **destroyed**
    /// view instance must compare against this shared value — per-view `@State` resets with navigation identity
    /// changes, which previously let a stale task call ``setThreadMessageHandler(_:handler:)`` with `nil` and
    /// drop the live handler for the replacement screen.
    private(set) var messagingThreadSurfaceEpoch: UInt64 = 0

    /// Hub Messages tab only: which conversation is the visible navigation destination (`nil` = inbox). Used to avoid stacking a second thread when a message push is opened while already in that conversation.
    @Published var hubForegroundConversationId: String?

    /// Clears hub thread navigation and any stale foreground id (e.g. after a Messages `NavigationStack` identity reset aborted the push).
    func clearHubMessagesThreadPresentation() {
        hubMessagesThreadPresentation = nil
        hubForegroundConversationId = nil
    }

    /// Presents a hub Messages thread and clears a mismatched foreground id left by an aborted push.
    func presentHubMessagesThread(_ presentation: HubMessagesThreadPresentation) {
        withAnimation(MessagingFlowMotion.threadNavigationPush) {
            hubMessagesThreadPresentation = presentation
        }
        let cid = presentation.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return }
        if let fg = hubForegroundConversationId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fg.isEmpty,
           fg.caseInsensitiveCompare(cid) != .orderedSame {
            hubForegroundConversationId = nil
        }
    }

    /// One-shot consume for message-push deep links so rebuilding the Messages `NavigationStack` does not re-run open logic.
    func consumePendingPushConversationId() -> String? {
        let raw = pendingPushConversationId
        pendingPushConversationId = nil
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func beginPushConversationOpenInFlight(_ conversationId: String) -> Bool {
        let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return false }
        if let inFlight = pushConversationOpenInFlight?.trimmingCharacters(in: .whitespacesAndNewlines),
           !inFlight.isEmpty,
           inFlight.caseInsensitiveCompare(cid) == .orderedSame {
            return false
        }
        pushConversationOpenInFlight = cid
        return true
    }

    func endPushConversationOpenInFlight(_ conversationId: String) {
        let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return }
        if pushConversationOpenInFlight?.caseInsensitiveCompare(cid) == .orderedSame {
            pushConversationOpenInFlight = nil
        }
    }

    /// Set when the user opens a booking-status push (confirmed, cancelled, reminder, etc.); `ConsumerBookingsHubView` pushes `ConsumerBookingDetailView`.
    @Published var pendingOpenBookingDetailId: String?

    /// When non-nil, the consumer must complete web checkout for this booking (provider marked service complete).
    @Published var activePaymentRequest: BookingPaymentRequestPayload?

    /// Booking ids the user dismissed with **Pay later** — `syncPaymentTakeover` / socket will not auto-present again until they tap **Pay** on the booking detail.
    private var deferredPaymentTakeoverBookingIds: Set<String> = []

    /// After successful pay (card/cash), optional star + text review before returning home.
    @Published var postPaymentReviewContext: PostPaymentReviewContext?

    /// Same handoff shape as inbox `NavigationLink` → `MessagingConversationView`.
    struct BookingMessagingThreadHandoff: Hashable, Identifiable {
        let nonce: UUID
        let conversationId: String
        let initialDraft: String
        let bookingSnapshot: MessagingBookingDTO?
        let counterpartyAvatarURLString: String?
        let counterpartyFallbackName: String?
        let counterpartyMessagingUserId: String?

        var id: UUID { nonce }
    }

    enum BookingMessagingThreadPresentationStack {
        /// `ConsumerBookingsHubView` inner `NavigationStack` — back returns to booking detail / timeline.
        case bookingsTabNavigation
        /// `ConsumerHomeScreen` / `UnifiedProviderHomeScreen` outer stack (e.g. home reminder detail).
        case homeShellNavigation
    }

    /// Legacy / unused on path-backed stacks — booking detail uses `NavigationPath` append instead.
    enum BookingDetailMessagingMode: Sendable {
        case bookingsTab
        case homeBookingPathHandoff
    }

    @Published var bookingsTabMessagingThreadHandoff: BookingMessagingThreadHandoff?
    /// Browse / empty-state on the home outer stack (`NavigationPath` empty).
    @Published var homeStackMessagingHandoff: BookingMessagingThreadHandoff?
    /// Thread above home-pushed booking detail (`NavigationPath` has `.detail` only).
    @Published var homeBookingMessagingThreadHandoff: BookingMessagingThreadHandoff?

    private static func normalizedConversationKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private let socket = MessagingSocketController()
    private var connectedBearerToken: String?
    private var connectedUserId: String?
    /// Open thread receives copies of `new-message` for its `conversationId` (no second socket).
    private var threadMessageHandlers: [String: (MessagingMessageDTO) -> Void] = [:]
    /// Events that arrive after REST history is applied but before ``setThreadMessageHandler`` runs (same `Task` tick), or during a brief navigation edge.
    private var pendingThreadSocketMessages: [String: [MessagingMessageDTO]] = [:]
    private static let maxPendingSocketMessagesPerConversation = 48

    /// Every `new-message` the socket delivers for a conversation (same payloads that drive inbox previews via ``registerSentMessage``).
    /// Replayed into ``MessagingConversationView`` after the thread handler is wired so bubbles stay in sync when REST lags or room join races.
    private var inboundSocketMessageTapeByConversation: [String: [MessagingMessageDTO]] = [:]
    private static let maxInboundSocketTapePerConversation = 48

    struct CachedThreadSnapshot {
        let messages: [MessagingMessageDTO]
        let booking: MessagingBookingDTO?
        let otherUser: MessagingConversationOtherUserDTO?
    }

    private var threadSnapshotCache: [String: CachedThreadSnapshot] = [:]
    private var threadPrefetchTasks: [String: Task<Void, Never>] = [:]
    private static let maxThreadSnapshotCacheEntries = 12

    func cachedThreadSnapshot(conversationId: String) -> CachedThreadSnapshot? {
        let key = Self.normalizedConversationKey(conversationId)
        guard !key.isEmpty else { return nil }
        return threadSnapshotCache[key]
    }

    func recordThreadSnapshot(
        conversationId: String,
        messages: [MessagingMessageDTO],
        booking: MessagingBookingDTO?,
        otherUser: MessagingConversationOtherUserDTO?
    ) {
        let key = Self.normalizedConversationKey(conversationId)
        guard !key.isEmpty else { return }
        threadSnapshotCache[key] = CachedThreadSnapshot(
            messages: messages,
            booking: booking,
            otherUser: otherUser
        )
        if threadSnapshotCache.count > Self.maxThreadSnapshotCacheEntries {
            let drop = threadSnapshotCache.keys.sorted().prefix(threadSnapshotCache.count - Self.maxThreadSnapshotCacheEntries)
            for k in drop { threadSnapshotCache.removeValue(forKey: k) }
        }
    }

    /// Waits for an in-flight ``prefetchThreadMessages`` so ``MessagingConversationView`` does not duplicate the same GET.
    func awaitThreadPrefetchIfNeeded(conversationId: String) async {
        let key = Self.normalizedConversationKey(conversationId)
        guard !key.isEmpty, let task = threadPrefetchTasks[key] else { return }
        await task.value
    }

    /// Warms the thread cache before navigation so the conversation can paint history immediately.
    func prefetchThreadMessages(conversationId: String, sessionManager: AppSessionManager) {
        let key = Self.normalizedConversationKey(conversationId)
        guard !key.isEmpty, sessionManager.isAuthenticated else { return }
        if threadSnapshotCache[key] != nil { return }
        if threadPrefetchTasks[key] != nil { return }
        threadPrefetchTasks[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.threadPrefetchTasks.removeValue(forKey: key) }
            guard !Task.isCancelled else { return }
            do {
                let result = try await MessagingAPIService.fetchConversationMessages(
                    conversationId: conversationId,
                    bearerToken: sessionManager.currentSession?.token
                )
                self.recordThreadSnapshot(
                    conversationId: conversationId,
                    messages: result.messages,
                    booking: result.booking,
                    otherUser: result.otherUser
                )
            } catch {
                if InteraRefreshCancellation.isBenignCancellation(error) { return }
            }
        }
    }

    /// Coalesce `GET /barbers/:id` + `POST …/messages/conversations` per booking id so the backend isn’t hit twice.
    private var bookingThreadResolveTasks: [String: Task<(String, String), Error>] = [:]

    /// Resolves barber messaging user id and opens or returns the booking-centric conversation id.
    func resolveBookingThreadConversation(
        barberProfileId: String,
        bookingRow: ConsumerBookingSimpleRow,
        bearerToken: String?
    ) async throws -> (conversationId: String, otherUserId: String) {
        let key = bookingRow.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw NSError(
                domain: "InteraMessaging",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing booking id."]
            )
        }
        if let existing = bookingThreadResolveTasks[key] {
            return try await existing.value
        }
        let barber = barberProfileId.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = bookingRow
        let token = bearerToken
        let task = Task<(String, String), Error> {
            guard !barber.isEmpty else {
                throw NSError(
                    domain: "InteraMessaging",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Missing provider for this booking."]
                )
            }
            guard let otherUserId = try await MessagingAPIService.fetchBarberMessagingUserId(
                barberProfileId: barber,
                bearerToken: token
            ), !otherUserId.isEmpty else {
                throw NSError(
                    domain: "InteraMessaging",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Could not resolve this provider’s account. Try again later."]
                )
            }
            let priceUsd: Double? = row.priceUsdCents.map { Double($0) / 100.0 }
            let cid = try await MessagingAPIService.startBookingConversation(
                otherUserId: otherUserId,
                bookingId: row.id,
                serviceName: row.displayServiceName,
                servicePriceUsd: priceUsd,
                scheduledTime: row.scheduledTime,
                location: row.location,
                notes: row.notes,
                barberName: row.barberName,
                barberProfilePicture: row.barberAvatar,
                bearerToken: token
            )
            return (cid, otherUserId)
        }
        bookingThreadResolveTasks[key] = task
        defer { bookingThreadResolveTasks.removeValue(forKey: key) }
        return try await task.value
    }

    /// When `bookings-simple` omits `barber_id`, or `startBookingConversation` / barber-id resolution fails, the inbox may
    /// already contain the thread (e.g. provider accepted first). Match by `booking.id` and build the same handoff shape.
    private func buildBookingMessagingHandoffFromInboxIfPossible(bookingRow: ConsumerBookingSimpleRow) -> BookingMessagingThreadHandoff? {
        let bookingId = bookingRow.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bookingId.isEmpty else { return nil }
        guard let inbox = rows.first(where: { r in
            let b = r.booking?.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !b.isEmpty && b.caseInsensitiveCompare(bookingId) == .orderedSame
        }) else { return nil }

        let cid = inbox.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return nil }

        let snapshot = inbox.booking ?? bookingRow.messagingBookingSnapshot
        let listTitle = inbox.inboxResolvedProviderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let rowBarber = bookingRow.barberName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackName: String? = {
            if !listTitle.isEmpty, listTitle.caseInsensitiveCompare("Conversation") != .orderedSame {
                return listTitle
            }
            return rowBarber.isEmpty ? nil : rowBarber
        }()

        return BookingMessagingThreadHandoff(
            nonce: UUID(),
            conversationId: cid,
            initialDraft: "",
            bookingSnapshot: snapshot,
            counterpartyAvatarURLString: inbox.inboxCounterpartyAvatarURLString,
            counterpartyFallbackName: fallbackName,
            counterpartyMessagingUserId: inbox.otherUser?.id
        )
    }

    private func applyBookingMessagingThreadPresentation(
        handoff: BookingMessagingThreadHandoff,
        presentationStack: BookingMessagingThreadPresentationStack,
        sessionManager: AppSessionManager
    ) -> BookingMessagingThreadHandoff? {
        hubMessagesThreadPresentation = nil
        switch presentationStack {
        case .bookingsTabNavigation:
            homeStackMessagingHandoff = nil
            promoteOrInsertConversationFromHandoff(handoff)
            prefetchThreadMessages(conversationId: handoff.conversationId, sessionManager: sessionManager)
            return handoff
        case .homeShellNavigation:
            promoteOrInsertConversationFromHandoff(handoff)
            prefetchThreadMessages(conversationId: handoff.conversationId, sessionManager: sessionManager)
            homeStackMessagingHandoff = handoff
            Task { @MainActor in
                await Task.yield()
                await Task.yield()
                await reloadInboxSilently(sessionManager: sessionManager)
            }
            return nil
        }
    }

    /// Resolves the thread, clears item handoffs, then appends `.messagingThread` on the host `NavigationPath`.
    /// Never use `navigationDestination(item:)` on the same stack as `NavigationStack(path:)` — that crashes on pop.
    @MainActor
    func presentBookingMessagingFromDetail(
        row: ConsumerBookingSimpleRow,
        sessionManager: AppSessionManager,
        appendToNavigationPath: (ChatViewModel.BookingMessagingThreadHandoff) -> Void
    ) async -> Bool {
        guard let handoff = await presentMessagingThreadForBooking(
            row: row,
            sessionManager: sessionManager,
            presentationStack: .bookingsTabNavigation
        ) else {
            return false
        }
        clearPathBackedMessagingItemHandoffs()
        await Task.yield()
        appendToNavigationPath(handoff)
        return true
    }

    @MainActor
    func clearPathBackedMessagingItemHandoffs() {
        bookingsTabMessagingThreadHandoff = nil
        homeBookingMessagingThreadHandoff = nil
        homeStackMessagingHandoff = nil
        hubMessagesThreadPresentation = nil
    }

    @MainActor
    @discardableResult
    func openBookingsTabMessagingThreadIfNeeded(_ handoff: BookingMessagingThreadHandoff) -> Bool {
        let key = Self.normalizedConversationKey(handoff.conversationId)
        guard !key.isEmpty else { return false }
        if let existing = bookingsTabMessagingThreadHandoff,
           Self.normalizedConversationKey(existing.conversationId) == key {
            return true
        }
        homeStackMessagingHandoff = nil
        homeBookingMessagingThreadHandoff = nil
        hubMessagesThreadPresentation = nil
        bookingsTabMessagingThreadHandoff = handoff
        return true
    }

    @MainActor
    @discardableResult
    func openHomeBookingMessagingThreadIfNeeded(_ handoff: BookingMessagingThreadHandoff) -> Bool {
        let key = Self.normalizedConversationKey(handoff.conversationId)
        guard !key.isEmpty else { return false }
        if let existing = homeBookingMessagingThreadHandoff,
           Self.normalizedConversationKey(existing.conversationId) == key {
            return true
        }
        homeStackMessagingHandoff = nil
        bookingsTabMessagingThreadHandoff = nil
        hubMessagesThreadPresentation = nil
        homeBookingMessagingThreadHandoff = handoff
        return true
    }

    /// Resolves the thread and returns a handoff. **Home shell** (inbox empty-state) sets ``homeStackMessagingHandoff``; booking detail uses ``presentBookingMessagingFromDetail``.
    @MainActor
    @discardableResult
    func presentMessagingThreadForBooking(
        row: ConsumerBookingSimpleRow,
        sessionManager: AppSessionManager,
        presentationStack: BookingMessagingThreadPresentationStack
    ) async -> BookingMessagingThreadHandoff? {
        guard sessionManager.isAuthenticated else { return nil }
        let trimmedBarber = row.barberId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedBarber.isEmpty {
            await reloadInboxSilently(sessionManager: sessionManager)
            if let handoff = buildBookingMessagingHandoffFromInboxIfPossible(bookingRow: row) {
                return applyBookingMessagingThreadPresentation(handoff: handoff, presentationStack: presentationStack, sessionManager: sessionManager)
            }
            return nil
        }

        do {
            let resolved = try await resolveBookingThreadConversation(
                barberProfileId: trimmedBarber,
                bookingRow: row,
                bearerToken: sessionManager.currentSession?.token
            )
            let cid = resolved.conversationId
            let snapshot = row.messagingBookingSnapshot
            let trimmedName = row.barberName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fallbackName: String? = trimmedName.isEmpty ? nil : trimmedName
            let handoff = BookingMessagingThreadHandoff(
                nonce: UUID(),
                conversationId: cid,
                initialDraft: "",
                bookingSnapshot: snapshot,
                counterpartyAvatarURLString: snapshot.barberProfileImageUrl ?? row.barberAvatar,
                counterpartyFallbackName: fallbackName,
                counterpartyMessagingUserId: resolved.otherUserId
            )

            return applyBookingMessagingThreadPresentation(handoff: handoff, presentationStack: presentationStack, sessionManager: sessionManager)
        } catch {
            if MessagingAPIService.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
                return nil
            }
            await reloadInboxSilently(sessionManager: sessionManager)
            if let handoff = buildBookingMessagingHandoffFromInboxIfPossible(bookingRow: row) {
                return applyBookingMessagingThreadPresentation(handoff: handoff, presentationStack: presentationStack, sessionManager: sessionManager)
            }
            return nil
        }
    }

    /// Promotes the thread in the inbox model, then posts ``interaOpenMessagingConversation`` **without** ``pendingPushConversationId`` so the hub behaves like tapping the Messages tab: inbox list only, no auto-push to the conversation (same as the tab selector).
    func requestOpenThreadInMessagesTab(handoff: BookingMessagingThreadHandoff) {
        promoteOrInsertConversationFromHandoff(handoff)
        NotificationCenter.default.post(
            name: .interaOpenMessagingConversation,
            object: nil
        )
    }

    func replaceFromServer(_ dtos: [MessagingConversationRowDTO]) {
        var priorById: [String: PreviewRow] = [:]
        for r in rows {
            priorById[r.id.lowercased()] = r
        }
        let visibleDtos = dtos.filter { !MessagingCommunitySafety.shouldHideConversation(otherUserId: $0.otherUser?.id) }
        let serverKeys = Set(visibleDtos.map { $0.id.lowercased() })
        var next: [PreviewRow] = visibleDtos.map { dto in
            let key = dto.id.lowercased()
            return Self.previewRowByMergingServerDto(dto, prior: priorById[key])
        }
        // If the conversations list briefly omits a thread (read lag, pagination quirks, or eventual consistency),
        // dropping the row makes the hub look “empty” while Socket/thread state still shows an active chat.
        // Keep prior rows the server didn’t return **only** when they already looked like a real thread locally.
        for (key, prior) in priorById where !serverKeys.contains(key) {
            if MessagingCommunitySafety.shouldHideConversation(otherUserId: prior.otherUser?.id) { continue }
            let preview = (prior.lastMessagePreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if prior.otherUser != nil || !preview.isEmpty {
                next.append(prior)
            }
        }
        rows = next
    }

    /// Promote a thread to the top and set the preview (after send or when opening from booking).
    func registerSentMessage(
        conversationId: String,
        previewText: String,
        bookingSnapshot: MessagingBookingDTO?,
        lastMessageSenderId: String? = nil
    ) {
        var existing: PreviewRow?
        if let i = rows.firstIndex(where: { $0.id == conversationId }) {
            existing = rows.remove(at: i)
        }
        var next = existing
            ?? PreviewRow(id: conversationId, booking: bookingSnapshot, lastMessagePreview: nil, updatedAt: nil, unreadCount: nil)
        next.lastMessagePreview = previewText
        if let sid = lastMessageSenderId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty {
            next.lastMessageSenderId = sid
        }
        if next.booking == nil { next.booking = bookingSnapshot }
        rows.insert(next, at: 0)
    }

    func removeConversation(id: String) {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let lowered = key.lowercased()
        rows.removeAll {
            $0.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lowered
        }
        if let hub = hubMessagesThreadPresentation {
            let hid = hub.conversationId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if hid == lowered { clearHubMessagesThreadPresentation() }
        }
        if let fid = hubForegroundConversationId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), fid == lowered {
            hubForegroundConversationId = nil
        }
    }

    /// Seeds the hub Messages inbox row (`ConversationListTimelineRow`) with booking-detail / thread handoff metadata (provider avatar, name).
    func promoteOrInsertConversationFromHandoff(_ handoff: BookingMessagingThreadHandoff) {
        let cid = handoff.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return }
        promoteOrInsertConversation(
            conversationId: cid,
            bookingSnapshot: Self.inboxBookingSnapshotEnriched(
                handoff.bookingSnapshot,
                counterpartyAvatarURLString: handoff.counterpartyAvatarURLString
            )
        )
    }

    func promoteOrInsertConversation(conversationId: String, bookingSnapshot: MessagingBookingDTO?) {
        let key = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if let i = rows.firstIndex(where: { $0.id.caseInsensitiveCompare(key) == .orderedSame }) {
            var r = rows.remove(at: i)
            r.booking = Self.mergedInboxBooking(server: bookingSnapshot, prior: r.booking)
            rows.insert(r, at: 0)
            return
        }
        rows.insert(
            PreviewRow(id: key, booking: bookingSnapshot, lastMessagePreview: nil, otherUser: nil, updatedAt: nil, unreadCount: nil, lastMessageSenderId: nil),
            at: 0
        )
    }

    private static func inboxBookingSnapshotEnriched(
        _ snapshot: MessagingBookingDTO?,
        counterpartyAvatarURLString: String?
    ) -> MessagingBookingDTO? {
        let avatar = counterpartyAvatarURLString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !avatar.isEmpty, let snapshot else { return snapshot }
        if !(snapshot.barberProfileImageUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return snapshot
        }
        return MessagingBookingDTO(
            id: snapshot.id,
            status: snapshot.status,
            serviceName: snapshot.serviceName,
            scheduledTime: snapshot.scheduledTime,
            location: snapshot.location,
            barberId: snapshot.barberId,
            barberName: snapshot.barberName,
            barberBusinessName: snapshot.barberBusinessName,
            barberProfileImageUrl: avatar
        )
    }

    /// Refetches the server unread total for tab/toolbar badges.
    func refreshUnreadMessageCount(sessionManager: AppSessionManager) async {
        guard sessionManager.isAuthenticated else {
            unreadMessageCount = 0
            return
        }
        do {
            unreadMessageCount = try await MessagingAPIService.fetchUnreadMessageCount(bearerToken: sessionManager.currentSession?.token)
        } catch {
            // Keep prior value on transient failures.
        }
    }

    /// Keeps Socket.IO connected while signed in so the inbox updates on receive without pull-to-refresh.
    func ensureRealtimeConnected(bearerToken: String?, userId: String?) {
        guard let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            disconnectRealtime()
            return
        }
        let normalizedUid = Self.normalizedUserId(userId)
        func wireHandlers() {
            socket.onNewMessage = { [weak self] conversationId, dto in
                Task { @MainActor in
                    self?.handleSocketNewMessage(conversationId: conversationId, dto: dto)
                }
            }
            socket.onBookingPaymentRequested = { [weak self] payload in
                Task { @MainActor in
                    guard let self else { return }
                    if self.isPaymentTakeoverDeferred(bookingId: payload.bookingId) { return }
                    self.activePaymentRequest = payload
                }
            }
            socket.onBookingStatusChanged = { [weak self] bookingId, status in
                Task { @MainActor in
                    self?.applyProviderPaymentStateChange(bookingId: bookingId, status: status)
                }
            }
        }

        if connectedBearerToken == token {
            connectedUserId = normalizedUid
            wireHandlers()
            return
        }
        connectedBearerToken = token
        connectedUserId = normalizedUid
        wireHandlers()
        socket.connect(bearerToken: token, personalRoomUserId: userId)
    }

    func disconnectRealtime() {
        connectedBearerToken = nil
        connectedUserId = nil
        hubMessagesThreadPresentation = nil
        deferredPaymentTakeoverBookingIds.removeAll()
        pendingThreadSocketMessages.removeAll()
        inboundSocketMessageTapeByConversation.removeAll()
        socket.disconnect(clearConversationSubscriptions: true)
        socket.onNewMessage = nil
        socket.onBookingPaymentRequested = nil
        socket.onBookingStatusChanged = nil
    }

    func isPaymentTakeoverDeferred(bookingId: String) -> Bool {
        let k = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return false }
        return deferredPaymentTakeoverBookingIds.contains(k)
    }

    /// Dismisses the payment takeover and returns the user to the app shell; they can pay later from **Bookings → booking → Pay**.
    func dismissPaymentTakeoverForLater() {
        guard let bid = activePaymentRequest?.bookingId.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty else {
            activePaymentRequest = nil
            return
        }
        deferredPaymentTakeoverBookingIds.insert(bid)
        activePaymentRequest = nil
    }

    /// Opens the payment takeover from the booking detail (clears any **Pay later** deferral for this booking).
    func presentPaymentTakeover(forBookingRow row: ConsumerBookingSimpleRow) {
        guard let payload = BookingPaymentRequestPayload.from(bookingRow: row) else { return }
        let bid = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bid.isEmpty {
            deferredPaymentTakeoverBookingIds.remove(bid)
        }
        activePaymentRequest = payload
    }

    /// Presents takeover if any booking is `COMPLETED` (awaiting payment). Clears takeover when the booking is `PAID` or no longer awaiting payment.
    func syncPaymentTakeover(withBookings rows: [ConsumerBookingSimpleRow]) {
        for row in rows {
            let s = row.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let bid = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if s == "PAID", !bid.isEmpty {
                deferredPaymentTakeoverBookingIds.remove(bid)
            }
        }
        if let active = activePaymentRequest {
            if let row = rows.first(where: { $0.id == active.bookingId }) {
                let s = row.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if s == "PAID" {
                    activePaymentRequest = nil
                    return
                }
                if s != "COMPLETED" {
                    activePaymentRequest = nil
                }
                return
            }
            // Booking not in this fetch (e.g. filter); keep takeover until socket/refetch updates.
            return
        }
        let pending = rows.filter {
            $0.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) == "COMPLETED"
        }
        .sorted { a, b in
            let da = a.scheduledAtDate ?? .distantPast
            let db = b.scheduledAtDate ?? .distantPast
            if da != db { return da > db }
            return a.id > b.id
        }
        guard let first = pending.first(where: { !isPaymentTakeoverDeferred(bookingId: $0.id) }),
              let payload = BookingPaymentRequestPayload.from(bookingRow: first)
        else {
            return
        }
        activePaymentRequest = payload
    }

    func clearPaymentTakeover() {
        if let bid = activePaymentRequest?.bookingId.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty {
            deferredPaymentTakeoverBookingIds.remove(bid)
        }
        activePaymentRequest = nil
    }

    /// Presents the post-payment review sheet (call after `clearPaymentTakeover()` and a yield).
    func beginPostPaymentReview(from payload: BookingPaymentRequestPayload, barberAvatarURLOverride: String? = nil) {
        postPaymentReviewContext = PostPaymentReviewContext(from: payload, barberAvatarURLOverride: barberAvatarURLOverride)
    }

    /// Navigates consumer Home and clears booking stacks, then dismisses the review sheet.
    /// Uses a non-animated hub move + a short yield before clearing `postPaymentReviewContext` so TabView paging and
    /// `NavigationStack` updates commit before `fullScreenCover` teardown — avoids SwiftUI showing empty / warning chrome.
    func completePostPaymentReviewNavigatingHome() async {
        NotificationCenter.default.post(
            name: .interaNavigateToConsumerHomeAfterPayment,
            object: nil,
            userInfo: [InteraBookingsUserInfoKeys.snapHubNoAnimation: true]
        )
        await Task.yield()
        await Task.yield()
        postPaymentReviewContext = nil
    }

    /// When the provider reverts completion (`undo-complete`) or otherwise leaves **COMPLETED**, dismiss in-app payment UI immediately.
    private func applyProviderPaymentStateChange(bookingId: String, status: String) {
        let s = status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let bid = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        if s != "COMPLETED", !bid.isEmpty {
            deferredPaymentTakeoverBookingIds.remove(bid)
        }
        guard let active = activePaymentRequest, active.bookingId == bookingId else { return }
        if s == "COMPLETED" { return }
        activePaymentRequest = nil
    }

    /// Refetch consumer bookings and dismiss the payment takeover when the booking is paid.
    func refreshConsumerBookingsAndSyncPayment(sessionManager: AppSessionManager) async {
        guard sessionManager.isAuthenticated else { return }
        do {
            let rows = try await ConsumerBookingsSimpleAPI.fetchConsumerBookings(
                bearerToken: sessionManager.currentSession?.token,
                consumerUserId: sessionManager.currentSession?.userId
            )
            await Task.yield()
            syncPaymentTakeover(withBookings: rows)
        } catch {
            if ConsumerBookingsSimpleAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
            }
        }
    }

    /// Register that a conversation thread UI is on-screen (call from ``MessagingConversationView`` `onAppear`).
    func registerMessagingThreadSurface() {
        messagingThreadSurfaceEpoch += 1
    }

    /// While a thread is visible, deliver `new-message` here (shared socket).
    func setThreadMessageHandler(conversationId: String, handler: ((MessagingMessageDTO) -> Void)?) {
        let key = Self.normalizedConversationSocketKey(conversationId)
        if let handler {
            // Only one interactive thread at a time; a new screen must not leave a prior conversation’s handler
            // registered (stale closures / wrong `appendInboundSocketMessage` target).
            threadMessageHandlers.removeAll()
            threadMessageHandlers[key] = handler
            if let batch = pendingThreadSocketMessages.removeValue(forKey: key) {
                for dto in batch {
                    handler(dto)
                }
            }
        } else {
            threadMessageHandlers.removeValue(forKey: key)
            pendingThreadSocketMessages.removeValue(forKey: key)
        }
    }

    private static func normalizedConversationSocketKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    /// Subscribe to a conversation room when a thread view appears.
    func joinThreadConversationRoom(_ conversationId: String) {
        socket.subscribeConversationRoom(conversationId)
    }
    
    /// Unsubscribe from a conversation room when a thread view disappears.
    func leaveThreadConversationRoom(_ conversationId: String) {
        socket.unsubscribeConversationRoom(conversationId)
    }

    /// Leaves every `join-conversation` room except `conversationId` so switching threads does not leave multiple
    /// handlers / rooms competing with the visible ``MessagingConversationView``.
    func leaveThreadConversationRoomsExcept(_ conversationId: String) {
        socket.leaveAllConversationRoomsExcept(conversationId)
    }

    /// After app foreground or transport reconnect, re-emit `join-personal` / `join-conversation` if the socket is up.
    func refreshMessagingRealtimeSubscriptions() {
        socket.reemitSubscribedRoomsIfConnected()
    }

    private func handleSocketNewMessage(conversationId: String, dto: MessagingMessageDTO) {
        let tapeKey = Self.normalizedConversationSocketKey(conversationId)
        var tape = inboundSocketMessageTapeByConversation[tapeKey] ?? []
        tape.append(dto)
        if tape.count > Self.maxInboundSocketTapePerConversation {
            tape.removeFirst(tape.count - Self.maxInboundSocketTapePerConversation)
        }
        inboundSocketMessageTapeByConversation[tapeKey] = tape

        let preview = dto.inboxPreviewLine
        // While a hub thread is on-screen, the inbox list is still in the hierarchy under the push — animating
        // `rows` updates there reads as flicker when the user pops back to Messages.
        if hubForegroundConversationId != nil {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                registerSentMessage(
                    conversationId: conversationId,
                    previewText: preview,
                    bookingSnapshot: nil,
                    lastMessageSenderId: dto.senderId
                )
            }
        } else {
            withAnimation(LiquidGlassMotion.fluidSpring) {
                registerSentMessage(
                    conversationId: conversationId,
                    previewText: preview,
                    bookingSnapshot: nil,
                    lastMessageSenderId: dto.senderId
                )
            }
        }
        let handlerKey = Self.normalizedConversationSocketKey(conversationId)
        if let handler = threadMessageHandlers[handlerKey] {
            handler(dto)
        } else {
            var batch = pendingThreadSocketMessages[handlerKey] ?? []
            batch.append(dto)
            if batch.count > Self.maxPendingSocketMessagesPerConversation {
                batch.removeFirst(batch.count - Self.maxPendingSocketMessagesPerConversation)
            }
            pendingThreadSocketMessages[handlerKey] = batch
        }

        let sender = Self.normalizedUserId(dto.senderId)
        let me = connectedUserId
        if let sender, let me, sender != me {
            Task { await refreshUnreadMessageCountFromConnectedToken() }
        }
    }

    /// Re-applies recent Socket.IO payloads for this conversation into the open thread (``appendInboundSocketMessage`` dedupes by message id).
    func replayInboundSocketTapeIntoThread(conversationId: String, append: (MessagingMessageDTO) -> Void) {
        let key = Self.normalizedConversationSocketKey(conversationId)
        guard let tape = inboundSocketMessageTapeByConversation[key], !tape.isEmpty else { return }
        for dto in tape {
            append(dto)
        }
    }

    private func refreshUnreadMessageCountFromConnectedToken() async {
        guard let token = connectedBearerToken else { return }
        do {
            unreadMessageCount = try await MessagingAPIService.fetchUnreadMessageCount(bearerToken: token)
        } catch {}
    }

    private static func normalizedUserId(_ raw: String?) -> String? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    private static let inboxFingerprintRowSeparator = "\u{001E}"

    /// Includes fields that drive the hub **selector tile** (`ConversationListTimelineRow`) so silent reload
    /// does not skip `replaceFromServer` when the API enriches `otherUser` or barber display without changing id/status/service/time.
    private static func inboxBookingFingerprint(_ booking: MessagingBookingDTO?) -> String {
        guard let booking else { return "" }
        let bid = booking.barberId ?? ""
        let bn = booking.barberName ?? ""
        let bb = booking.barberBusinessName ?? ""
        let img = booking.barberProfileImageUrl ?? ""
        let loc = booking.location ?? ""
        return "\(booking.id ?? "")|\(booking.status ?? "")|\(booking.serviceName ?? "")|\(booking.scheduledTime ?? "")|\(bid)|\(bn)|\(bb)|\(img)|\(loc)"
    }

    private static func inboxOtherUserFingerprint(_ other: MessagingConversationOtherUserDTO?) -> String {
        guard let other else { return "" }
        let id = other.id ?? ""
        let dn = other.displayName ?? ""
        let pic = other.profilePicture ?? ""
        let fn = other.firstName ?? ""
        let ln = other.lastName ?? ""
        return "\(id)|\(dn)|\(pic)|\(fn)|\(ln)"
    }

    private static func inboxFingerprint(from dtos: [MessagingConversationRowDTO]) -> String {
        dtos
            .filter { !MessagingCommunitySafety.shouldHideConversation(otherUserId: $0.otherUser?.id) }
            .map { dto in
                let u = dto.unreadCount.map(String.init) ?? ""
                let s = dto.lastMessageSenderId ?? ""
                let b = inboxBookingFingerprint(dto.booking)
                let o = inboxOtherUserFingerprint(dto.otherUser)
                return "\(dto.id.lowercased())|\(b)|\(o)|\(dto.lastMessagePreview ?? "")|\(u)|\(s)|\(dto.updatedAt ?? "")"
            }
            .joined(separator: inboxFingerprintRowSeparator)
    }

    private static func inboxFingerprint(from rows: [PreviewRow]) -> String {
        rows
            .map { row in
                let u = row.unreadCount.map(String.init) ?? ""
                let s = row.lastMessageSenderId ?? ""
                let b = inboxBookingFingerprint(row.booking)
                let o = inboxOtherUserFingerprint(row.otherUser)
                return "\(row.id.lowercased())|\(b)|\(o)|\(row.lastMessagePreview ?? "")|\(u)|\(s)|\(row.updatedAt ?? "")"
            }
            .joined(separator: inboxFingerprintRowSeparator)
    }

    private static func mergedInboxBookingField(_ server: String?, _ prior: String?) -> String? {
        let ts = (server ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !ts.isEmpty { return ts }
        let tp = (prior ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return tp.isEmpty ? nil : tp
    }

    private static func mergedInboxBooking(server: MessagingBookingDTO?, prior: MessagingBookingDTO?) -> MessagingBookingDTO? {
        guard server != nil || prior != nil else { return nil }
        return MessagingBookingDTO(
            id: mergedInboxBookingField(server?.id, prior?.id),
            status: mergedInboxBookingField(server?.status, prior?.status),
            serviceName: mergedInboxBookingField(server?.serviceName, prior?.serviceName),
            scheduledTime: mergedInboxBookingField(server?.scheduledTime, prior?.scheduledTime),
            location: mergedInboxBookingField(server?.location, prior?.location),
            barberId: mergedInboxBookingField(server?.barberId, prior?.barberId),
            barberName: mergedInboxBookingField(server?.barberName, prior?.barberName),
            barberBusinessName: mergedInboxBookingField(server?.barberBusinessName, prior?.barberBusinessName),
            barberProfileImageUrl: mergedInboxBookingField(server?.barberProfileImageUrl, prior?.barberProfileImageUrl)
        )
    }

    private static func inboxOtherUserRichness(_ u: MessagingConversationOtherUserDTO?) -> Int {
        guard let u else { return 0 }
        var score = 0
        if u.resolvedDisplayName() != nil { score += 3 }
        if let p = u.profilePicture?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty { score += 2 }
        if let id = u.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty { score += 1 }
        return score
    }

    private static func richerInboxOtherUser(
        server: MessagingConversationOtherUserDTO?,
        prior: MessagingConversationOtherUserDTO?
    ) -> MessagingConversationOtherUserDTO? {
        let rs = inboxOtherUserRichness(server)
        let rp = inboxOtherUserRichness(prior)
        if rs >= rp { return server ?? prior }
        return prior ?? server
    }

    private static func previewRowByMergingServerDto(_ dto: MessagingConversationRowDTO, prior: PreviewRow?) -> PreviewRow {
        var row = PreviewRow(dto: dto)
        guard let prior else { return row }
        row.booking = mergedInboxBooking(server: row.booking, prior: prior.booking)
        row.otherUser = richerInboxOtherUser(server: row.otherUser, prior: prior.otherUser)
        let serverPreview = (row.lastMessagePreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if serverPreview.isEmpty {
            let kept = (prior.lastMessagePreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !kept.isEmpty {
                row.lastMessagePreview = prior.lastMessagePreview
                if (row.lastMessageSenderId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    row.lastMessageSenderId = prior.lastMessageSenderId
                }
            }
        }
        if (row.lastMessageSenderId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let p = (prior.lastMessageSenderId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty { row.lastMessageSenderId = prior.lastMessageSenderId }
        }
        return row
    }

    private func fetchConversationDTOsForInbox(sessionManager: AppSessionManager) async throws -> [MessagingConversationRowDTO] {
        if let ids = try? await MessagingAPIService.fetchBlockedMessagingUserIds(bearerToken: sessionManager.currentSession?.token) {
            MessagingCommunitySafety.replaceLocallyBlockedUserIdsFromServer(ids)
        }
        return try await MessagingAPIService.fetchConversations(bearerToken: sessionManager.currentSession?.token)
    }

    /// Shared inbox fetch + apply. Caller controls `replaceFromServer` animation.
    private func fetchAndApplyInboxRows(sessionManager: AppSessionManager, disableImplicitAnimations: Bool) async throws {
        let dtos = try await fetchConversationDTOsForInbox(sessionManager: sessionManager)
        if disableImplicitAnimations {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                replaceFromServer(dtos)
            }
        } else {
            replaceFromServer(dtos)
        }
        ensureRealtimeConnected(bearerToken: sessionManager.currentSession?.token, userId: sessionManager.currentSession?.userId)
        await refreshUnreadMessageCount(sessionManager: sessionManager)
    }

    /// Refreshes the hub inbox model without a loading shell; skips `replaceFromServer` when list content is unchanged (reduces SwiftUI flicker on periodic refresh).
    func reloadInboxSilently(sessionManager: AppSessionManager) async {
        guard sessionManager.isAuthenticated else { return }
        do {
            let dtos = try await fetchConversationDTOsForInbox(sessionManager: sessionManager)
            let visible = dtos.filter { !MessagingCommunitySafety.shouldHideConversation(otherUserId: $0.otherUser?.id) }
            let serverIdSet = Set(visible.map { $0.id.lowercased() })
            let localIdSet = Set(rows.map { $0.id.lowercased() })
            let newFp = Self.inboxFingerprint(from: dtos)
            let oldFp = Self.inboxFingerprint(from: rows)
            // Fingerprint alone can miss structural drift (e.g. id set vs. preview-only rows). Always merge when
            // the visible server id set and local rows disagree so we don’t freeze on a false “empty inbox.”
            if newFp != oldFp || serverIdSet != localIdSet {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    replaceFromServer(dtos)
                }
            }
            ensureRealtimeConnected(bearerToken: sessionManager.currentSession?.token, userId: sessionManager.currentSession?.userId)
            await refreshUnreadMessageCount(sessionManager: sessionManager)
        } catch {
            if InteraRefreshCancellation.isBenignCancellation(error) { return }
            if MessagingAPIService.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
                if rows.isEmpty {
                    listLoadError = "Your session is no longer valid. Please sign in again."
                }
                return
            }
            if rows.isEmpty {
                listLoadError = error.localizedDescription
            }
        }
    }

    /// Explicit inbox refresh (errors always surface in `listLoadError`). Prefer ``reloadInboxSilently`` for hub Messages tab automatic refresh.
    func reloadInbox(sessionManager: AppSessionManager) async {
        guard sessionManager.isAuthenticated else {
            rows = []
            hubMessagesThreadPresentation = nil
            disconnectRealtime()
            unreadMessageCount = 0
            return
        }
        listLoadError = nil
        do {
            try await fetchAndApplyInboxRows(sessionManager: sessionManager, disableImplicitAnimations: false)
        } catch {
            if InteraRefreshCancellation.isBenignCancellation(error) { return }
            if MessagingAPIService.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
                listLoadError = "Your session is no longer valid. Please sign in again."
            } else {
                listLoadError = error.localizedDescription
            }
        }
    }
}
