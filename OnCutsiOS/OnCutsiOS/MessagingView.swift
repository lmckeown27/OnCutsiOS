//
//  MessagingView.swift
//  OnCuts
//
//  Inbox + booking-centric conversation: REST history, read receipts, Socket.IO `new-message`,
//  barber-first pending state, image upload, glass context header, thread delete / barber profile.
//

import Foundation
import SwiftUI
import Combine
import PhotosUI
#if DEBUG
import OSLog
#endif
#if canImport(UIKit)
import UIKit
#endif

#if DEBUG
/// Xcode / Console.app: filter by subsystem **OnCutsMessagingThread** or category **analytics**.
private enum MessagingThreadAnalytics {
    static let log = Logger(subsystem: "OnCutsMessagingThread", category: "analytics")

    static func logRESTLoad(
        conversationId: String,
        currentUserId: String,
        apiMessageCount: Int,
        builtCount: Int,
        blockedIncomingSkipped: Int,
        dedupeSkipped: Int,
        priorSnapshotCount: Int
    ) {
        let me = currentUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let meShort = me.isEmpty ? "∅" : String(me.prefix(8))
        log.info(
            "REST load cid=\(conversationId, privacy: .public) apiRows=\(apiMessageCount) built=\(builtCount) blockedOther=\(blockedIncomingSkipped) deduped=\(dedupeSkipped) priorSnap=\(priorSnapshotCount) mePrefix=\(meShort, privacy: .public)"
        )
    }

    static func logRESTSenderSample(dtos: [MessagingMessageDTO], currentUserId: String, limit: Int = 8) {
        guard !dtos.isEmpty else {
            log.info("REST sender sample: (empty)")
            return
        }
        let me = currentUserId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var parts: [String] = []
        parts.reserveCapacity(min(limit, dtos.count))
        for el in dtos.prefix(limit) {
            let sid = (el.senderId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let mine = !sid.isEmpty && sid.lowercased() == me
            let c = (el.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let head = c.isEmpty ? (el.mediaUrl != nil ? "[media]" : "∅") : String(c.prefix(24))
            parts.append("\(mine ? "out" : "in"):\(String(sid.prefix(8)))…:\(head)")
        }
        log.info("REST sample [\(parts.joined(separator: " | "), privacy: .public)]")
    }

    static func logMergeServer(conversationId: String, appended: Int, incomingOther: Int) {
        log.info("REST merge cid=\(conversationId, privacy: .public) appended=\(appended) incomingFromOther=\(incomingOther)")
    }

    static func logSocket(conversationId: String, reason: String, dto: MessagingMessageDTO) {
        let sid = (dto.senderId ?? "?").prefix(8)
        let mid = (dto.idString ?? "?").prefix(8)
        log.info("Socket cid=\(conversationId, privacy: .public) \(reason, privacy: .public) msg~\(mid, privacy: .public) sender~\(sid, privacy: .public)")
    }
}
#endif

// MARK: - Inbox

struct MessagingView: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator

    @EnvironmentObject private var chatViewModel: ChatViewModel

    @State private var conversations: [MessagingConversationRowDTO] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showMessagingTermsGate = false

    var body: some View {
        ZStack {
            OnCutsLavaLampBackground()

            Group {
                if !sessionManager.isAuthenticated {
                    ContentUnavailableView("Sign in required", systemImage: "message.badge", description: Text("Sign in to see your conversations."))
                } else if isLoading && conversations.isEmpty {
                    ProgressView()
                        .tint(Color.oliveGreen)
                } else if conversations.isEmpty {
                    ContentUnavailableView(
                        "No messages",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("When you book with a service provider, your conversation will show up here.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(conversations) { row in
                                NavigationLink {
                                    MessagingConversationView(
                                        conversationId: row.id,
                                        sessionManager: sessionManager,
                                        coordinator: coordinator,
                                        initialBooking: row.booking,
                                        counterpartyAvatarURLString: row.inboxCounterpartyAvatarURLString,
                                        counterpartyFallbackDisplayName: row.otherUser?.resolvedDisplayName(),
                                        counterpartyUserId: row.otherUser?.id
                                    )
                                } label: {
                                    ConversationInboxThreadCard(
                                        model: MessageThreadDisplayModel(dto: row),
                                        currentUserId: sessionManager.currentSession?.userId ?? ""
                                    )
                                }
                                .buttonStyle(ConversationCardPressStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    #if os(iOS)
                    .scrollContentBackground(.hidden)
                    #endif
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Messages")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .tint(Color.oliveGreen)
        .refreshable { await loadInbox() }
        .task { await loadInbox() }
        .onAppear {
            if sessionManager.isAuthenticated, !MessagingCommunitySafety.hasAcceptedMessagingTerms {
                showMessagingTermsGate = true
            }
        }
        .sheet(isPresented: $showMessagingTermsGate) {
            MessagingUGCTermsGateView(
                onAccept: {
                    MessagingCommunitySafety.setMessagingTermsAccepted()
                    showMessagingTermsGate = false
                }
            )
            #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .messagingBlockedUserDidChange)) { _ in
            Task { await loadInbox() }
        }
        .alert("Couldn’t load conversations", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    @MainActor
    private func loadInbox() async {
        guard sessionManager.isAuthenticated else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            if let ids = try? await MessagingAPIService.fetchBlockedMessagingUserIds(bearerToken: sessionManager.currentSession?.token) {
                MessagingCommunitySafety.replaceLocallyBlockedUserIdsFromServer(ids)
            }
            let rows = try await MessagingAPIService.fetchConversations(bearerToken: sessionManager.currentSession?.token)
            conversations = rows.filter { !MessagingCommunitySafety.shouldHideConversation(otherUserId: $0.otherUser?.id) }
        } catch {
            if !OnCutsRefreshCancellation.isBenignCancellation(error) {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Inbox row (legacy flat layout; hub inbox uses `ConversationInboxThreadCard`)

/// Provider avatar (leading), then **name → last message → occupation/service** (tighter preview width than full row).
/// Typography mirrors `TimelineSectionHeader` (Today / Past) and `BookingTimelineRow.compactLabels` service line.
struct MessagingInboxRowLabel: View {
    let providerTitle: String
    let booking: MessagingBookingDTO?
    let counterpartyAvatarURLString: String?
    let lastMessagePreview: String?
    let lastMessageSenderId: String?
    let currentUserId: String
    /// Hub / list unread badge; also a fallback when `lastMessageSenderId` is missing (older API).
    var unreadCount: Int? = nil

    /// Matches `TimelineSectionHeader` “Today” (`size: 28`, bold, default design) + bookings brand color.
    private static let senderNameFont = OnCutsFont.system(size: 28, weight: .bold, design: .default)
    /// Larger than thread header tile so the row reads **provider-first**; width leaves room for a capped preview chip.
    private static let inboxRowAvatarSize: CGFloat = 128
    private static let inboxRowAvatarCornerRadius: CGFloat = 18
    private static let inboxRowAvatarInitialFont: CGFloat = 44

    /// Occupation · service under the preview (same face as prior trailing line).
    private static let occupationServiceFont = OnCutsFont.system(size: 14, weight: .medium, design: .default)
    private static let occupationServiceKerning: CGFloat = 2.2
    /// Caps preview bubble width so the column sits further **right** of the enlarged avatar.
    private static let messagePreviewMaxWidth: CGFloat = 300
    /// Same face as `BookingTimelineRow` compact service title (`headlineSmall`); line rhythm for multi-line preview.
    private static let previewLineSpacing: CGFloat = 4
    /// Same semantic as `BookingTimelineRow.compactLabels` `displayServiceName` (`.primary` adapts light/dark; light-mode ink aligns with design `neutral700` / #000000).
    private static let previewForeground = Color.primary

    private var rowTerminalDim: Bool {
        booking?.inboxRowIsTerminalPastContinuum == true
    }

    /// Last line is from the counterparty (you received it) vs from you (you sent it).
    private var lastMessageIsFromCounterparty: Bool {
        let me = currentUserId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !me.isEmpty else { return (unreadCount ?? 0) > 0 }
        if let sid = lastMessageSenderId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !sid.isEmpty {
            return sid != me
        }
        return (unreadCount ?? 0) > 0
    }

    private var messagePreviewBoxIsLit: Bool {
        !messageBoxIsPlaceholder && lastMessageIsFromCounterparty
    }

    private var showsIncomingUnreadDot: Bool {
        messagePreviewBoxIsLit && (unreadCount ?? 0) > 0
    }

    private var messageBoxDisplayText: String {
        let p = (lastMessagePreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? "No messages yet" : p
    }

    private var messageBoxIsPlaceholder: Bool {
        (lastMessagePreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var messageBoxForeground: Color {
        if messageBoxIsPlaceholder { return Color.secondary }
        return messagePreviewBoxIsLit ? Self.previewForeground : Color.secondary
    }

    private var messagePreviewBoxFill: Color {
        if messageBoxIsPlaceholder { return Color.primary.opacity(0.04) }
        return messagePreviewBoxIsLit ? Color.oliveGreen.opacity(0.12) : Color.primary.opacity(0.045)
    }

    private var messagePreviewBoxStroke: Color {
        if messageBoxIsPlaceholder { return Color.primary.opacity(0.1) }
        return messagePreviewBoxIsLit ? Color.oliveGreen.opacity(0.32) : Color.primary.opacity(0.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                avatarView
                VStack(alignment: .leading, spacing: 8) {
                    Text(providerTitle)
                        .font(Self.senderNameFont)
                        .foregroundStyleOliveGreen()
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(rowTerminalDim ? 0.72 : 1)

                    if let line = booking?.inboxBookingContextSubtitle, !line.isEmpty {
                        Text(line)
                            .font(OnCutsFont.subheadline(weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .opacity(rowTerminalDim ? 0.72 : 1)
                    }
                    if let loc = booking?.inboxLocationDisplayLine, !loc.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(OnCutsFont.caption(weight: .semibold))
                                .foregroundStyleOnCutsShellIconSecondary()
                                .frame(width: 14, alignment: .leading)
                            Text(loc)
                                .font(OnCutsFont.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Location, \(loc)")
                        .opacity(rowTerminalDim ? 0.72 : 1)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Text(messageBoxDisplayText)
                            .font(OnCutsFont.headlineSmall)
                            .foregroundStyle(messageBoxForeground)
                            .lineSpacing(Self.previewLineSpacing)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if showsIncomingUnreadDot {
                            MessagingInboxIncomingUnreadDot()
                                .padding(.top, 5)
                        }
                    }
                    .frame(maxWidth: Self.messagePreviewMaxWidth, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(messagePreviewBoxFill)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(messagePreviewBoxStroke, lineWidth: 1)
                    }
                    .accessibilityLabel(
                        messageBoxIsPlaceholder
                            ? "No messages yet"
                            : showsIncomingUnreadDot
                                ? "Unread message, \(messageBoxDisplayText)"
                                : "Latest message, \(messageBoxDisplayText)"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 2)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(MessagingProviderRoleLine.occupationAndServicePresentable(booking: booking))
                    .font(Self.occupationServiceFont)
                    .foregroundStyle(.secondary)
                    .kerning(Self.occupationServiceKerning)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                if let sched = booking?.inboxCompactScheduledDisplay, !sched.isEmpty {
                    Spacer(minLength: 8)
                    Text(sched)
                        .font(Self.occupationServiceFont)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(rowTerminalDim ? 0.72 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var avatarView: some View {
        AvatarView(
            imageUrl: counterpartyAvatarURLString,
            name: providerTitle,
            size: Self.inboxRowAvatarSize,
            fontSize: Self.inboxRowAvatarInitialFont,
            clipStyle: .square(cornerRadius: Self.inboxRowAvatarCornerRadius)
        )
    }
}

// MARK: - Conversation view model (socket + uploads mutate published state)

#if canImport(UIKit)
/// Staged attachment in the message composer (not sent until the user taps Send).
struct MessagingComposerDraftImage: Identifiable {
    let id = UUID()
    let uploadData: Data
    let mimeType: String
    let preview: UIImage
}
#endif

@MainActor
final class MessagingConversationViewModel: ObservableObject {
    let conversationId: String
    let sessionManager: AppSessionManager

    @Published var messages: [ChatThreadMessage] = []
    @Published var bookingContext: BookingChatContext?
    @Published var loadError: String?
    @Published var draftText = ""
    /// Bumped when clearing or restoring the composer so multi-line `TextField` remounts (SwiftUI often keeps stale text otherwise).
    @Published var composerRefreshID = UUID()
    @Published var pendingImageThumbs: [UUID: UIImage] = [:]
    #if canImport(UIKit)
    /// Photo chosen from library or camera — previewed in the composer until Send.
    @Published var composerDraftImage: MessagingComposerDraftImage?
    #endif
    @Published private(set) var isSendingComposer = false
    /// Messaging user UUID for the other party (reports / block).
    @Published var counterpartyMessagingUserId: String?
    /// Populated from `GET …/messages/conversations/:id` when the API includes `otherUser` (display + avatar often present while `booking.barber_*` is still empty).
    @Published private(set) var threadOtherUser: MessagingConversationOtherUserDTO?

    /// When set, called with the latest **visible** thread preview line and that message’s `senderId` so the hub inbox row stays in sync.
    var onHubInboxPreviewSync: ((String, String?) -> Void)?
    /// Persists the latest REST thread payload for hub prefetch / instant reopen.
    var onThreadSnapshotCommitted: (([MessagingMessageDTO], MessagingBookingDTO?, MessagingConversationOtherUserDTO?) -> Void)?

    private var didStartSocketSession = false
    /// From inbox `otherUser` / booking row when `booking` lacks provider display strings (keeps nav title off the generic role label).
    private let counterpartyFallbackDisplayName: String?
    /// Handoff snapshot (`ConsumerBookingSimpleRow`, inbox row) — thread GET often omits `booking.scheduledTime`.
    private let seedBookingDTO: MessagingBookingDTO?

    init(
        conversationId: String,
        sessionManager: AppSessionManager,
        initialBooking: MessagingBookingDTO?,
        counterpartyFallbackDisplayName: String? = nil,
        seedCounterpartyMessagingUserId: String? = nil,
        initialDraftText: String? = nil
    ) {
        self.conversationId = conversationId
        self.sessionManager = sessionManager
        seedBookingDTO = initialBooking
        let trimmedFb = counterpartyFallbackDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.counterpartyFallbackDisplayName = trimmedFb.isEmpty ? nil : trimmedFb
        let trimmedOther = seedCounterpartyMessagingUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        counterpartyMessagingUserId = trimmedOther.isEmpty ? nil : trimmedOther
        if let b = initialBooking {
            bookingContext = MessagingDTOMapper.bookingContext(from: b, counterpartyFallbackDisplayName: self.counterpartyFallbackDisplayName)
        }
        if let d = initialDraftText?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            draftText = d
        }
    }

    var currentUserId: String { sessionManager.currentSession?.userId ?? "" }

    private static func normalizedMediaKey(_ url: URL?) -> String? {
        guard let url else { return nil }
        let raw = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.query = nil
            parts.fragment = nil
            return parts.url?.absoluteString ?? raw
        }
        return raw
    }

    /// Inserts or upgrades a thread row without duplicating outgoing image bubbles (local optimistic vs socket/REST echo).
    private func integrateThreadMessage(_ message: ChatThreadMessage, hapticOnInsert: Bool = false) -> Bool {
        if messages.contains(where: { $0.id == message.id }) { return false }
        if let sid = message.serverMessageIdForReport?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sid.isEmpty,
           messages.contains(where: { $0.serverMessageIdForReport == sid }) {
            return false
        }

        if message.isFromCurrentUser, let mediaKey = Self.normalizedMediaKey(message.mediaUrl) {
            if let idx = messages.firstIndex(where: { existing in
                existing.isFromCurrentUser
                    && Self.normalizedMediaKey(existing.mediaUrl) == mediaKey
                    && (existing.serverMessageIdForReport ?? "").isEmpty
            }) {
                messages[idx] = message
                publishHubInboxPreviewFromThread()
                return true
            }
            if messages.contains(where: {
                $0.isFromCurrentUser && Self.normalizedMediaKey($0.mediaUrl) == mediaKey
            }) {
                return false
            }
        }

        if hapticOnInsert {
            MessagingFlowHaptics.sentMessage()
        }
        messages.append(message)
        publishHubInboxPreviewFromThread()
        return true
    }

    var showWaitingForBarber: Bool {
        guard let ctx = bookingContext else { return false }
        return ctx.isPending && messages.isEmpty
    }

    /// Fills `scheduledTimeRaw` from `GET /bookings-simple/:id` when the messaging payload omitted it.
    func hydrateBookingScheduleIfNeeded(bearerToken: String?) async {
        guard let ctx = bookingContext else { return }
        if !ctx.scheduledTimeRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let bookingId = {
            let fromContext = ctx.bookingId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !fromContext.isEmpty { return fromContext }
            return seedBookingDTO?.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }()
        guard !bookingId.isEmpty else { return }
        do {
            let row = try await ConsumerBookingsSimpleAPI.fetchConsumerBookingById(
                bookingId: bookingId,
                bearerToken: bearerToken
            )
            applyBookingScheduleRaw(row.scheduledTime)
        } catch {
            if ConsumerBookingsSimpleAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
            }
        }
    }

    func applyBookingScheduleRaw(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let ctx = bookingContext else { return }
        if !ctx.scheduledTimeRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        bookingContext = BookingChatContext(
            statusNormalized: ctx.statusNormalized,
            serviceName: ctx.serviceName,
            scheduledTimeRaw: trimmed,
            location: ctx.location,
            barberId: ctx.barberId,
            barberName: ctx.barberName,
            barberImageUrl: ctx.barberImageUrl,
            bookingId: ctx.bookingId
        )
    }

    func start() async {
        guard !didStartSocketSession else { return }
        didStartSocketSession = true
        await loadThreadAndMarkRead()
    }

    /// Paints cached REST history before the network round-trip finishes (hub prefetch / prior visit).
    func seedFromCachedSnapshot(
        messages: [MessagingMessageDTO],
        booking: MessagingBookingDTO?,
        otherUser: MessagingConversationOtherUserDTO?
    ) {
        guard !messages.isEmpty || booking != nil || otherUser != nil else { return }
        integrateRESTPayload(
            messages: messages,
            booking: booking,
            otherUser: otherUser,
            mergingPriorSnapshot: self.messages
        )
    }

    func stop() {
        didStartSocketSession = false
    }

    /// Newest committed bubble by `createdAt` (skips pending uploads); ignores sender direction.
    static func latestRenderableMessage(from messages: [ChatThreadMessage]) -> ChatThreadMessage? {
        let candidates = messages.filter { !$0.isPendingUpload }
        guard !candidates.isEmpty else { return nil }
        return candidates.reduce(candidates[0]) { best, next in
            if next.createdAt > best.createdAt { return next }
            if next.createdAt < best.createdAt { return best }
            return next.id > best.id ? next : best
        }
    }

    /// One-line preview for header + hub inbox (text or `📷 Photo`).
    static func latestThreadPreviewLine(from messages: [ChatThreadMessage]) -> String? {
        guard let latest = latestRenderableMessage(from: messages) else { return nil }
        let t = latest.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if latest.mediaUrl != nil { return "📷 Photo" }
        return nil
    }

    #if DEBUG
    /// Incoming rows that would not draw text or media in ``messageBubble`` (display-only signal).
    private static func countIncomingWithNoRenderableBody(_ rows: [ChatThreadMessage]) -> Int {
        rows.filter { msg in
            guard !msg.isFromCurrentUser else { return false }
            let t = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty && msg.mediaUrl == nil && msg.clientUUID == nil
        }.count
    }
    #endif

    private func publishHubInboxPreviewFromThread() {
        guard let sync = onHubInboxPreviewSync else { return }
        guard let latest = Self.latestRenderableMessage(from: messages) else { return }
        guard let line = Self.latestThreadPreviewLine(from: messages) else { return }
        let sid = latest.senderId.trimmingCharacters(in: .whitespacesAndNewlines)
        sync(line, sid.isEmpty ? nil : sid)
    }

    /// Appends a row from the **shared** hub `ChatViewModel` Socket.IO `new-message` handler (single connection).
    func appendInboundSocketMessage(_ dto: MessagingMessageDTO) {
        let m = MessagingDTOMapper.chatMessage(from: dto, index: messages.count, currentUserId: currentUserId)
        if messages.contains(where: { $0.id == m.id }) {
            #if DEBUG
            MessagingThreadAnalytics.logSocket(conversationId: conversationId, reason: "skip_duplicate", dto: dto)
            #endif
            return
        }
        if !m.isFromCurrentUser, MessagingCommunitySafety.isMessagingUserBlocked(m.senderId) {
            #if DEBUG
            MessagingThreadAnalytics.logSocket(conversationId: conversationId, reason: "skip_blocked_sender", dto: dto)
            #endif
            return
        }
        #if DEBUG
        MessagingThreadAnalytics.logSocket(
            conversationId: conversationId,
            reason: m.isFromCurrentUser ? "append_outgoing" : "append_incoming",
            dto: dto
        )
        #endif
        if !m.isFromCurrentUser {
            MessagingFlowHaptics.receivedMessage()
        }
        withAnimation(MessagingFlowMotion.messageAppearSpring) {
            _ = integrateThreadMessage(m)
        }
    }

    private static func preferredCounterpartyFallbackForBookingContext(
        inboxHandoff: String?,
        threadOther: MessagingConversationOtherUserDTO?
    ) -> String? {
        let h = inboxHandoff?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !h.isEmpty { return h }
        return threadOther?.resolvedDisplayName()
    }

    func loadThreadAndMarkRead() async {
        do {
            /// Socket wiring (`wireSharedMessagingRealtimeBridge`) can run from `onAppear` before this await
            /// finishes; inbound rows must not be wiped when REST history lags the inbox / Socket preview.
            let priorSnapshot = messages
            let result = try await MessagingAPIService.fetchConversationMessages(
                conversationId: conversationId,
                bearerToken: sessionManager.currentSession?.token
            )
            integrateRESTPayload(
                messages: result.messages,
                booking: result.booking,
                otherUser: result.otherUser,
                mergingPriorSnapshot: priorSnapshot
            )
            onThreadSnapshotCommitted?(result.messages, result.booking, result.otherUser)
            let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cid.isEmpty {
                Task {
                    try? await MessagingAPIService.markConversationRead(
                        conversationId: cid,
                        bearerToken: sessionManager.currentSession?.token
                    )
                    await MainActor.run {
                        NotificationCenter.default.post(name: .messagingUnreadCountShouldRefresh, object: nil)
                    }
                }
            }
        } catch {
            if !OnCutsRefreshCancellation.isBenignCancellation(error) {
                loadError = error.localizedDescription
            }
        }
    }

    private func integrateRESTPayload(
        messages apiMessages: [MessagingMessageDTO],
        booking: MessagingBookingDTO?,
        otherUser: MessagingConversationOtherUserDTO?,
        mergingPriorSnapshot priorSnapshot: [ChatThreadMessage]
    ) {
        threadOtherUser = otherUser
        let mergedFallback = Self.preferredCounterpartyFallbackForBookingContext(
            inboxHandoff: counterpartyFallbackDisplayName,
            threadOther: otherUser
        )
        if counterpartyMessagingUserId == nil,
           let oid = otherUser?.id?.trimmingCharacters(in: .whitespacesAndNewlines),
           !oid.isEmpty
        {
            counterpartyMessagingUserId = oid
        }
        if let b = booking {
            let fromContext = bookingContext.map { MessagingDTOMapper.bookingDTO(from: $0) }
            let prior = MessagingDTOMapper.mergeBookingDTO(server: fromContext, prior: seedBookingDTO)
                ?? fromContext
                ?? seedBookingDTO
            let merged = MessagingDTOMapper.mergeBookingDTO(server: b, prior: prior) ?? b
            bookingContext = MessagingDTOMapper.bookingContext(
                from: merged,
                counterpartyFallbackDisplayName: mergedFallback,
                existingBookingId: bookingContext?.bookingId
            ) ?? bookingContext
        }
        var seenMessageKeys = Set<String>()
        var built: [ChatThreadMessage] = []
        built.reserveCapacity(apiMessages.count + priorSnapshot.count)
        #if DEBUG
        var blockedIncomingSkipped = 0
        var dedupeSkippedREST = 0
        #endif
        for (idx, el) in apiMessages.enumerated() {
            let m = MessagingDTOMapper.chatMessage(from: el, index: idx, currentUserId: currentUserId)
            if !m.isFromCurrentUser, MessagingCommunitySafety.isMessagingUserBlocked(m.senderId) {
                #if DEBUG
                blockedIncomingSkipped += 1
                #endif
                continue
            }
            var keys: [String] = [m.id]
            if let sid = m.serverMessageIdForReport, !sid.isEmpty { keys.append(sid) }
            if keys.contains(where: { seenMessageKeys.contains($0) }) {
                #if DEBUG
                dedupeSkippedREST += 1
                #endif
                continue
            }
            keys.forEach { seenMessageKeys.insert($0) }
            built.append(m)
        }
        for m in priorSnapshot {
            if !m.isFromCurrentUser, MessagingCommunitySafety.isMessagingUserBlocked(m.senderId) {
                #if DEBUG
                blockedIncomingSkipped += 1
                #endif
                continue
            }
            var keys: [String] = [m.id]
            if let sid = m.serverMessageIdForReport, !sid.isEmpty { keys.append(sid) }
            if keys.contains(where: { seenMessageKeys.contains($0) }) {
                #if DEBUG
                dedupeSkippedREST += 1
                #endif
                continue
            }
            keys.forEach { seenMessageKeys.insert($0) }
            built.append(m)
        }
        built.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
        messages = built
        #if DEBUG
        let mineBuilt = built.filter(\.isFromCurrentUser).count
        let otherBuilt = built.count - mineBuilt
        MessagingThreadAnalytics.logRESTLoad(
            conversationId: conversationId,
            currentUserId: currentUserId,
            apiMessageCount: apiMessages.count,
            builtCount: built.count,
            blockedIncomingSkipped: blockedIncomingSkipped,
            dedupeSkipped: dedupeSkippedREST,
            priorSnapshotCount: priorSnapshot.count
        )
        MessagingThreadAnalytics.logRESTSenderSample(dtos: apiMessages, currentUserId: currentUserId)
        MessagingThreadAnalytics.log.info(
            "REST built direction mine=\(mineBuilt) other=\(otherBuilt) emptyOtherBubble=\(Self.countIncomingWithNoRenderableBody(built))"
        )
        #endif
        publishHubInboxPreviewFromThread()
    }

    /// Lightweight REST sync while the thread is open — covers missed Socket.IO (`transport close`, JWT rebuild, race).
    func mergeNewMessagesFromServer() async {
        guard didStartSocketSession, sessionManager.isAuthenticated else { return }
        do {
            let result = try await MessagingAPIService.fetchConversationMessages(
                conversationId: conversationId,
                bearerToken: sessionManager.currentSession?.token
            )
            var appended: [ChatThreadMessage] = []
            #if DEBUG
            var mergeBlocked = 0
            #endif
            for el in result.messages {
                let m = MessagingDTOMapper.chatMessage(from: el, index: messages.count + appended.count, currentUserId: currentUserId)
                if !m.isFromCurrentUser, MessagingCommunitySafety.isMessagingUserBlocked(m.senderId) {
                    #if DEBUG
                    mergeBlocked += 1
                    #endif
                    continue
                }
                if messages.contains(where: { $0.id == m.id }) { continue }
                if let sid = m.serverMessageIdForReport, !sid.isEmpty,
                   messages.contains(where: { $0.serverMessageIdForReport == sid }) {
                    continue
                }
                if m.isFromCurrentUser,
                   let mediaKey = Self.normalizedMediaKey(m.mediaUrl),
                   messages.contains(where: {
                       $0.isFromCurrentUser && Self.normalizedMediaKey($0.mediaUrl) == mediaKey
                   }) {
                    continue
                }
                appended.append(m)
            }
            #if DEBUG
            if appended.isEmpty {
                MessagingThreadAnalytics.log.info(
                    "REST merge no_new cid=\(self.conversationId, privacy: .public) api=\(result.messages.count) blockedSkips=\(mergeBlocked)"
                )
            }
            #endif
            guard !appended.isEmpty else { return }
            let incomingFromOther = appended.contains { !$0.isFromCurrentUser }
            #if DEBUG
            MessagingThreadAnalytics.logMergeServer(
                conversationId: self.conversationId,
                appended: appended.count,
                incomingOther: appended.filter { !$0.isFromCurrentUser }.count
            )
            if mergeBlocked > 0 {
                MessagingThreadAnalytics.log.info("REST merge cid=\(self.conversationId, privacy: .public) blockedOtherSkipped=\(mergeBlocked)")
            }
            #endif
            if incomingFromOther {
                MessagingFlowHaptics.receivedMessage()
            }
            withAnimation(MessagingFlowMotion.messageAppearSpring) {
                var merged = messages + appended
                merged.sort {
                    if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                    return $0.id < $1.id
                }
                messages = merged
            }
            publishHubInboxPreviewFromThread()
        } catch {
            if OnCutsRefreshCancellation.isBenignCancellation(error) { return }
        }
    }

    func sendText() async {
        await sendComposer()
    }

    var canSendComposer: Bool {
        #if canImport(UIKit)
        if composerDraftImage != nil { return true }
        #endif
        return !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    #if canImport(UIKit)
    func stageComposerPhoto(data: Data, uiImage: UIImage) {
        let prepared = OnCutsChatImagePreparation.dataForChatUpload(image: uiImage, originalData: data)
        composerDraftImage = MessagingComposerDraftImage(
            uploadData: prepared.data,
            mimeType: prepared.mimeType,
            preview: prepared.preview
        )
    }

    func clearComposerDraftImage() {
        composerDraftImage = nil
    }
    #endif

    func sendComposer() async {
        guard !isSendingComposer else { return }
        let caption = draftText.trimmingCharacters(in: .whitespacesAndNewlines)

        #if canImport(UIKit)
        if let draft = composerDraftImage {
            if !caption.isEmpty, OnCutsMessagingContentFilter.textViolatesCommunityRules(caption) {
                loadError = "This message can’t be sent because it may violate our community guidelines."
                return
            }
            isSendingComposer = true
            defer { isSendingComposer = false }
            draftText = ""
            composerRefreshID = UUID()
            composerDraftImage = nil
            await uploadAndSendImage(
                uploadData: draft.uploadData,
                mimeType: draft.mimeType,
                preview: draft.preview,
                caption: caption.isEmpty ? nil : caption
            )
            return
        }
        #endif

        guard !caption.isEmpty else { return }
        if OnCutsMessagingContentFilter.textViolatesCommunityRules(caption) {
            loadError = "This message can’t be sent because it may violate our community guidelines."
            return
        }
        isSendingComposer = true
        defer { isSendingComposer = false }
        draftText = ""
        composerRefreshID = UUID()
        do {
            if let dto = try await MessagingAPIService.sendTextMessage(
                conversationId: conversationId,
                text: caption,
                bearerToken: sessionManager.currentSession?.token
            ) {
                let m = MessagingDTOMapper.chatMessage(from: dto, index: messages.count, currentUserId: currentUserId)
                withAnimation(MessagingFlowMotion.messageAppearSpring) {
                    _ = integrateThreadMessage(m, hapticOnInsert: true)
                }
            }
        } catch {
            if !OnCutsRefreshCancellation.isBenignCancellation(error) {
                loadError = error.localizedDescription
            }
            draftText = caption
            composerRefreshID = UUID()
        }
    }

    #if canImport(UIKit)
    private func uploadAndSendImage(
        uploadData: Data,
        mimeType: String,
        preview: UIImage,
        caption: String?
    ) async {
        let client = UUID()
        let pending = ChatThreadMessage(
            id: "pending-\(client.uuidString)",
            serverMessageIdForReport: nil,
            clientUUID: client,
            senderId: currentUserId,
            isFromCurrentUser: true,
            text: caption ?? "",
            mediaUrl: nil,
            createdAt: Date(),
            uploadProgress: 0.05
        )
        pendingImageThumbs[client] = preview
        withAnimation(MessagingFlowMotion.messageAppearSpring) {
            messages.append(pending)
        }
        do {
            let urlString = try await MessagingAPIService.uploadChatImage(
                imageData: uploadData,
                mimeType: mimeType,
                bearerToken: sessionManager.currentSession?.token
            )
            messages.removeAll { $0.clientUUID == client }
            pendingImageThumbs[client] = nil
            if let dto = try await MessagingAPIService.sendImageMessage(
                conversationId: conversationId,
                mediaUrl: urlString,
                caption: caption,
                bearerToken: sessionManager.currentSession?.token
            ) {
                let m = MessagingDTOMapper.chatMessage(from: dto, index: messages.count, currentUserId: currentUserId)
                withAnimation(MessagingFlowMotion.messageAppearSpring) {
                    _ = integrateThreadMessage(m, hapticOnInsert: true)
                }
            } else {
                await mergeNewMessagesFromServer()
            }
        } catch {
            messages.removeAll { $0.clientUUID == client }
            pendingImageThumbs[client] = nil
            if !OnCutsRefreshCancellation.isBenignCancellation(error) {
                loadError = error.localizedDescription
            }
            composerDraftImage = MessagingComposerDraftImage(
                uploadData: uploadData,
                mimeType: mimeType,
                preview: preview
            )
            if let caption, !caption.isEmpty {
                draftText = caption
                composerRefreshID = UUID()
            }
            publishHubInboxPreviewFromThread()
        }
    }
    #endif

    func deleteThread(onSuccess: @escaping () -> Void) async {
        do {
            try await MessagingAPIService.deleteConversation(conversationId: conversationId, bearerToken: sessionManager.currentSession?.token)
            onSuccess()
        } catch {
            if !OnCutsRefreshCancellation.isBenignCancellation(error) {
                loadError = error.localizedDescription
            }
        }
    }

    func submitContentReport(reason: String, details: String?, messageServerId: String?) async throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { return }
        let reported = counterpartyMessagingUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !reported.isEmpty else {
            throw NSError(domain: "OnCutsMessaging", code: 10, userInfo: [NSLocalizedDescriptionKey: "Could not determine who to report. Try again after the thread finishes loading."])
        }
        try await MessagingAPIService.reportConversationContent(
            conversationId: conversationId,
            reason: trimmedReason,
            details: details,
            messageId: messageServerId,
            reportedUserId: reported,
            bearerToken: sessionManager.currentSession?.token
        )
    }

    func blockCounterpartyAndNotify() async throws {
        let blocked = counterpartyMessagingUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !blocked.isEmpty else {
            throw NSError(domain: "OnCutsMessaging", code: 11, userInfo: [NSLocalizedDescriptionKey: "Could not determine who to block. Try again after the thread finishes loading."])
        }
        try await MessagingAPIService.blockMessagingUser(blockedUserId: blocked, bearerToken: sessionManager.currentSession?.token)
        MessagingCommunitySafety.addLocallyBlockedUserId(blocked)
        // Guideline 1.2: notify the developer/moderation pipeline when a user blocks someone (in addition to the block record).
        try? await MessagingAPIService.reportConversationContent(
            conversationId: conversationId,
            reason: "user_blocked_moderation_notice",
            details: "Automatic notice: the reporter blocked this messaging user. Review if further action is needed.",
            messageId: nil,
            reportedUserId: blocked,
            bearerToken: sessionManager.currentSession?.token
        )
    }

    /// Cancels an active booking (`DELETE /bookings-simple/:id`), then removes the thread (`DELETE …/conversations/:id`) when the server still keeps it—`404` is treated as already removed.
    func cancelActiveBooking(onSuccess: @escaping () -> Void) async {
        guard let raw = bookingContext?.bookingId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            loadError = "Missing booking information."
            return
        }
        do {
            try await MessagingAPIService.cancelBookingSimple(bookingId: raw, bearerToken: sessionManager.currentSession?.token)
            do {
                try await MessagingAPIService.deleteConversation(conversationId: conversationId, bearerToken: sessionManager.currentSession?.token)
            } catch {
                if OnCutsRefreshCancellation.isBenignCancellation(error) { /* no-op */ }
                else {
                    let ns = error as NSError
                    let alreadyGone = ns.domain == "MessagingAPI" && ns.code == 404
                    if !alreadyGone {
                        loadError = error.localizedDescription
                    }
                }
            }
            onSuccess()
        } catch {
            if !OnCutsRefreshCancellation.isBenignCancellation(error) {
                loadError = error.localizedDescription
            }
        }
    }

    func clearLoadError() {
        loadError = nil
    }
}

private extension Data {
    var isProbablyPNG: Bool {
        let sig = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        return count >= sig.count && starts(with: sig)
    }
}

// MARK: - Conversation

struct MessagingConversationView: View {
    let conversationId: String
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    var initialBooking: MessagingBookingDTO?
    /// Prefer `MessagingConversationRowDTO.inboxCounterpartyAvatarURLString` when pushing from the inbox so the thread shows the same photo as the list (booking `barber_profile_image_url` or `otherUser.profilePicture`).
    var counterpartyAvatarURLString: String?
    /// Legacy: only used if the conversation is embedded in a custom container (e.g. experiments); hub `NavigationLink` uses `dismiss()`.
    var onRequestPopFromParent: (() -> Void)?
    /// Hub / stack: notify when this view is the active navigation destination (drives tab paging lock), same idea as booking detail push/pop. Second parameter is always this view’s ``conversationId``.
    var onNavigationVisibilityChanged: ((Bool, String) -> Void)?
    /// Called after the first successful `loadThreadAndMarkRead` from booking flows (e.g. inbox list sync) — not used for every embed.
    var onInitialThreadHydrationComplete: (() -> Void)?
    /// Refreshes the shared hub ``ChatViewModel`` inbox **without** loading chrome while this thread is open so returning to Messages stays stable.
    var onResyncSharedHubInboxSilently: (() async -> Void)?
    /// Other participant’s messaging user id when known (inbox / booking handoff). Thread load fills this when omitted.
    var counterpartyUserId: String?
    /// Rebook gating on pushed `ConsumerBookingDetailView` (matches Bookings / Home detail).
    var hasActiveConsumerBooking: Bool = false
    var onShowLogin: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var chatViewModel: ChatViewModel

    @StateObject private var vm: MessagingConversationViewModel
    private let counterpartyFallbackDisplayName: String?
    @State private var showCancelBookingConfirm = false
    @State private var showDeleteConversationConfirm = false
    @State private var showBookingDetails = false
    /// Interactive drag when the trailing booking panel is open (swipe right to dismiss).
    @State private var bookingDetailsPanelDragOffset: CGFloat = 0
    /// Pull distance (0…panel width) when dragging the panel in from the **right edge** before it is committed open — tab-like, follows the finger.
    @State private var bookingDetailsEdgePull: CGFloat = 0
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCameraCapture = false
    @State private var showCameraUnavailableAlert = false
    @State private var showBlockUserConfirm = false
    @State private var showReportMessageDialog = false
    @State private var messagePendingReport: ChatThreadMessage?
    @State private var moderationBanner: String?
    /// Guideline 1.2: terms must be accepted before any thread loads (covers deep links / Home handoff, not only the Messages tab).
    @State private var showThreadMessagingTermsGate = false
    /// Cancelled on disappear so a deferred hub inbox resync never runs during the pop transition.
    @State private var hubInboxResyncTasks: [Task<Void, Never>] = []
    @State private var deferredRealtimeTeardownTask: Task<Void, Never>?
    @State private var pushedBookingDetailRoute: MessagingThreadPushedBookingDetail?
    @State private var isOpeningBookingDetailFromDrawer = false
    @State private var bookingDetailOpenError: String?
    /// Suppresses bubble insert transitions and animated scroll until the navigation push settles.
    @State private var allowsThreadContentMotion = false
    @State private var threadContentMotionTask: Task<Void, Never>?
    @FocusState private var isMessageComposerFocused: Bool
    @State private var conversationPopDragOffset: CGFloat = 0

    /// Snap / cancel physics aligned with hub tab paging (not a single-flick commit).
    private static let edgeGestureSnapSpring = Animation.spring(response: 0.33, dampingFraction: 0.86, blendDuration: 0.12)
    private static let deferredRealtimeTeardownNanoseconds: UInt64 = 400_000_000

    init(
        conversationId: String,
        sessionManager: AppSessionManager,
        coordinator: MainCoordinator,
        initialBooking: MessagingBookingDTO?,
        counterpartyAvatarURLString: String? = nil,
        counterpartyFallbackDisplayName: String? = nil,
        initialDraftText: String? = nil,
        onRequestPopFromParent: (() -> Void)? = nil,
        onNavigationVisibilityChanged: ((Bool, String) -> Void)? = nil,
        onInitialThreadHydrationComplete: (() -> Void)? = nil,
        onResyncSharedHubInboxSilently: (() async -> Void)? = nil,
        counterpartyUserId: String? = nil,
        hasActiveConsumerBooking: Bool = false,
        onShowLogin: (() -> Void)? = nil
    ) {
        self.conversationId = conversationId
        self.sessionManager = sessionManager
        self.coordinator = coordinator
        self.initialBooking = initialBooking
        self.counterpartyAvatarURLString = counterpartyAvatarURLString
        self.onRequestPopFromParent = onRequestPopFromParent
        self.onNavigationVisibilityChanged = onNavigationVisibilityChanged
        self.onInitialThreadHydrationComplete = onInitialThreadHydrationComplete
        self.onResyncSharedHubInboxSilently = onResyncSharedHubInboxSilently
        self.hasActiveConsumerBooking = hasActiveConsumerBooking
        self.onShowLogin = onShowLogin
        let trimmedCp = counterpartyUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.counterpartyUserId = trimmedCp.isEmpty ? nil : trimmedCp
        let trimmedFallback = counterpartyFallbackDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = (trimmedFallback?.isEmpty == false) ? trimmedFallback : nil
        self.counterpartyFallbackDisplayName = fallback
        _vm = StateObject(
            wrappedValue: MessagingConversationViewModel(
                conversationId: conversationId,
                sessionManager: sessionManager,
                initialBooking: initialBooking,
                counterpartyFallbackDisplayName: fallback,
                seedCounterpartyMessagingUserId: trimmedCp.isEmpty ? nil : trimmedCp,
                initialDraftText: initialDraftText
            )
        )
    }

    private func leaveConversation() {
        if let onRequestPopFromParent {
            onRequestPopFromParent()
        } else {
            dismiss()
        }
    }

    private func dismissMessageComposerKeyboard() {
        isMessageComposerFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    /// Keeps `ConversationListTimelineRow` avatars in sync after booking-detail threads hydrate provider photos from REST.
    @MainActor
    private func syncHubInboxPreviewFromThreadContext() {
        let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return }
        let uid = (counterpartyUserId ?? vm.counterpartyMessagingUserId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let handoff = ChatViewModel.BookingMessagingThreadHandoff(
            nonce: UUID(),
            conversationId: cid,
            initialDraft: "",
            bookingSnapshot: threadHeaderBookingSnapshot,
            counterpartyAvatarURLString: threadCounterpartyAvatarURL,
            counterpartyFallbackName: threadCounterpartyDisplayName,
            counterpartyMessagingUserId: uid?.isEmpty == false ? uid : nil
        )
        chatViewModel.promoteOrInsertConversationFromHandoff(handoff)
    }

    @MainActor
    private func startThreadAfterTermsIfNeeded() async {
        guard sessionManager.isAuthenticated else { return }
        guard MessagingCommunitySafety.hasAcceptedMessagingTerms else { return }
        let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        vm.onHubInboxPreviewSync = { line, senderId in
            guard !cid.isEmpty else { return }
            chatViewModel.registerSentMessage(conversationId: cid, previewText: line, bookingSnapshot: nil, lastMessageSenderId: senderId)
        }
        vm.onThreadSnapshotCommitted = { apiMessages, booking, otherUser in
            chatViewModel.recordThreadSnapshot(
                conversationId: cid,
                messages: apiMessages,
                booking: booking,
                otherUser: otherUser
            )
        }
        wireSharedMessagingRealtimeBridge()
        await chatViewModel.awaitThreadPrefetchIfNeeded(conversationId: cid)
        if let cached = chatViewModel.cachedThreadSnapshot(conversationId: cid) {
            vm.seedFromCachedSnapshot(
                messages: cached.messages,
                booking: cached.booking,
                otherUser: cached.otherUser
            )
        }
        await vm.start()
        await vm.hydrateBookingScheduleIfNeeded(bearerToken: sessionManager.currentSession?.token)
        syncHubInboxPreviewFromThreadContext()
        onInitialThreadHydrationComplete?()
        if let resync = onResyncSharedHubInboxSilently {
            hubInboxResyncTasks.forEach { $0.cancel() }
            hubInboxResyncTasks.removeAll()
            hubInboxResyncTasks.append(Task { await resync() })
            hubInboxResyncTasks.append(Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                await resync()
            })
        }
    }

    /// One Socket.IO client per signed-in user (`ChatViewModel`); join the open thread and forward `new-message` here.
    private func wireSharedMessagingRealtimeBridge() {
        let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return }
        chatViewModel.ensureRealtimeConnected(
            bearerToken: sessionManager.currentSession?.token,
            userId: sessionManager.currentSession?.userId
        )
        chatViewModel.leaveThreadConversationRoomsExcept(cid)
        chatViewModel.joinThreadConversationRoom(cid)
        chatViewModel.setThreadMessageHandler(conversationId: cid, handler: { dto in
            vm.appendInboundSocketMessage(dto)
        })
        chatViewModel.refreshMessagingRealtimeSubscriptions()
        // Same Socket.IO payloads that update the hub inbox preview (`registerSentMessage`); replay ensures
        // bubbles match the list when GET history lags or the handler was not wired yet.
        chatViewModel.replayInboundSocketTapeIntoThread(conversationId: cid) { dto in
            vm.appendInboundSocketMessage(dto)
        }
    }

    private func unwireSharedMessagingRealtimeBridge() {
        let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return }
        vm.onHubInboxPreviewSync = nil
        chatViewModel.setThreadMessageHandler(conversationId: cid, handler: nil)
        chatViewModel.leaveThreadConversationRoom(cid)
    }

    /// `onDisappear` alone is unreliable for navigation destinations; only tear down the shared socket subscription after a short quiet window, unless another thread surface registered (``ChatViewModel/messagingThreadSurfaceEpoch``).
    private func scheduleDeferredRealtimeTeardown(surfaceEpochAtDisappear: UInt64) {
        deferredRealtimeTeardownTask?.cancel()
        deferredRealtimeTeardownTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.deferredRealtimeTeardownNanoseconds)
            guard !Task.isCancelled else { return }
            guard surfaceEpochAtDisappear == chatViewModel.messagingThreadSurfaceEpoch else { return }
            #if canImport(UIKit)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
            unwireSharedMessagingRealtimeBridge()
            syncHubInboxPreviewFromThreadContext()
            onNavigationVisibilityChanged?(false, conversationId)
            hubInboxResyncTasks.forEach { $0.cancel() }
            hubInboxResyncTasks.removeAll()
            vm.stop()
        }
    }

    private static let messagingThreadBottomID = "messagingThreadBottom"

    var body: some View {
        messagingConversationChrome
    }

    /// Split from `body` so the Swift compiler can type-check the navigation stack in reasonable time.
    @ViewBuilder
    private var messagingConversationChrome: some View {
        messagingConversationWithNavigationAppearance
            .alert("Are you sure?", isPresented: $showCancelBookingConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Cancel booking", role: .destructive) {
                    Task {
                        await vm.cancelActiveBooking {
                            let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !cid.isEmpty {
                                chatViewModel.removeConversation(id: cid)
                            }
                            leaveConversation()
                            Task { await chatViewModel.reloadInboxSilently(sessionManager: sessionManager) }
                        }
                    }
                }
            } message: {
                Text("This will cancel your booking and remove this chat. This can’t be undone.")
            }
            .alert("Are you sure?", isPresented: $showDeleteConversationConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await vm.deleteThread {
                            let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !cid.isEmpty {
                                chatViewModel.removeConversation(id: cid)
                            }
                            leaveConversation()
                            Task { await chatViewModel.reloadInboxSilently(sessionManager: sessionManager) }
                        }
                    }
                }
            } message: {
                Text("This conversation will be permanently deleted.")
            }
            .alert("Couldn’t open booking", isPresented: Binding(
                get: { bookingDetailOpenError != nil },
                set: { if !$0 { bookingDetailOpenError = nil } }
            )) {
                Button("OK") { bookingDetailOpenError = nil }
            } message: {
                Text(bookingDetailOpenError ?? "")
            }
            .task(id: conversationId) {
                if sessionManager.isAuthenticated, !MessagingCommunitySafety.hasAcceptedMessagingTerms {
                    showThreadMessagingTermsGate = true
                    return
                }
                await startThreadAfterTermsIfNeeded()
            }
            /// REST backstop when Socket.IO drops or room joins lag behind server emits.
            .task(id: "\(conversationId)-thread-sync") {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                while !Task.isCancelled {
                    await vm.mergeNewMessagesFromServer()
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, sessionManager.isAuthenticated else { return }
                let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cid.isEmpty else { return }
                chatViewModel.ensureRealtimeConnected(
                    bearerToken: sessionManager.currentSession?.token,
                    userId: sessionManager.currentSession?.userId
                )
                chatViewModel.joinThreadConversationRoom(cid)
                chatViewModel.refreshMessagingRealtimeSubscriptions()
                if MessagingCommunitySafety.hasAcceptedMessagingTerms {
                    wireSharedMessagingRealtimeBridge()
                }
                Task { await vm.mergeNewMessagesFromServer() }
            }
            .onDisappear {
                let snapshot = chatViewModel.messagingThreadSurfaceEpoch
                scheduleDeferredRealtimeTeardown(surfaceEpochAtDisappear: snapshot)
            }
            .sheet(isPresented: $showThreadMessagingTermsGate) {
                MessagingUGCTermsGateView(
                    onAccept: {
                        MessagingCommunitySafety.setMessagingTermsAccepted()
                        showThreadMessagingTermsGate = false
                        Task {
                            await startThreadAfterTermsIfNeeded()
                        }
                    }
                )
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
            }
            .alert("Error", isPresented: Binding(
                get: { vm.loadError != nil },
                set: { if !$0 { vm.clearLoadError() } }
            )) {
                Button("OK") { vm.clearLoadError() }
            } message: {
                Text(vm.loadError ?? "")
            }
            .confirmationDialog(
                messagePendingReport == nil ? "Report this conversation" : "Report this message",
                isPresented: $showReportMessageDialog,
                titleVisibility: .visible
            ) {
                Button("Harassment or hate") { Task { await submitModerationReport(reason: "harassment_or_hate") } }
                Button("Threats or violence") { Task { await submitModerationReport(reason: "threats_or_violence") } }
                Button("Spam or scam") { Task { await submitModerationReport(reason: "spam_or_scam") } }
                Button("Nudity or sexual content") { Task { await submitModerationReport(reason: "sexual_content") } }
                Button("Cancel", role: .cancel) {
                    messagePendingReport = nil
                }
            } message: {
                Text("Our team reviews reports within 24 hours and may remove content or restrict accounts that break our Terms of Service.")
            }
            .alert("Block this user?", isPresented: $showBlockUserConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Block", role: .destructive) {
                    Task { await performBlockUser() }
                }
            } message: {
                Text("You won’t see threads with this person. We’re notified so we can review within 24 hours.")
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showCameraCapture) {
                #if canImport(UIKit)
                CameraImagePicker(isPresented: $showCameraCapture) { image in
                    Task { @MainActor in
                        let data = image.jpegData(compressionQuality: 0.88) ?? (image.pngData() ?? Data())
                        vm.stageComposerPhoto(data: data, uiImage: image)
                    }
                }
                .ignoresSafeArea()
                #endif
            }
            .alert("Camera unavailable", isPresented: $showCameraUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cameraUnavailableAlertMessage)
            }
            .overlay {
                ConversationBookingPanelEdgeOverlay(
                    bookingDetailsEdgePull: $bookingDetailsEdgePull,
                    showBookingDetails: showBookingDetails,
                    hasBookingContext: vm.bookingContext != nil,
                    onBookingPanelCommitted: {
                        bookingDetailsEdgePull = 0
                        withAnimation(MessagingFlowMotion.messageAppearSpring) {
                            showBookingDetails = true
                        }
                    }
                )
                .allowsHitTesting(true)
            }
            #endif
    }

    @ViewBuilder
    private var messagingConversationWithNavigationAppearance: some View {
        messagingConversationBaseLayers
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(iOS)
            .onCutsNavigationShellBackgroundClear()
            #endif
            .onChange(of: showBookingDetails) { _, open in
                if open {
                    Task {
                        await vm.hydrateBookingScheduleIfNeeded(
                            bearerToken: sessionManager.currentSession?.token
                        )
                    }
                } else {
                    bookingDetailsPanelDragOffset = 0
                }
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .navigationBar)
            .onCutsEnableNavigationSwipeBack()
            .background {
                ConversationSwipeBackPanEnabler(
                    dragOffset: $conversationPopDragOffset,
                    isEnabled: conversationSwipeToDismissEnabled,
                    onDismiss: { leaveConversation() }
                )
            }
            #endif
            .tint(Color.oliveGreen)
            .onAppear {
                threadContentMotionTask?.cancel()
                allowsThreadContentMotion = false
                threadContentMotionTask = Task { @MainActor in
                    try? await Task.sleep(for: MessagingFlowMotion.threadOpenMotionDelay)
                    guard !Task.isCancelled else { return }
                    allowsThreadContentMotion = true
                }
                // Defer off the navigation appearance transaction; mutating `ChatViewModel` / parent bindings
                // synchronously in `onAppear` causes "Modifying state during view update" and can strand `navigationDestination`.
                Task { @MainActor in
                    chatViewModel.registerMessagingThreadSurface()
                    deferredRealtimeTeardownTask?.cancel()
                    deferredRealtimeTeardownTask = nil
                    onNavigationVisibilityChanged?(true, conversationId)
                    // Do not call `wireSharedMessagingRealtimeBridge()` here: it can run while `.task` is still
                    // awaiting `loadThreadAndMarkRead()`, letting Socket append rows that the REST assign then wipes.
                    // Realtime is wired after the first successful load in `startThreadAfterTermsIfNeeded()`.
                }
            }
            .onDisappear {
                threadContentMotionTask?.cancel()
                threadContentMotionTask = nil
                allowsThreadContentMotion = false
            }
            .navigationDestination(item: $pushedBookingDetailRoute) { presentation in
                ConsumerBookingDetailView(
                    row: presentation.row,
                    sessionManager: sessionManager,
                    coordinator: coordinator,
                    bookingDetailPresentationID: presentation.id,
                    hasActiveConsumerBooking: hasActiveConsumerBooking,
                    onShowLogin: { onShowLogin?() }
                )
                .id(presentation.id)
                #if os(iOS)
                .onCutsNavigationShellBackgroundClear()
                #endif
            }
    }

    @ViewBuilder
    private var messagingConversationBaseLayers: some View {
        ZStack {
            ZStack {
                Color.clear
                messagingConversationMainColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: conversationPopDragOffset)

            if showBookingDetails || bookingDetailsEdgePull > 0 {
                bookingDetailsTrailingDrawerOverlay
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conversationSwipeToDismissEnabled: Bool {
        !showBookingDetails && bookingDetailsEdgePull <= 0
    }

    @ViewBuilder
    private var messagingConversationMainColumn: some View {
        VStack(spacing: 0) {
            instagramStickyHeader
            if let moderationBanner, !moderationBanner.isEmpty {
                Text(moderationBanner)
                    .font(OnCutsFont.caption(weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.oliveGreen.opacity(0.35))
                    .simultaneousGesture(TapGesture().onEnded { dismissMessageComposerKeyboard() })
            }
            messagingThreadScrollRegion()
            messagingConversationComposerRow
        }
    }

    @ViewBuilder
    private var messagingConversationComposerRow: some View {
        if vm.showWaitingForBarber {
            waitingForBarberChrome
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        } else {
            composerChrome
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func messagingThreadScrollRegion() -> some View {
        ScrollViewReader { proxy in
            GeometryReader { geo in
                messagingThreadScrollContent(proxy: proxy, scrollViewportHeight: geo.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func messagingThreadScrollContent(proxy: ScrollViewProxy, scrollViewportHeight: CGFloat) -> some View {
        Group {
            if #available(iOS 17.0, *) {
                ScrollView {
                    messagesTimelineStack(minHeight: scrollViewportHeight)
                }
                #if os(iOS)
                .scrollContentBackground(.hidden)
                #endif
                .defaultScrollAnchor(.top)
            } else {
                ScrollView {
                    messagesTimelineStack(minHeight: scrollViewportHeight)
                }
                #if os(iOS)
                .scrollContentBackground(.hidden)
                #endif
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .simultaneousGesture(TapGesture().onEnded { dismissMessageComposerKeyboard() })
        .onChange(of: vm.messages.last?.id) { oldLastId, _ in
            guard !vm.messages.isEmpty, oldLastId != nil else { return }
            scrollThreadToBottom(proxy: proxy, animated: allowsThreadContentMotion)
        }
    }

    #if os(iOS)
    private func bookingDetailsPanelDismissDragGesture(panelWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard showBookingDetails else { return }
                let w = value.translation.width
                let h = value.translation.height
                guard w > 0, w > abs(h) * 0.55 else { return }
                bookingDetailsPanelDragOffset = min(w, panelWidth * 1.15)
            }
            .onEnded { value in
                let w = value.translation.width
                let threshold = max(72, panelWidth * 0.22)
                if w > threshold {
                    withAnimation(MessagingFlowMotion.messageAppearSpring) {
                        showBookingDetails = false
                    }
                }
                withAnimation(Self.edgeGestureSnapSpring) {
                    bookingDetailsPanelDragOffset = 0
                }
            }
    }
    #endif

    /// Scrolls so the newest bubble is visible. We still defer a few frames so `ScrollViewReader` can resolve
    /// the bottom id after `VStack` layout (covers send, socket receive, and photo upload completion).
    private func scrollThreadToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        func scroll() {
            let targetId = MessagingConversationViewModel.latestRenderableMessage(from: vm.messages)?.id
                ?? Self.messagingThreadBottomID
            if animated {
                withAnimation(MessagingFlowMotion.messageAppearSpring) {
                    proxy.scrollTo(targetId, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(targetId, anchor: .bottom)
            }
        }
        DispatchQueue.main.async {
            scroll()
        }
    }

    /// Booking/thread API first, then initial booking blob, then inbox list merge (uploaded barber photo or `otherUser` avatar).
    private var threadCounterpartyAvatarURL: String? {
        func trimmed(_ raw: String?) -> String? {
            let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        if let u = trimmed(vm.bookingContext?.barberImageUrl) { return u }
        if let u = trimmed(initialBooking?.barberProfileImageUrl) { return u }
        if let u = trimmed(vm.threadOtherUser?.profilePicture) { return u }
        return trimmed(counterpartyAvatarURLString)
    }

    private var threadCounterpartyDisplayName: String {
        let ctx = (vm.bookingContext?.barberName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !ctx.isEmpty, ctx.caseInsensitiveCompare("Chat") != .orderedSame {
            return ctx
        }
        if let b = initialBooking {
            if let n = b.inboxProviderNameIfKnown { return n }
            let bn = (b.barberName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !bn.isEmpty { return bn }
        }
        if let n = vm.threadOtherUser?.resolvedDisplayName() { return n }
        if let fb = counterpartyFallbackDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !fb.isEmpty {
            return fb
        }
        return "Conversation"
    }

    /// Provider name in the compact sticky bar (same row as back chevron + avatar).
    private static let stickyHeaderNameFont = OnCutsFont.system(size: 17, weight: .bold, design: .default)
    /// Status + service lines beside the avatar.
    private static let stickyHeaderMetaFont = OnCutsFont.system(size: 12, weight: .medium, design: .default)
    private static let stickyHeaderMetaKerning: CGFloat = 1.2
    private static let stickyHeaderAvatarSize: CGFloat = 44
    private static let stickyHeaderAvatarCornerRadius: CGFloat = 10
    private static let stickyHeaderAvatarInitialFont: CGFloat = 18

    /// Booking status for sticky header + details drawer (never raw API enums like `PENDING`).
    private var headerBookingStatusPresentable: String {
        guard let ctx = vm.bookingContext else { return "" }
        let raw = ctx.statusNormalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "Active" }
        return MessagingBookingDTO.inboxPrettyBookingStatus(raw)
    }

    /// Booking blob for chrome that mirrors the hub inbox row (`ConversationListTimelineRow`): prefer handoff, then hydrated API context.
    private var threadHeaderBookingSnapshot: MessagingBookingDTO? {
        if let b = initialBooking { return b }
        if let ctx = vm.bookingContext { return MessagingDTOMapper.bookingDTO(from: ctx) }
        return nil
    }

    private var threadHeaderRoleServiceLine: String {
        MessagingProviderRoleLine.occupationAndServicePresentable(booking: threadHeaderBookingSnapshot)
    }

    /// Align dimming with `ConversationListTimelineRow.shouldDimTextColumn` (terminal booking lane).
    private var threadHeaderDimTextColumn: Bool {
        threadHeaderBookingSnapshot?.inboxRowIsTerminalPastContinuum == true
    }

    private var resolvedThreadScheduledTimeRaw: String {
        func nonEmpty(_ raw: String?) -> String? {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        if let raw = nonEmpty(vm.bookingContext?.scheduledTimeRaw) { return raw }
        if let raw = nonEmpty(initialBooking?.scheduledTime) { return raw }
        if let raw = nonEmpty(threadHeaderBookingSnapshot?.scheduledTime) { return raw }
        return ""
    }

    private var formattedContextHeaderScheduledTime: String {
        let raw = resolvedThreadScheduledTimeRaw
        guard !raw.isEmpty else { return "Time TBD" }
        return BookingPacificSchedule.formattedDisplayScheduledTime(raw, fullMonthName: true)
    }

    private var resolvedThreadBookingId: String? {
        func trimmed(_ raw: String?) -> String? {
            let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        if let id = trimmed(vm.bookingContext?.bookingId) { return id }
        if let id = trimmed(initialBooking?.id) { return id }
        if let id = trimmed(threadHeaderBookingSnapshot?.id) { return id }
        return nil
    }

    @MainActor
    private func openBookingDetailFromDrawer() async {
        guard let bookingId = resolvedThreadBookingId else {
            bookingDetailOpenError = "We couldn't find this booking yet. Try again after refresh."
            return
        }
        guard !isOpeningBookingDetailFromDrawer else { return }
        isOpeningBookingDetailFromDrawer = true
        defer { isOpeningBookingDetailFromDrawer = false }
        do {
            let row = try await ConsumerBookingsSimpleAPI.fetchConsumerBookingById(
                bookingId: bookingId,
                bearerToken: sessionManager.currentSession?.token
            )
            withAnimation(MessagingFlowMotion.messageAppearSpring) {
                showBookingDetails = false
            }
            bookingDetailsPanelDragOffset = 0
            pushedBookingDetailRoute = MessagingThreadPushedBookingDetail(row: row)
        } catch {
            if ConsumerBookingsSimpleAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
            } else {
                bookingDetailOpenError = "We couldn't open this booking. Try again from the Bookings tab."
            }
        }
    }

    /// Trailing drawer over chat: follows finger when pulling from the right edge; full open uses the same drag-to-dismiss affordance.
    private var bookingDetailsTrailingDrawerOverlay: some View {
        GeometryReader { geo in
            let panelW = Self.bookingPanelWidth(screenWidth: geo.size.width)
            let panelH = Self.bookingPanelHeight(screenHeight: geo.size.height)
            let panelTrailingX = showBookingDetails
                ? bookingDetailsPanelDragOffset
                : (panelW - bookingDetailsEdgePull)
            let scrimStrength: CGFloat = {
                if showBookingDetails { return 1 }
                guard panelW > 0 else { return 0 }
                return bookingDetailsEdgePull / panelW
            }()

            ZStack(alignment: Alignment(horizontal: .trailing, vertical: .center)) {
                Button {
                    if showBookingDetails {
                        withAnimation(MessagingFlowMotion.messageAppearSpring) {
                            showBookingDetails = false
                        }
                    } else {
                        withAnimation(Self.edgeGestureSnapSpring) {
                            bookingDetailsEdgePull = 0
                        }
                    }
                } label: {
                    Color.black.opacity(0.45 * scrimStrength)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss details")

                MessagingThreadBookingDetailsView(
                    onClose: {
                        withAnimation(MessagingFlowMotion.messageAppearSpring) {
                            showBookingDetails = false
                        }
                    },
                    serviceName: MessagingProviderRoleLine.presentableServiceName(vm.bookingContext?.serviceName),
                    schedule: formattedContextHeaderScheduledTime,
                    status: headerBookingStatusPresentable,
                    canOpenFullBookingDetail: resolvedThreadBookingId != nil,
                    isOpeningBookingDetail: isOpeningBookingDetailFromDrawer,
                    onEditBooking: {
                        Task { await openBookingDetailFromDrawer() }
                    }
                )
                .frame(width: panelW)
                .frame(height: panelH)
                .offset(x: panelTrailingX)
                #if os(iOS)
                .simultaneousGesture(bookingDetailsPanelDismissDragGesture(panelWidth: panelW))
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
    }

    private static func bookingPanelWidth(screenWidth: CGFloat) -> CGFloat {
        min(screenWidth * 0.68, 286)
    }

    private static func bookingPanelHeight(screenHeight: CGFloat) -> CGFloat {
        min(screenHeight * 0.42, 292)
    }

    // MARK: - Compact sticky header (back + avatar + provider summary)

    private var conversationExitButton: some View {
        Button {
            leaveConversation()
        } label: {
            Image(systemName: "chevron.left")
                .font(OnCutsFont.system(size: 17, weight: .semibold))
                .foregroundStyleOnCutsShellIcon()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var conversationOverflowMenu: some View {
        Menu {
            if vm.bookingContext != nil {
                Button {
                    withAnimation(MessagingFlowMotion.messageAppearSpring) {
                        showBookingDetails = true
                    }
                } label: {
                    Text("Details")
                }
            }
            if vm.bookingContext?.consumerMayCancelActiveBooking == true {
                Button(role: .destructive) {
                    showCancelBookingConfirm = true
                } label: {
                    Text("Cancel booking")
                }
            } else {
                Button(role: .destructive) {
                    showDeleteConversationConfirm = true
                } label: {
                    Text("Delete conversation")
                }
            }
            Divider()
            Button {
                messagePendingReport = nil
                showReportMessageDialog = true
            } label: {
                Text("Report conversation")
            }
            Button(role: .destructive) {
                showBlockUserConfirm = true
            } label: {
                Text("Block user")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(OnCutsFont.system(size: 24, weight: .medium))
                .foregroundStyle(Color.lavaShellCream)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Conversation options")
    }

    private var stickyHeaderProviderSummary: some View {
        Button {
            guard vm.bookingContext != nil else { return }
            withAnimation(MessagingFlowMotion.messageAppearSpring) {
                showBookingDetails = true
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                stickyHeaderSquareAvatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(threadCounterpartyDisplayName)
                        .font(Self.stickyHeaderNameFont)
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    if vm.bookingContext != nil, !headerBookingStatusPresentable.isEmpty {
                        Text(headerBookingStatusPresentable)
                            .font(Self.stickyHeaderMetaFont)
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .kerning(Self.stickyHeaderMetaKerning)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    if !threadHeaderRoleServiceLine.isEmpty {
                        Text(threadHeaderRoleServiceLine)
                            .font(Self.stickyHeaderMetaFont)
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .kerning(Self.stickyHeaderMetaKerning)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Provider details")
        .accessibilityHint(vm.bookingContext != nil ? "Opens booking details." : "")
    }

    private var instagramStickyHeader: some View {
        HStack(alignment: .center, spacing: 2) {
            conversationExitButton
            stickyHeaderProviderSummary
            conversationOverflowMenu
        }
        .opacity(threadHeaderDimTextColumn ? 0.6 : 1)
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background {
            ZStack {
                Color.white.opacity(0.05)
                Color.black.opacity(0.1)
            }
            .ignoresSafeArea(edges: .top)
        }
        .simultaneousGesture(TapGesture().onEnded { dismissMessageComposerKeyboard() })
        #if os(iOS)
        .safeAreaPadding(.top, 2)
        #endif
    }

    /// Square crop beside the back chevron in the sticky header.
    private var stickyHeaderSquareAvatar: some View {
        AvatarView(
            imageUrl: threadCounterpartyAvatarURL,
            name: threadCounterpartyDisplayName,
            size: Self.stickyHeaderAvatarSize,
            fontSize: Self.stickyHeaderAvatarInitialFont,
            clipStyle: .square(cornerRadius: Self.stickyHeaderAvatarCornerRadius)
        )
    }

    // MARK: - Message list + timeline rail

    private func messagesTimelineStack(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(vm.messages) { msg in
                messageBubble(msg)
                    .id(msg.id)
                    .transition(
                        allowsThreadContentMotion
                            ? .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: msg.isFromCurrentUser ? .trailing : .leading)),
                                removal: .opacity
                            )
                            : .identity
                    )
            }
            Color.clear
                .frame(height: 1)
                .id(Self.messagingThreadBottomID)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
    }

    private var waitingForProviderChromeHeadline: String {
        let n = (vm.bookingContext?.barberName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || n.caseInsensitiveCompare("Chat") == .orderedSame {
            return "Waiting for your provider"
        }
        return "Waiting for \(n)"
    }

    private var cameraUnavailableAlertMessage: String {
        #if targetEnvironment(simulator)
        "The iOS Simulator doesn’t support the camera. Use the photo library button, or run on an iPhone."
        #else
        "The camera can’t be used on this device right now. Try the photo library, or allow camera access in Settings → \(Bundle.main.appDisplayName) under Privacy & Security."
        #endif
    }

    private var waitingForBarberChrome: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .foregroundStyle(Color.lavaShellCream.opacity(0.9))
            Text(waitingForProviderChromeHeadline)
                .font(OnCutsFont.subheadline(weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
            Spacer()
        }
        .padding(14)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Color.white.opacity(0.15)
            }
        }
    }

    private var composerChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if canImport(UIKit)
            if let draft = vm.composerDraftImage {
                composerDraftImagePreview(draft)
            }
            #endif

            composerInputRow
        }
    }

    private var composerInputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(OnCutsFont.title3)
                    .foregroundStyleOnCutsShellIcon()
                    .frame(width: 36, height: 36)
            }
            .disabled(vm.isSendingComposer)
            .onChange(of: pickerItem) { _, new in
                guard let new else { return }
                Task { @MainActor in
                    defer { pickerItem = nil }
                    guard let data = try? await new.loadTransferable(type: Data.self),
                          let ui = UIImage(data: data) else { return }
                    vm.stageComposerPhoto(data: data, uiImage: ui)
                }
            }

            #if os(iOS)
            Button {
                #if targetEnvironment(simulator)
                showCameraUnavailableAlert = true
                #elseif canImport(UIKit)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCameraCapture = true
                } else {
                    showCameraUnavailableAlert = true
                }
                #else
                showCameraUnavailableAlert = true
                #endif
            } label: {
                Image(systemName: "plus")
                    .font(OnCutsFont.title3(weight: .semibold))
                    .foregroundStyleOnCutsShellIcon()
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(vm.isSendingComposer)
            .accessibilityLabel("Take a photo")
            #endif

            TextField("Message", text: $vm.draftText, axis: .vertical)
                .id(vm.composerRefreshID)
                .focused($isMessageComposerFocused)
                .lineLimit(1 ... 5)
                .foregroundStyle(Color.lavaShellCream)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .disabled(vm.isSendingComposer)

            Button {
                Task { await vm.sendComposer() }
            } label: {
                if vm.isSendingComposer {
                    ProgressView()
                        .tint(Color.lavaShellCream)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(OnCutsFont.system(size: 32))
                        .foregroundStyleOnCutsShellIcon()
                }
            }
            .disabled(!vm.canSendComposer || vm.isSendingComposer)
        }
    }

    #if canImport(UIKit)
    private func composerDraftImagePreview(_ draft: MessagingComposerDraftImage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(uiImage: draft.preview)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.lavaShellCream.opacity(0.22), lineWidth: 0.75)
                }
                .accessibilityLabel("Photo attached")

            VStack(alignment: .leading, spacing: 4) {
                Text("Photo attached")
                    .font(OnCutsFont.caption(weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                Text("Add a caption or tap send")
                    .font(OnCutsFont.caption2)
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }

            Spacer(minLength: 0)

            Button {
                vm.clearComposerDraftImage()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(OnCutsFont.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.lavaShellCream.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(vm.isSendingComposer)
            .accessibilityLabel("Remove photo")
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
    #endif

    @ViewBuilder
    private func messageBubble(_ msg: ChatThreadMessage) -> some View {
        let outgoing = msg.isFromCurrentUser
        HStack {
            if outgoing { Spacer(minLength: 40) }
            VStack(alignment: outgoing ? .trailing : .leading, spacing: 6) {
                if let thumbId = msg.clientUUID, let img = vm.pendingImageThumbs[thumbId] {
                    messagingLiquidMediaBubble(isOutgoing: outgoing) {
                        ZStack(alignment: .bottom) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: 220, maxHeight: 220)
                                .clipped()
                                .blur(radius: msg.uploadProgress != nil ? 10 : 0)
                            if msg.uploadProgress != nil {
                                ProgressView()
                                    .progressViewStyle(.linear)
                                    .tint(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .padding(10)
                            }
                        }
                        .frame(maxWidth: 220, maxHeight: 220)
                    }
                } else if let url = msg.mediaUrl {
                    messagingLiquidMediaBubble(isOutgoing: outgoing) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .font(OnCutsFont.title2)
                                        .foregroundStyle(Color.lavaShellCream.opacity(0.85))
                                    Text("Couldn’t load this image.")
                                        .font(OnCutsFont.caption(weight: .semibold))
                                        .foregroundStyle(Color.lavaShellCream.opacity(0.9))
                                        .multilineTextAlignment(.center)
                                }
                                .frame(width: 200, height: 120)
                            default:
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 200, height: 140)
                                    .overlay { ProgressView().tint(Color.lavaShellCream) }
                            }
                        }
                        .frame(maxWidth: 240, maxHeight: 240)
                        .clipped()
                    }
                }

                if !msg.text.isEmpty {
                    messagingLiquidTextBubble(isOutgoing: outgoing) {
                        Text(msg.text)
                            .font(OnCutsFont.bodyMedium)
                            .foregroundStyle(outgoing ? MessagingOutgoingBubbleStyle.labelColor : Color.lavaShellCream)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                } else if !outgoing,
                          msg.mediaUrl == nil,
                          msg.clientUUID == nil,
                          msg.serverMessageIdForReport != nil {
                    messagingLiquidTextBubble(isOutgoing: false) {
                        Text("This message couldn’t be shown.")
                            .font(OnCutsFont.caption(weight: .semibold))
                            .foregroundStyle(Color.lavaShellCream.opacity(0.88))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
            }
            if !outgoing { Spacer(minLength: 40) }
        }
        .contextMenu {
            if !msg.isFromCurrentUser {
                Button {
                    messagePendingReport = msg
                    showReportMessageDialog = true
                } label: {
                    Label("Report message", systemImage: "flag")
                }
            }
        }
    }

    @MainActor
    private func submitModerationReport(reason: String) async {
        let mid = messagePendingReport?.serverMessageIdForReport
        defer {
            messagePendingReport = nil
            showReportMessageDialog = false
        }
        do {
            try await vm.submitContentReport(reason: reason, details: nil, messageServerId: mid)
            moderationBanner = "Thanks — we received your report."
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run { moderationBanner = nil }
            }
        } catch {
            vm.loadError = error.localizedDescription
        }
    }

    @MainActor
    private func performBlockUser() async {
        do {
            try await vm.blockCounterpartyAndNotify()
            NotificationCenter.default.post(name: .messagingBlockedUserDidChange, object: nil)
            leaveConversation()
        } catch {
            vm.loadError = error.localizedDescription
        }
    }

    private func messagingLiquidTextBubble<Content: View>(isOutgoing: Bool, @ViewBuilder content: () -> Content) -> some View {
        MessagingBubbleChrome(isOutgoing: isOutgoing, content: content)
    }

    private func messagingLiquidMediaBubble<Content: View>(isOutgoing: Bool, @ViewBuilder content: () -> Content) -> some View {
        MessagingBubbleChrome(isOutgoing: isOutgoing, content: content)
    }

}

// MARK: - UGC terms gate (before messaging)

struct MessagingUGCTermsGateView: View {
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Before you message")
                        .font(OnCutsFont.title3(weight: .bold))
                    Text("Messages & community safety")
                        .font(OnCutsFont.subheadline(weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        "\(AppBranding.displayName) lets you message providers about bookings. By continuing, you agree to our Terms of Service and acknowledge that messages are user-generated content: some text may be filtered automatically, you can report objectionable messages or conversations, and you can block abusive users (we are notified when you block). Our team reviews serious reports as soon as possible and aims to act within 24 hours, including removing content or restricting accounts when appropriate."
                    )
                    .font(OnCutsFont.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        Link(destination: AppBranding.termsOfServiceURL) {
                            Label("Terms of Service", systemImage: "doc.text")
                        }
                        Link(destination: AppBranding.privacyPolicyURL) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                    }
                    .font(OnCutsFont.subheadline(weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Community guidelines")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("I agree") {
                        onAccept()
                    }
                    .font(OnCutsFont.body(weight: .semibold))
                }
            }
        }
        #if os(iOS)
        .presentationBackground(.regularMaterial)
        .interactiveDismissDisabled(true)
        #endif
    }
}

// MARK: - Thread booking details (trailing drawer over chat)

private struct MessagingThreadPushedBookingDetail: Hashable, Identifiable {
    let id: UUID
    let row: ConsumerBookingSimpleRow

    init(row: ConsumerBookingSimpleRow) {
        self.row = row
        id = ConsumerHomeBookingStackRoute.stablePresentationID(forBookingId: row.id)
    }
}

private struct MessagingThreadBookingDetailsView: View {
    let onClose: () -> Void

    let serviceName: String
    let schedule: String
    let status: String
    let canOpenFullBookingDetail: Bool
    let isOpeningBookingDetail: Bool
    let onEditBooking: () -> Void

    private static let cardCorner: CGFloat = 18

    private static var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cardCorner,
            bottomLeadingRadius: cardCorner,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: onEditBooking) {
                    HStack(spacing: 6) {
                        if isOpeningBookingDetail {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.lavaShellCreamSecondary)
                        }
                        Text("Edit Booking")
                            .font(OnCutsFont.subheadline(weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.oliveGreen.opacity(0.55), lineWidth: 1)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canOpenFullBookingDetail || isOpeningBookingDetail)
                .opacity(canOpenFullBookingDetail ? 1 : 0.5)
                .accessibilityHint("Opens the full booking details screen.")

                Spacer(minLength: 0)

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(OnCutsFont.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.lavaShellCream.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)

            GeometryReader { contentGeo in
                ScrollView {
                    VStack {
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 16) {
                            bookingDetailRow(title: "Service", value: serviceName)
                            bookingDetailRow(title: "Schedule", value: schedule)
                            bookingDetailRow(title: "Status", value: status)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: contentGeo.size.height)
                }
                #if os(iOS)
                .scrollContentBackground(.hidden)
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                OnCutsLavaLampBackground()
                Color.black.opacity(0.18)
            }
            .clipShape(Self.panelShape)
        }
        .clipShape(Self.panelShape)
        .overlay {
            Self.panelShape
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 22, x: -10, y: 0)
    }

    private func bookingDetailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .bookingDetailFieldTitleStyle()
            Text(value)
                .font(OnCutsFont.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(Color.lavaShellCream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Instagram-style conversation layout (alias for `MessagingConversationView`).
typealias ConversationDetailView = MessagingConversationView

#if canImport(UIKit) && os(iOS)
/// Matches the Service Provider conversation back-swipe: rightward, mostly horizontal, 20% width or 300 pt/s flick.
private enum ConversationSwipeBackMetrics {
    /// Horizontal movement must be at least ~85% of vertical movement.
    static let horizontalDominanceRatio: CGFloat = 0.85
    static let dismissDistanceScreenFraction: CGFloat = 0.20
    static let dismissVelocityPointsPerSecond: CGFloat = 300
    static let maxDragOffsetScreenFraction: CGFloat = 0.85
}

/// Full-screen rightward swipe-to-pop that runs simultaneously with the thread `UIScrollView`.
private struct ConversationSwipeBackPanEnabler: UIViewControllerRepresentable {
    @Binding var dragOffset: CGFloat
    var isEnabled: Bool
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(dragOffset: $dragOffset, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onDismiss = onDismiss
        context.coordinator.attach(from: uiViewController)
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @Binding var dragOffset: CGFloat
        var onDismiss: () -> Void
        var isEnabled = true

        private weak var panRecognizer: UIPanGestureRecognizer?
        private weak var hostView: UIView?
        private var swipeEngaged = false

        init(dragOffset: Binding<CGFloat>, onDismiss: @escaping () -> Void) {
            _dragOffset = dragOffset
            self.onDismiss = onDismiss
        }

        func attach(from viewController: UIViewController) {
            DispatchQueue.main.async { [weak self, weak viewController] in
                guard let self, let viewController else { return }
                let host = viewController.navigationController?.view ?? viewController.view
                guard let host else { return }
                if self.panRecognizer?.view === host { return }
                self.detach()
                let pan = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
                pan.delegate = self
                pan.cancelsTouchesInView = false
                host.addGestureRecognizer(pan)
                self.panRecognizer = pan
                self.hostView = host
            }
        }

        func detach() {
            if let host = hostView, let pan = panRecognizer {
                host.removeGestureRecognizer(pan)
            }
            panRecognizer = nil
            hostView = nil
            swipeEngaged = false
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard isEnabled, let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)
            let width = translation.x
            let height = translation.y
            let screenWidth = max(view.bounds.width, 1)

            switch gesture.state {
            case .began:
                swipeEngaged = false
            case .changed:
                guard width > 0, width >= abs(height) * ConversationSwipeBackMetrics.horizontalDominanceRatio else {
                    if swipeEngaged {
                        swipeEngaged = false
                        snapBack()
                    }
                    return
                }
                swipeEngaged = true
                dragOffset = min(width, screenWidth * ConversationSwipeBackMetrics.maxDragOffsetScreenFraction)
            case .ended, .cancelled, .failed:
                defer {
                    swipeEngaged = false
                    gesture.setTranslation(.zero, in: view)
                }
                guard swipeEngaged, width > 0 else {
                    snapBack()
                    return
                }
                let dismissDistance = screenWidth * ConversationSwipeBackMetrics.dismissDistanceScreenFraction
                let shouldDismiss = width >= dismissDistance
                    || velocity.x > ConversationSwipeBackMetrics.dismissVelocityPointsPerSecond
                if shouldDismiss, width >= abs(height) * ConversationSwipeBackMetrics.horizontalDominanceRatio {
                    dragOffset = 0
                    onDismiss()
                } else {
                    snapBack()
                }
            default:
                break
            }
        }

        private func snapBack() {
            Task { @MainActor in
                withAnimation(.spring(response: 0.33, dampingFraction: 0.86, blendDuration: 0.12)) {
                    dragOffset = 0
                }
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, gestureRecognizer === panRecognizer, let view = gestureRecognizer.view else { return false }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: view)
            // Slow rightward drags are allowed; dominance is enforced in `handlePan`.
            if abs(velocity.x) < 40, abs(velocity.y) < 40 { return true }
            guard velocity.x > 0 else { return false }
            return abs(velocity.x) >= abs(velocity.y) * ConversationSwipeBackMetrics.horizontalDominanceRatio
                || velocity.x > ConversationSwipeBackMetrics.dismissVelocityPointsPerSecond
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === panRecognizer && otherGestureRecognizer.view is UIScrollView
        }
    }
}

/// Captures touches only on the **right** screen edge (below the header) so the booking panel can be pulled in
/// without blocking the thread `ScrollView`, the system back swipe, or the **⋯** menu in the sticky header
/// (the menu sits in the top-right ~52pt and would otherwise be covered by this overlay).
private final class ConversationRightEdgePassthroughUIView: UIView {
    var edgeCaptureWidth: CGFloat = 52
    /// When false, the overlay is fully passthrough (no hit stealing on the trailing strip).
    var capturesRightEdge = false
    /// Top: nav + compact sticky header — don’t steal taps meant for chrome.
    private var headerChromeExclusionHeight: CGFloat { safeAreaInsets.top + 88 }
    /// Bottom: composer, staged-photo preview, Send, and keyboard — keep the trailing strip clear for taps.
    private var bottomComposerExclusionHeight: CGFloat { safeAreaInsets.bottom + 220 }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point), capturesRightEdge else { return nil }
        if point.y < headerChromeExclusionHeight {
            return nil
        }
        if point.y > bounds.height - bottomComposerExclusionHeight {
            return nil
        }
        if point.x > bounds.width - edgeCaptureWidth {
            return super.hitTest(point, with: event)
        }
        return nil
    }
}

private struct ConversationBookingPanelEdgeOverlay: UIViewRepresentable {
    @Binding var bookingDetailsEdgePull: CGFloat
    var showBookingDetails: Bool
    var hasBookingContext: Bool
    var onBookingPanelCommitted: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            bookingDetailsEdgePull: $bookingDetailsEdgePull,
            onBookingPanelCommitted: onBookingPanelCommitted
        )
    }

    func makeUIView(context: Context) -> ConversationRightEdgePassthroughUIView {
        let v = ConversationRightEdgePassthroughUIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = true
        v.capturesRightEdge = !showBookingDetails && hasBookingContext
        context.coordinator.attach(to: v)
        return v
    }

    func updateUIView(_ uiView: ConversationRightEdgePassthroughUIView, context: Context) {
        context.coordinator.showBookingDetails = showBookingDetails
        context.coordinator.hasBookingContext = hasBookingContext
        context.coordinator.onBookingPanelCommitted = onBookingPanelCommitted
        uiView.capturesRightEdge = !showBookingDetails && hasBookingContext
    }

    static func dismantleUIView(_ uiView: ConversationRightEdgePassthroughUIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var bookingDetailsEdgePull: Binding<CGFloat>
        var showBookingDetails = false
        var hasBookingContext = false
        var onBookingPanelCommitted: () -> Void

        private weak var rightPan: UIScreenEdgePanGestureRecognizer?
        private weak var hostView: ConversationRightEdgePassthroughUIView?

        init(
            bookingDetailsEdgePull: Binding<CGFloat>,
            onBookingPanelCommitted: @escaping () -> Void
        ) {
            self.bookingDetailsEdgePull = bookingDetailsEdgePull
            self.onBookingPanelCommitted = onBookingPanelCommitted
        }

        func attach(to view: ConversationRightEdgePassthroughUIView) {
            hostView = view
            let right = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleRightPan(_:)))
            right.edges = .right
            right.delegate = self
            right.cancelsTouchesInView = false
            view.addGestureRecognizer(right)
            rightPan = right
        }

        func detach() {
            if let v = hostView, let r = rightPan {
                v.removeGestureRecognizer(r)
            }
            rightPan = nil
            hostView = nil
        }

        @objc private func handleRightPan(_ g: UIScreenEdgePanGestureRecognizer) {
            guard !showBookingDetails, hasBookingContext else { return }
            let screenW = UIScreen.main.bounds.width
            let panelW = min(screenW * 0.68, 286)
            let t = g.translation(in: g.view)
            let vx = g.velocity(in: g.view).x

            switch g.state {
            case .changed:
                let pull = min(max(0, -t.x), panelW)
                bookingDetailsEdgePull.wrappedValue = pull
            case .ended, .cancelled, .failed:
                let pull = bookingDetailsEdgePull.wrappedValue
                let shouldOpen = pull > panelW * 0.22 || vx < -560
                if shouldOpen {
                    onBookingPanelCommitted()
                } else {
                    UIView.animate(
                        withDuration: 0.32,
                        delay: 0,
                        usingSpringWithDamping: 0.88,
                        initialSpringVelocity: 0.45,
                        options: [.beginFromCurrentState, .allowUserInteraction]
                    ) {
                        self.bookingDetailsEdgePull.wrappedValue = 0
                    }
                }
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === rightPan && !showBookingDetails && hasBookingContext
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === rightPan && otherGestureRecognizer.view is UIScrollView
        }
    }
}
#endif
