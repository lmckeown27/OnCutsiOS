//
//  MessagingRealtime.swift
//  Intera
//
//  Socket.IO listener for `new-message` (AvilaPlatforms real-time chat).
//  Must join `join-personal` + `join-conversation` like the web client, or `io.to("user-…")` emits are never received.
//

import Foundation
import SocketIO

@MainActor
final class MessagingSocketController {
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var personalRoomUserId: String?
    private var joinedConversationIds: [String] = []

    /// `conversationId` + decoded message DTO from the server payload.
    var onNewMessage: ((String, MessagingMessageDTO) -> Void)?

    /// Emitted to the consumer's personal room when a provider marks a booking complete (`PUT …/bookings-simple/:id/complete`).
    var onBookingPaymentRequested: ((BookingPaymentRequestPayload) -> Void)?

    /// Emitted when a booking leaves the **COMPLETED (awaiting payment)** state — e.g. `PUT …/undo-complete` (`booking-status-changed`).
    var onBookingStatusChanged: ((String, String) -> Void)?

    func connect(bearerToken: String?, personalRoomUserId: String?) {
        // Rebuilding the socket (e.g. refreshed JWT) must **not** drop conversation room ids — otherwise
        // `emitPendingRoomSubscriptions` only runs `join-personal` and the client misses `conversation-*` emits.
        disconnect(clearConversationSubscriptions: false)
        let trimmedUser = personalRoomUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.personalRoomUserId = trimmedUser.isEmpty ? nil : trimmedUser

        let url = AppConfiguration.messagingSocketOriginURL
        var config: SocketIOClientConfiguration = [.compress, .forceWebsockets(true), .reconnects(true)]
        if let t = bearerToken, !t.isEmpty {
            config.insert(.connectParams(["token": t]))
            config.insert(.extraHeaders(["Authorization": "Bearer \(t)"]))
        }
        let mgr = SocketManager(socketURL: url, config: config)
        let s = mgr.defaultSocket

        s.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                self?.emitPendingRoomSubscriptions()
            }
        }

        s.on(clientEvent: .reconnect) { [weak self] _, _ in
            Task { @MainActor in
                self?.emitPendingRoomSubscriptions()
            }
        }

        s.on("new-message") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleNewMessagePayload(data)
            }
        }

        s.on("booking-completed") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleBookingCompletedPayload(data)
            }
        }

        s.on("booking-status-changed") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleBookingStatusChangedPayload(data)
            }
        }

        manager = mgr
        socket = s
        s.connect()
    }

    /// Subscribe to `conversation-<id>` (server also emits `new-message` here; matches web `join-conversation`).
    /// Preserves server id casing for `emit` (some deployments key rooms on the raw DB id string).
    func subscribeConversationRoom(_ conversationId: String) {
        let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return }
        if !joinedConversationIds.contains(where: { $0.caseInsensitiveCompare(cid) == .orderedSame }) {
            joinedConversationIds.append(cid)
        }
        if socket?.status == .connected {
            socket?.emit("join-conversation", cid)
        }
    }

    func unsubscribeConversationRoom(_ conversationId: String) {
        let cid = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        joinedConversationIds.removeAll { $0.caseInsensitiveCompare(cid) == .orderedSame }
        socket?.emit("leave-conversation", cid)
    }

    /// `leave-conversation` for every joined room except `conversationId` (case-insensitive match).
    func leaveAllConversationRoomsExcept(_ conversationId: String) {
        let keep = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keep.isEmpty else { return }
        for cid in Array(joinedConversationIds) where cid.caseInsensitiveCompare(keep) != .orderedSame {
            unsubscribeConversationRoom(cid)
        }
    }

    /// - Parameter clearConversationSubscriptions: Pass `false` when replacing the socket while the same user session
    ///   should stay in the same `join-conversation` rooms (token refresh / transport rebuild). Pass `true` on sign-out.
    func disconnect(clearConversationSubscriptions: Bool = true) {
        socket?.disconnect()
        socket = nil
        manager = nil
        personalRoomUserId = nil
        if clearConversationSubscriptions {
            joinedConversationIds.removeAll()
        }
    }

    /// Re-sends `join-personal` + all `join-conversation` subscriptions when already connected (foreground resume, etc.).
    func reemitSubscribedRoomsIfConnected() {
        emitPendingRoomSubscriptions()
    }

    private func emitPendingRoomSubscriptions() {
        guard let s = socket, s.status == .connected else { return }
        if let uid = personalRoomUserId, !uid.isEmpty {
            s.emit("join-personal", uid)
        }
        for cid in joinedConversationIds {
            s.emit("join-conversation", cid)
        }
    }

    private func handleNewMessagePayload(_ data: [Any]) {
        guard !data.isEmpty else { return }

        // Some servers emit `(conversationId, message)` as two Socket.IO arguments.
        if data.count >= 2,
           let cid = Self.conversationIdString(from: data[0]),
           let msg = Self.decodeSocketMessagingMessageDTO(data[1], conversationIdHint: cid) {
            onNewMessage?(cid, msg)
            return
        }

        for piece in data {
            if Self.tryEmitNewMessage(from: piece, conversationIdHint: nil, onNewMessage: onNewMessage) {
                return
            }
        }
    }

    /// Socket.IO may deliver nested `NSDictionary` values (`NSDate`, etc.) that fail `JSONSerialization.isValidJSONObject`.
    /// Coerce those into JSON-safe primitives before decoding ``MessagingMessageDTO``.
    private static func socketJSONData(from value: Any) -> Data? {
        if let d = value as? Data { return d }
        if let s = value as? String, let d = s.data(using: .utf8) { return d }
        if JSONSerialization.isValidJSONObject(value),
           let d = try? JSONSerialization.data(withJSONObject: value) {
            return d
        }
        if let sanitized = sanitizeForJSONSerialization(value),
           JSONSerialization.isValidJSONObject(sanitized),
           let d = try? JSONSerialization.data(withJSONObject: sanitized) {
            return d
        }
        return nil
    }

    private static func sanitizeForJSONSerialization(_ value: Any) -> Any? {
        switch value {
        case is NSNull:
            return NSNull()
        case let b as Bool:
            return b
        case let n as NSNumber:
            return n
        case let n as Int:
            return n
        case let n as Int64:
            return n
        case let n as Double:
            return n
        case let s as String:
            return s
        case let s as NSString:
            return s as String
        case let d as Date:
            return ISO8601DateFormatter().string(from: d)
        case let d as NSDictionary:
            var out: [String: Any] = [:]
            for (k, v) in d {
                guard let key = k as? String else { continue }
                if let sv = sanitizeForJSONSerialization(v) {
                    out[key] = sv
                }
            }
            return out
        case let a as NSArray:
            return a.compactMap { sanitizeForJSONSerialization($0) }
        case let d as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in d {
                if let sv = sanitizeForJSONSerialization(v) {
                    out[k] = sv
                }
            }
            return out
        case let a as [Any]:
            return a.compactMap { sanitizeForJSONSerialization($0) }
        default:
            return nil
        }
    }

    private static func conversationIdString(from value: Any) -> String? {
        switch value {
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let n as NSNumber:
            let t = n.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let i as Int:
            return String(i)
        default:
            return nil
        }
    }

    /// Socket.IO often surfaces nested objects as `NSDictionary`, which does not bridge with `as? [String: Any]`.
    private static func stringKeyedDictionary(from value: Any) -> [String: Any]? {
        if let d = value as? [String: Any] { return d }
        if let d = value as? NSDictionary {
            var out: [String: Any] = [:]
            for (k, v) in d {
                guard let ks = k as? String else { continue }
                out[ks] = v
            }
            return out
        }
        return nil
    }

    private static func conversationIdFromEnvelopeDict(_ dict: [String: Any]) -> String? {
        if let v = dict["conversation_id"] ?? dict["conversationId"] {
            return conversationIdString(from: v)
        }
        if let data = stringKeyedDictionary(from: dict["data"] as Any) {
            if let v = data["conversation_id"] ?? data["conversationId"] {
                return conversationIdString(from: v)
            }
        }
        return nil
    }

    private static func nestedMessagePayload(fromRoot value: Any) -> (message: Any, conversationHint: String?)? {
        guard let dict = stringKeyedDictionary(from: value) else { return nil }
        let hint = conversationIdFromEnvelopeDict(dict)
        if let m = dict["message"] {
            return (m, hint)
        }
        if let data = stringKeyedDictionary(from: dict["data"] as Any), let m = data["message"] {
            return (m, hint ?? conversationIdFromEnvelopeDict(data))
        }
        return nil
    }

    private static func decodeMessagingMessageDTO(fromJSONData jsonData: Data, conversationIdHint: String?) -> MessagingMessageDTO? {
        let decoder = JSONDecoder()
        guard var msg = try? decoder.decode(MessagingMessageDTO.self, from: jsonData) else { return nil }
        let trimmedHint = conversationIdHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let existing = msg.conversationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedHint.isEmpty, existing.isEmpty {
            msg = MessagingMessageDTO(
                idString: msg.idString,
                conversationId: trimmedHint,
                senderId: msg.senderId,
                senderRole: msg.senderRole,
                content: msg.content,
                mediaUrl: msg.mediaUrl,
                createdAt: msg.createdAt
            )
        }
        return msg
    }

    private static func decodeSocketMessagingMessageDTO(_ value: Any, conversationIdHint: String?) -> MessagingMessageDTO? {
        guard let jsonData = socketJSONData(from: value) else { return nil }
        return decodeMessagingMessageDTO(fromJSONData: jsonData, conversationIdHint: conversationIdHint)
    }

    private static func tryEmitNewMessage(
        from piece: Any,
        conversationIdHint: String?,
        onNewMessage: ((String, MessagingMessageDTO) -> Void)?
    ) -> Bool {
        let hintRoot = stringKeyedDictionary(from: piece).flatMap { conversationIdFromEnvelopeDict($0) }
        let mergedHint: String? = {
            for h in [conversationIdHint, hintRoot].compactMap({ $0 }) {
                let t = h.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
            return nil
        }()

        if let nested = nestedMessagePayload(fromRoot: piece),
           let msg = decodeSocketMessagingMessageDTO(nested.message, conversationIdHint: mergedHint ?? nested.conversationHint),
           let cid = msg.conversationId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cid.isEmpty {
            onNewMessage?(cid, msg)
            return true
        }

        if let msg = decodeSocketMessagingMessageDTO(piece, conversationIdHint: mergedHint),
           let cid = msg.conversationId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cid.isEmpty {
            onNewMessage?(cid, msg)
            return true
        }

        guard let jsonData = socketJSONData(from: piece) else { return false }
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(MessagingSocketNewMessagePayload.self, from: jsonData),
           let cid = payload.conversationId, !cid.isEmpty,
           let msg = payload.message {
            onNewMessage?(cid, msg)
            return true
        }
        return false
    }

    private func handleBookingCompletedPayload(_ data: [Any]) {
        guard let payload = BookingPaymentRequestPayload.decode(socketData: data) else { return }
        onBookingPaymentRequested?(payload)
    }

    private func handleBookingStatusChangedPayload(_ data: [Any]) {
        guard let first = data.first else { return }
        let jsonData: Data?
        if let d = first as? Data {
            jsonData = d
        } else if JSONSerialization.isValidJSONObject(first) {
            jsonData = try? JSONSerialization.data(withJSONObject: first)
        } else if let s = first as? String, let d = s.data(using: .utf8) {
            jsonData = d
        } else {
            jsonData = nil
        }
        guard let jsonData else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let parsed = try? decoder.decode(BookingStatusChangedSocketDTO.self, from: jsonData) else { return }
        let bid = (parsed.bookingId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let st = (parsed.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bid.isEmpty, !st.isEmpty else { return }
        onBookingStatusChanged?(bid, st)
    }
}

/// Socket `booking-status-changed` (e.g. barber undo-complete → `ACCEPTED`).
private struct BookingStatusChangedSocketDTO: Decodable, Sendable {
    let bookingId: String?
    let status: String?
}

enum MessagingDTOMapper {
    /// `counterpartyFallbackDisplayName` is typically **`otherUser.displayName`** from the conversations list when `booking.barber_name` / business name is empty (avoids showing the generic role **“Barber”** in the nav title).
    /// `existingBookingId` keeps `bookings.id` when a thread payload omits `id` but the client already had it (e.g. from inbox or prior load).
    static func bookingContext(
        from dto: MessagingBookingDTO?,
        counterpartyFallbackDisplayName: String? = nil,
        existingBookingId: String? = nil
    ) -> BookingChatContext? {
        guard let dto else { return nil }
        let status = (dto.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let svc = (dto.serviceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let service = svc.isEmpty ? "Booking" : svc
        let timeRaw = dto.scheduledTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedBarberId = dto.barberId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let barberId = trimmedBarberId.isEmpty
            ? (dto.barberName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : trimmedBarberId
        guard !barberId.isEmpty else { return nil }
        let bnBusiness = (dto.barberBusinessName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let bnPlain = (dto.barberName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFallback = counterpartyFallbackDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let barberName: String = {
            if !bnBusiness.isEmpty { return bnBusiness }
            if !bnPlain.isEmpty { return bnPlain }
            if !trimmedFallback.isEmpty { return trimmedFallback }
            return "Chat"
        }()
        let bookingIdTrimmed: String? = {
            if let raw = dto.id?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty { return raw }
            if let raw = existingBookingId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty { return raw }
            return nil
        }()

        return BookingChatContext(
            statusNormalized: status,
            serviceName: service,
            scheduledTimeRaw: timeRaw,
            location: {
                let loc = (dto.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if loc.isEmpty { return nil }
                // API uses "TBD" when `conversations.location` was never set; don’t treat as a real address.
                if loc.caseInsensitiveCompare("TBD") == .orderedSame { return nil }
                return loc
            }(),
            barberId: barberId,
            barberName: barberName,
            barberImageUrl: dto.barberProfileImageUrl,
            bookingId: bookingIdTrimmed
        )
    }

    static func bookingDTO(from context: BookingChatContext) -> MessagingBookingDTO {
        MessagingBookingDTO(
            id: context.bookingId,
            status: context.statusNormalized,
            serviceName: context.serviceName,
            scheduledTime: context.scheduledTimeRaw,
            location: context.location,
            barberId: context.barberId,
            barberName: context.barberName,
            barberBusinessName: nil,
            barberProfileImageUrl: context.barberImageUrl
        )
    }

    static func chatMessage(
        from dto: MessagingMessageDTO,
        index: Int,
        currentUserId: String
    ) -> ChatThreadMessage {
        let sid = dto.senderId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isMine = !sid.isEmpty && sid == currentUserId
        let hasMedia = dto.mediaUrl.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        let rawText = dto.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let threaded = Self.threadDisplayText(rawText, hasMediaAttachment: hasMedia)
        let text: String = {
            if isMine { return threaded }
            return InteraMessagingContentFilter.displayTextForIncomingCommunity(threaded)
        }()
        let url = dto.mediaUrl.flatMap { URL(string: $0) }
        let created = parseDate(dto.createdAt) ?? Date()
        let sidRaw = dto.idString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reportId = sidRaw.isEmpty ? nil : sidRaw
        return ChatThreadMessage(
            id: dto.stableId(fallbackIndex: index),
            serverMessageIdForReport: reportId,
            clientUUID: nil,
            senderId: sid,
            isFromCurrentUser: isMine,
            text: text,
            mediaUrl: url,
            createdAt: created,
            uploadProgress: nil
        )
    }

    /// Hides server/inbox placeholder copy (e.g. `"Photo"`) under image bubbles so only the image shows.
    private static func threadDisplayText(_ content: String, hasMediaAttachment: Bool) -> String {
        guard hasMediaAttachment, !content.isEmpty else { return content }
        let strippedEmoji = content.replacingOccurrences(of: "📷", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if strippedEmoji.caseInsensitiveCompare("Photo") == .orderedSame {
            return ""
        }
        return content
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        return nil
    }
}
