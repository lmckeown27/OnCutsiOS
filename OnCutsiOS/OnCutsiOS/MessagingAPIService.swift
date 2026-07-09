//
//  MessagingAPIService.swift
//  OnCuts
//
//  REST client for OnCuts messaging (conversations, read receipts, send, upload, delete).
//

import Foundation

private struct SuccessEnvelope<T: Decodable>: Decodable {
    let success: Bool?
    let data: T?
}

/// OnCuts `GET /messages/conversations` returns `{ success, data: { conversations: [...], pagination } }`.
private struct ConversationsListDataPayload: Decodable, Sendable {
    let conversations: [MessagingConversationRowDTO]
}

private struct ThreadDataPayload: Decodable, Sendable {
    let messages: [MessagingMessageDTO]?
    let booking: MessagingBookingDTO?
    /// Same shape as list rows’ `otherUser` — thread payloads often carry display + avatar when `booking.barber_*` is sparse.
    let otherUser: MessagingConversationOtherUserDTO?

    enum CodingKeys: String, CodingKey {
        case messages
        case booking
        case otherUser
        case other_user
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messages = try c.decodeIfPresent([MessagingMessageDTO].self, forKey: .messages)
        booking = try c.decodeIfPresent(MessagingBookingDTO.self, forKey: .booking)
        otherUser =
            try c.decodeIfPresent(MessagingConversationOtherUserDTO.self, forKey: .otherUser)
            ?? c.decodeIfPresent(MessagingConversationOtherUserDTO.self, forKey: .other_user)
    }
}

private struct BlockedIdsEnvelope: Decodable, Sendable {
    let blockedUserIds: [String]?
}

private struct BlockedListDataPayload: Decodable, Sendable {
    let blockedUserIds: [String]?
    let users: [MessagingBlockedUserProfile]?
}

private struct MessageSinglePayload: Decodable, Sendable {
    let message: MessagingMessageDTO?
}

private struct UploadPayload: Decodable, Sendable {
    let mediaUrl: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case mediaUrl = "media_url"
        case url
    }
}

/// `POST /messages/conversations` returns `data.conversation.id` (new) or `data.conversation.conversation_id` (existing thread).
private struct StartConversationNestedPayload: Decodable, Sendable {
    let conversation: ConversationIdFromStartPayload?
}

private struct ConversationIdFromStartPayload: Decodable, Sendable {
    let id: FlexibleConversationIDDecodable?
    let conversation_id: FlexibleConversationIDDecodable?
}

private enum FlexibleConversationIDDecodable: Decodable, Sendable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected Int or String for conversation id")
        }
    }

    var stringValue: String {
        switch self {
        case let .int(i): return String(i)
        case let .string(s): return s
        }
    }
}

private struct StartConversationFlatPayload: Decodable, Sendable {
    let conversationId: String?
    let conversation_id: String?
    let id: String?

    var resolvedId: String? {
        conversationId ?? conversation_id ?? id
    }
}

enum MessagingAPIService {
    // MARK: - URLs

    private static func conversationsBase() throws -> URL {
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let u = URL(string: base + "/messages/conversations") else {
            throw URLError(.badURL)
        }
        return u
    }

    private static func conversationURL(id: String) throws -> URL {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let u = URL(string: base + "/messages/conversations/\(enc)") else {
            throw URLError(.badURL)
        }
        return u
    }

    private static func conversationMessagesURL(id: String) throws -> URL {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let u = URL(string: base + "/messages/conversations/\(enc)/messages") else {
            throw URLError(.badURL)
        }
        return u
    }

    private static func conversationReadURL(id: String) throws -> URL {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let u = URL(string: base + "/messages/conversations/\(enc)/read") else {
            throw URLError(.badURL)
        }
        return u
    }

    private static func uploadURL() throws -> URL {
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let u = URL(string: base + "/upload/chat-image") else {
            throw URLError(.badURL)
        }
        return u
    }

    private static func blocksListURL() throws -> URL {
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let u = URL(string: base + "/messages/blocks") else { throw URLError(.badURL) }
        return u
    }

    private static func blockUserURL() throws -> URL {
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let u = URL(string: base + "/messages/block") else { throw URLError(.badURL) }
        return u
    }

    private static func unblockUserURL() throws -> URL {
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let u = URL(string: base + "/messages/unblock") else { throw URLError(.badURL) }
        return u
    }

    /// Alternate when `POST /messages/unblock` is missing on the host (e.g. older deploy).
    private static func unblockUserNestedURL() throws -> URL {
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let u = URL(string: base + "/messages/blocks/unblock") else { throw URLError(.badURL) }
        return u
    }

    private static func unblockUserDeleteURL(blockedUserId: String) throws -> URL {
        let enc = blockedUserId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? blockedUserId
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let u = URL(string: base + "/messages/blocks/\(enc)") else { throw URLError(.badURL) }
        return u
    }

    private static func conversationReportURL(conversationId: String) throws -> URL {
        let enc = conversationId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? conversationId
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let u = URL(string: base + "/messages/conversations/\(enc)/report") else {
            throw URLError(.badURL)
        }
        return u
    }

    // MARK: - Request

    private static func authorizedGET(url: URL, bearerToken: String?) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        // Thread + inbox GETs must never rely on `URLSession` conditional revalidation alone: the server often
        // answers `304 Not Modified` (see PM2 logs for `/messages/conversations/:id/messages`), and without a
        // fresh JSON body the client keeps stale messages. `throwIfHTTPError` also rejects non-2xx, so 304 can
        // break merges silently when callers swallow errors.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
        return data
    }

    private static func authorizedJSON(
        url: URL,
        method: String,
        bearerToken: String?,
        body: Data? = nil
    ) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
        return data
    }

    private static func serverErrorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? nil : raw
        }
        if let s = obj["error"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let block = obj["error"] as? [String: Any],
           let msg = block["message"] as? String {
            let t = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let msg = obj["message"] as? String {
            let t = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return nil
    }

    private static func throwIfHTTPError(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg: String = {
                if http.statusCode == 413 {
                    return "The photo is too large for the server. Try again with a smaller image, or ask your host to raise the upload size limit."
                }
                return serverErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            }()
            throw NSError(domain: "MessagingAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// `true` when the API rejected the Bearer token (stale session, wrong token type, rotated `JWT_SECRET`).
    static func isUnauthorizedHTTPError(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == "MessagingAPI" && ns.code == 401
    }

    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    /// `GET /messages/blocks` payloads may use **snake_case** (`first_name`, `avatar_url`, …); OnCuts Node may emit camelCase. This decoder accepts both.
    private static let blocksListJSONDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Inbox list rows may mix camelCase (OnCuts Node) with snake_case (legacy / proxy).
    private static let conversationsListJSONDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// When envelope `Decodable` fails (or one bad row breaks the array), read `data.conversations` via `JSONSerialization` and decode row-by-row.
    private static func parseConversationsFromLooseJSON(_ data: Data) -> [MessagingConversationRowDTO] {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let payload = (top["data"] as? [String: Any]) ?? top
        let rawRows: [Any]?
        if let arr = payload["conversations"] as? [Any] {
            rawRows = arr
        } else if let arr = top["conversations"] as? [Any] {
            rawRows = arr
        } else if let arr = payload["data"] as? [Any] {
            rawRows = arr
        } else {
            rawRows = nil
        }
        guard let rows = rawRows else { return [] }

        var out: [MessagingConversationRowDTO] = []
        out.reserveCapacity(rows.count)
        let rowDecoders = [jsonDecoder, conversationsListJSONDecoder]
        for el in rows {
            guard let dict = el as? [String: Any] else { continue }
            var decoded: MessagingConversationRowDTO?
            if JSONSerialization.isValidJSONObject(dict), let blob = try? JSONSerialization.data(withJSONObject: dict) {
                for decoder in rowDecoders {
                    if let row = try? decoder.decode(MessagingConversationRowDTO.self, from: blob) {
                        decoded = row
                        break
                    }
                }
            }
            if decoded == nil {
                decoded = MessagingConversationRowDTO(jsonObject: dict)
            }
            if let row = decoded {
                out.append(row)
            }
        }
        return out
    }

    private static func decodeConversationRows(from data: Data) throws -> [MessagingConversationRowDTO] {
        let decoders = [jsonDecoder, conversationsListJSONDecoder]
        for decoder in decoders {
            if let env = try? decoder.decode(SuccessEnvelope<ConversationsListDataPayload>.self, from: data),
               let rows = env.data?.conversations {
                return rows
            }
            if let env = try? decoder.decode(SuccessEnvelope<[MessagingConversationRowDTO]>.self, from: data),
               let rows = env.data {
                return rows
            }
            if let rows = try? decoder.decode([MessagingConversationRowDTO].self, from: data) {
                return rows
            }
        }

        let loose = parseConversationsFromLooseJSON(data)
        if !loose.isEmpty {
            return loose
        }

        // Surface the primary decode error when nothing could be parsed.
        _ = try jsonDecoder.decode(SuccessEnvelope<ConversationsListDataPayload>.self, from: data)
        return []
    }

    /// When `JSONDecoder` fails on `users[]` or returns empty rows, read `data.users` / `blockedUserIds` via `JSONSerialization`.
    private static func parseBlockedListFromLooseJSON(_ data: Data) -> (blockedUserIds: [String], users: [MessagingBlockedUserProfile])? {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let payload = (top["data"] as? [String: Any]) ?? top
        let idArrays: [[Any]?] = [
            payload["blockedUserIds"] as? [Any],
            payload["blocked_user_ids"] as? [Any],
        ]
        var blockedUserIds: [String] = []
        for arr in idArrays {
            guard let a = arr else { continue }
            for el in a {
                if let s = el as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { blockedUserIds.append(t) }
                } else if let n = el as? NSNumber {
                    let t = n.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { blockedUserIds.append(t) }
                } else if let i = el as? Int {
                    blockedUserIds.append(String(i))
                }
            }
            if !blockedUserIds.isEmpty { break }
        }
        let rawUsers = payload["users"] as? [Any]
        let userDicts: [[String: Any]] = (rawUsers ?? []).compactMap { $0 as? [String: Any] }
        let users = userDicts.compactMap { MessagingBlockedUserProfile(jsonObject: $0) }
        if blockedUserIds.isEmpty && users.isEmpty { return nil }
        return (blockedUserIds, users)
    }

    // MARK: - Public

    static func fetchConversations(bearerToken: String?) async throws -> [MessagingConversationRowDTO] {
        let data = try await authorizedGET(url: try conversationsBase(), bearerToken: bearerToken)
        return try decodeConversationRows(from: data)
    }

    static func fetchConversationMessages(
        conversationId: String,
        bearerToken: String?
    ) async throws -> (messages: [MessagingMessageDTO], booking: MessagingBookingDTO?, otherUser: MessagingConversationOtherUserDTO?) {
        let data = try await authorizedGET(url: try conversationMessagesURL(id: conversationId), bearerToken: bearerToken)
        if let env = try? jsonDecoder.decode(SuccessEnvelope<ThreadDataPayload>.self, from: data), let d = env.data {
            return (d.messages ?? [], d.booking, d.otherUser)
        }
        if let env = try? jsonDecoder.decode(SuccessEnvelope<[MessagingMessageDTO]>.self, from: data), let arr = env.data {
            return (arr, nil, nil)
        }
        let thread = try jsonDecoder.decode(ThreadDataPayload.self, from: data)
        return (thread.messages ?? [], thread.booking, thread.otherUser)
    }

    /// Resolves `GET /messages/blocks` JSON into display rows (`users[]`, loose fallback, blocked ids-only).
    private static func resolveBlockedMessagingUsersPayload(data: Data) -> [MessagingBlockedUserProfile] {
        let looseBackup = parseBlockedListFromLooseJSON(data)
        let decodePayload: (JSONDecoder) -> BlockedListDataPayload? = { decoder in
            (try? decoder.decode(SuccessEnvelope<BlockedListDataPayload>.self, from: data))?.data
        }

        var profilesResult: [MessagingBlockedUserProfile] = []
        let dOpt = decodePayload(blocksListJSONDecoder) ?? decodePayload(jsonDecoder)

        if let d = dOpt {
            var profiles = d.users ?? []
            var idOrder = d.blockedUserIds ?? []
            if profiles.isEmpty, let lb = looseBackup, !lb.users.isEmpty {
                profiles = lb.users
            }
            if idOrder.isEmpty, let lb = looseBackup, !lb.blockedUserIds.isEmpty {
                idOrder = lb.blockedUserIds
            }
            if !profiles.isEmpty {
                if idOrder.isEmpty {
                    profilesResult = profiles
                } else {
                    var byId: [String: MessagingBlockedUserProfile] = [:]
                    byId.reserveCapacity(profiles.count)
                    for p in profiles {
                        let key = p.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if !key.isEmpty { byId[key] = p }
                    }
                    profilesResult = idOrder.map { rawId in
                        let key = rawId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        return byId[key] ?? MessagingBlockedUserProfile(id: rawId, firstName: nil, lastName: nil, avatarUrl: nil)
                    }
                }
            } else if let ids = d.blockedUserIds, !ids.isEmpty {
                profilesResult = ids.map { MessagingBlockedUserProfile(id: $0, firstName: nil, lastName: nil, avatarUrl: nil) }
            }
        }

        if profilesResult.isEmpty, let lb = looseBackup, !lb.users.isEmpty {
            let idOrder = lb.blockedUserIds
            if idOrder.isEmpty {
                profilesResult = lb.users
            } else {
                var byId: [String: MessagingBlockedUserProfile] = [:]
                byId.reserveCapacity(lb.users.count)
                for p in lb.users {
                    let key = p.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !key.isEmpty { byId[key] = p }
                }
                profilesResult = idOrder.map { rawId in
                    let key = rawId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return byId[key] ?? MessagingBlockedUserProfile(id: rawId, firstName: nil, lastName: nil, avatarUrl: nil)
                }
            }
        }

        if profilesResult.isEmpty {
            if let env = try? blocksListJSONDecoder.decode(SuccessEnvelope<BlockedIdsEnvelope>.self, from: data),
               let ids = env.data?.blockedUserIds {
                profilesResult = ids.map { MessagingBlockedUserProfile(id: $0, firstName: nil, lastName: nil, avatarUrl: nil) }
            } else if let env = try? jsonDecoder.decode(SuccessEnvelope<BlockedIdsEnvelope>.self, from: data),
                      let ids = env.data?.blockedUserIds {
                profilesResult = ids.map { MessagingBlockedUserProfile(id: $0, firstName: nil, lastName: nil, avatarUrl: nil) }
            } else if let env = try? blocksListJSONDecoder.decode(SuccessEnvelope<[String]>.self, from: data), let ids = env.data {
                profilesResult = ids.map { MessagingBlockedUserProfile(id: $0, firstName: nil, lastName: nil, avatarUrl: nil) }
            } else if let env = try? jsonDecoder.decode(SuccessEnvelope<[String]>.self, from: data), let ids = env.data {
                profilesResult = ids.map { MessagingBlockedUserProfile(id: $0, firstName: nil, lastName: nil, avatarUrl: nil) }
            }
        }

        return profilesResult
    }

    /// True when `GET /messages/blocks` returned only ids (no `users[]` row) for this profile.
    private static func profileNeedsUserAPIEnrichment(_ p: MessagingBlockedUserProfile) -> Bool {
        (p.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (p.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (p.displayNameOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (p.avatarUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Fetches `GET …/users/:id` for id-only rows (legacy blocks payload omitting `data.users`).
    private static func enrichBlockedProfilesViaUserAPI(
        profiles: [MessagingBlockedUserProfile],
        bearerToken: String?
    ) async -> [MessagingBlockedUserProfile] {
        let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { return profiles }
        var out = profiles
        for i in out.indices {
            guard profileNeedsUserAPIEnrichment(out[i]) else { continue }
            let id = out[i].id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            do {
                let u = try await UserProfileAPI.fetchProfile(userId: id, bearerToken: token)
                out[i] = MessagingBlockedUserProfile(blockedUserId: id, userProfile: u)
            } catch {
                continue
            }
        }
        return out
    }

    static func fetchBlockedMessagingUsers(bearerToken: String?) async throws -> [MessagingBlockedUserProfile] {
        let data = try await authorizedGET(url: try blocksListURL(), bearerToken: bearerToken)
        let profiles = resolveBlockedMessagingUsersPayload(data: data)
        return await enrichBlockedProfilesViaUserAPI(profiles: profiles, bearerToken: bearerToken)
    }

    static func fetchBlockedMessagingUserIds(bearerToken: String?) async throws -> [String] {
        let rows = try await fetchBlockedMessagingUsers(bearerToken: bearerToken)
        return rows.map(\.id)
    }

    static func blockMessagingUser(blockedUserId: String, bearerToken: String?) async throws {
        let trimmed = blockedUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let body = try JSONSerialization.data(withJSONObject: ["blockedUserId": trimmed], options: [])
        _ = try await authorizedJSON(url: try blockUserURL(), method: "POST", bearerToken: bearerToken, body: body)
    }

    static func unblockMessagingUser(blockedUserId: String, bearerToken: String?) async throws {
        let trimmed = blockedUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let body = try JSONSerialization.data(withJSONObject: ["blockedUserId": trimmed], options: [])
        var lastNotFound: Error?
        for url in [try unblockUserURL(), try unblockUserNestedURL()] {
            do {
                _ = try await authorizedJSON(url: url, method: "POST", bearerToken: bearerToken, body: body)
                return
            } catch {
                let ns = error as NSError
                if ns.domain == "MessagingAPI", ns.code == 404 {
                    lastNotFound = error
                    continue
                }
                throw error
            }
        }
        do {
            _ = try await authorizedJSON(
                url: try unblockUserDeleteURL(blockedUserId: trimmed),
                method: "DELETE",
                bearerToken: bearerToken,
                body: nil
            )
        } catch {
            let ns = error as NSError
            if ns.domain == "MessagingAPI", ns.code == 404, let lastNotFound {
                throw lastNotFound
            }
            throw error
        }
    }

    static func reportConversationContent(
        conversationId: String,
        reason: String,
        details: String?,
        messageId: String?,
        reportedUserId: String?,
        bearerToken: String?
    ) async throws {
        var payload: [String: Any] = ["reason": reason]
        if let details, !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["details"] = details
        }
        if let messageId, !messageId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["messageId"] = messageId
        }
        if let reportedUserId, !reportedUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["reportedUserId"] = reportedUserId
        }
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        _ = try await authorizedJSON(url: try conversationReportURL(conversationId: conversationId), method: "POST", bearerToken: bearerToken, body: body)
    }

    static func markConversationRead(conversationId: String, bearerToken: String?) async throws {
        _ = try await authorizedJSON(url: try conversationReadURL(id: conversationId), method: "PUT", bearerToken: bearerToken)
    }

    static func deleteConversation(conversationId: String, bearerToken: String?) async throws {
        _ = try await authorizedJSON(url: try conversationURL(id: conversationId), method: "DELETE", bearerToken: bearerToken)
    }

    /// Consumer/barber cancel: `DELETE /api/v1/bookings-simple/:id` — cancels the booking and removes the linked conversation when applicable.
    static func cancelBookingSimple(bookingId: String, bearerToken: String?) async throws {
        let enc = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let url = URL(string: base + "/bookings-simple/\(enc)") else {
            throw URLError(.badURL)
        }
        _ = try await authorizedJSON(url: url, method: "DELETE", bearerToken: bearerToken, body: nil)
    }

    static func sendTextMessage(conversationId: String, text: String, bearerToken: String?) async throws -> MessagingMessageDTO? {
        let url = try conversationMessagesURL(id: conversationId)
        let body = try JSONSerialization.data(withJSONObject: ["content": text], options: [])
        let data = try await authorizedJSON(url: url, method: "POST", bearerToken: bearerToken, body: body)
        if let env = try? jsonDecoder.decode(SuccessEnvelope<MessageSinglePayload>.self, from: data), let m = env.data?.message {
            return m
        }
        if let env = try? jsonDecoder.decode(SuccessEnvelope<MessagingMessageDTO>.self, from: data), let m = env.data {
            return m
        }
        return nil
    }

    /// Persists an image message after ``uploadChatImage`` (web parity: upload file, then POST message row).
    static func sendImageMessage(
        conversationId: String,
        mediaUrl: String,
        caption: String? = nil,
        bearerToken: String?
    ) async throws -> MessagingMessageDTO? {
        let url = try conversationMessagesURL(id: conversationId)
        let trimmed = mediaUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let payload: [String: Any] = [
            "content": content,
            "messageType": "image",
            "message_type": "image",
            "mediaUrl": trimmed,
            "media_url": trimmed,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        let data = try await authorizedJSON(url: url, method: "POST", bearerToken: bearerToken, body: body)
        if let env = try? jsonDecoder.decode(SuccessEnvelope<MessageSinglePayload>.self, from: data), let m = env.data?.message {
            return m
        }
        if let env = try? jsonDecoder.decode(SuccessEnvelope<MessagingMessageDTO>.self, from: data), let m = env.data {
            return m
        }
        return nil
    }

    /// Multipart image upload; returns absolute `mediaUrl` string from `POST /upload/chat-image`.
    static func uploadChatImage(imageData: Data, mimeType: String, bearerToken: String?) async throws -> String {
        let url = try uploadURL()
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        let filename = mimeType.contains("png") ? "chat.png" : "chat.jpg"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
        if let env = try? jsonDecoder.decode(SuccessEnvelope<UploadPayload>.self, from: data), let p = env.data {
            if let u = p.mediaUrl ?? p.url, !u.isEmpty { return u }
        }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let nested = dict["data"] as? [String: Any] {
                if let u = nested["media_url"] as? String ?? nested["mediaUrl"] as? String ?? nested["url"] as? String,
                   !u.isEmpty {
                    return u
                }
            }
            if let u = dict["media_url"] as? String ?? dict["mediaUrl"] as? String ?? dict["url"] as? String, !u.isEmpty {
                return u
            }
        }
        throw NSError(domain: "MessagingAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload response missing media URL"])
    }
    
    /// Fetch the messaging user ID for a barber given their **barber profile** id (`barbers.id`).
    /// OnCuts exposes this on `GET /api/v1/barbers/:id` as `data.user_id` (not a separate `/users/barber/...` route).
    static func fetchBarberMessagingUserId(barberProfileId: String, bearerToken: String?) async throws -> String? {
        let base = AppConfiguration.messagingAPIRootTrimmed
        let encoded = barberProfileId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? barberProfileId
        guard let url = URL(string: "\(base)/barbers/\(encoded)") else {
            throw URLError(.badURL)
        }

        let data = try await authorizedGET(url: url, bearerToken: bearerToken)

        struct BarberProfileUserPayload: Decodable {
            let userId: String?
            let user_id: String?

            var resolvedUserId: String? {
                let a = userId?.trimmingCharacters(in: .whitespacesAndNewlines)
                let b = user_id?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let a, !a.isEmpty { return a }
                if let b, !b.isEmpty { return b }
                return nil
            }
        }

        if let response = try? jsonDecoder.decode(SuccessEnvelope<BarberProfileUserPayload>.self, from: data) {
            return response.data?.resolvedUserId
        }

        if let response = try? jsonDecoder.decode(BarberProfileUserPayload.self, from: data) {
            return response.resolvedUserId
        }

        return nil
    }
    
    /// Start a booking conversation with a barber (`POST /api/v1/messages/conversations`).
    static func startBookingConversation(
        otherUserId: String,
        bookingId: String,
        serviceName: String?,
        servicePriceUsd: Double?,
        scheduledTime: String?,
        location: String?,
        notes: String?,
        barberName: String?,
        barberProfilePicture: String?,
        bearerToken: String?
    ) async throws -> String {
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let url = URL(string: "\(base)/messages/conversations") else {
            throw URLError(.badURL)
        }

        var payload: [String: Any] = [
            "otherUserId": otherUserId,
            "bookingId": bookingId
        ]

        if let serviceName = serviceName { payload["serviceName"] = serviceName }
        // Backend `message.routes` expects `servicePrice` (see `bookingContext.servicePrice`).
        if let servicePriceUsd = servicePriceUsd { payload["servicePrice"] = servicePriceUsd }
        if let scheduledTime = scheduledTime { payload["scheduledTime"] = scheduledTime }
        if let location = location { payload["location"] = location }
        if let notes = notes { payload["notes"] = notes }
        if let barberName = barberName { payload["barberName"] = barberName }
        if let barberProfilePicture = barberProfilePicture { payload["barberProfilePicture"] = barberProfilePicture }

        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await authorizedJSON(url: url, method: "POST", bearerToken: bearerToken, body: body)

        if let nested = try? jsonDecoder.decode(SuccessEnvelope<StartConversationNestedPayload>.self, from: data),
           let conv = nested.data?.conversation,
           let raw = conv.id ?? conv.conversation_id {
            return raw.stringValue
        }

        if let nested = try? jsonDecoder.decode(StartConversationNestedPayload.self, from: data),
           let conv = nested.conversation,
           let raw = conv.id ?? conv.conversation_id {
            return raw.stringValue
        }

        if let response = try? jsonDecoder.decode(SuccessEnvelope<StartConversationFlatPayload>.self, from: data),
           let cid = response.data?.resolvedId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cid.isEmpty {
            return cid
        }

        if let response = try? jsonDecoder.decode(StartConversationFlatPayload.self, from: data),
           let cid = response.resolvedId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cid.isEmpty {
            return cid
        }

        throw NSError(domain: "MessagingAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not parse conversation ID from response"])
    }
    
    /// Fetch unread message count for the current user
    static func fetchUnreadMessageCount(bearerToken: String?) async throws -> Int {
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let url = URL(string: "\(base)/messages/unread-count") else {
            throw URLError(.badURL)
        }
        
        let data = try await authorizedGET(url: url, bearerToken: bearerToken)
        
        struct UnreadCountResponse: Decodable {
            let count: Int?
            let unreadCount: Int?
            let unread_count: Int?
            
            var resolvedCount: Int {
                count ?? unreadCount ?? unread_count ?? 0
            }
        }
        
        if let response = try? jsonDecoder.decode(SuccessEnvelope<UnreadCountResponse>.self, from: data) {
            return response.data?.resolvedCount ?? 0
        }
        
        if let response = try? jsonDecoder.decode(UnreadCountResponse.self, from: data) {
            return response.resolvedCount
        }
        
        // Fallback: try to decode as direct integer
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let count = dict["count"] as? Int { return count }
            if let count = dict["unreadCount"] as? Int { return count }
            if let count = dict["unread_count"] as? Int { return count }
        }
        
        return 0
    }
}

extension MessagingBlockedUserProfile {
    /// Maps `GET …/users/:id` into a blocked row when `/messages/blocks` omits `data.users`.
    fileprivate init(blockedUserId: String, userProfile: UserProfileAPIModel) {
        let f = userProfile.first_name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        let l = userProfile.last_name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        let av = userProfile.profile_picture_url.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        var override: String?
        if f == nil, l == nil {
            let parts = userProfile.email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
            if let head = parts.first {
                override = String(head).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
        }
        self.init(
            id: blockedUserId,
            firstName: f,
            lastName: l,
            avatarUrl: av,
            displayNameOverride: override
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
