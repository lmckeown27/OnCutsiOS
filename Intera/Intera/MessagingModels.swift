//
//  MessagingModels.swift
//  Intera
//
//  Decodable DTOs for CampusCuts messaging REST + socket payloads (snake_case JSON).
//

import Foundation

// MARK: - Thread / booking context

struct MessagingBookingDTO: Decodable, Sendable, Hashable {
    /// CampusCuts `bookings.id` (UUID) when the API includes it — required for `DELETE /bookings-simple/:id`.
    let id: String?
    let status: String?
    let serviceName: String?
    let scheduledTime: String?
    let location: String?
    let barberId: String?
    let barberName: String?
    let barberBusinessName: String?
    let barberProfileImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case serviceName = "service_name"
        case scheduledTime = "scheduled_time"
        case location
        case barberId = "barber_id"
        case barberName = "barber_name"
        case barberBusinessName = "barber_business_name"
        case barberProfileImageUrl = "barber_profile_image_url"
        /// Alternate keys some deployments use for the barber’s uploaded / listing photo.
        case barberProfilePhotoUrl = "barber_profile_photo_url"
        case barberAvatarUrl = "barber_avatar_url"
        case providerImageUrl = "provider_image_url"
        case avatarUrl = "avatar_url"
        case bookingId = "booking_id"
    }

    /// Express often returns **camelCase** (`serviceName`); web clients may use **snake_case** (`service_name`).
    private enum AltCodingKeys: String, CodingKey {
        case id, status, location, notes
        case serviceName, scheduledTime, barberId, barberName
        case barberBusinessName, barberProfileImageUrl
        case barberProfilePhotoUrl, barberAvatarUrl, providerImageUrl, avatarUrl
        case bookingId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try? decoder.container(keyedBy: AltCodingKeys.self)

        if let s = try? c.decode(String.self, forKey: .id), !s.isEmpty {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else if let s = try? c.decode(String.self, forKey: .bookingId), !s.isEmpty {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .bookingId) {
            id = String(i)
        } else if let s = try? alt?.decode(String.self, forKey: .id), !s.isEmpty {
            id = s
        } else if let i = try? alt?.decode(Int.self, forKey: .id) {
            id = String(i)
        } else if let s = try? alt?.decode(String.self, forKey: .bookingId), !s.isEmpty {
            id = s
        } else {
            id = nil
        }

        status = try c.decodeIfPresent(String.self, forKey: .status) ?? (try? alt?.decodeIfPresent(String.self, forKey: .status)) ?? nil
        serviceName = try c.decodeIfPresent(String.self, forKey: .serviceName) ?? (try? alt?.decodeIfPresent(String.self, forKey: .serviceName)) ?? nil
        scheduledTime = try c.decodeIfPresent(String.self, forKey: .scheduledTime) ?? (try? alt?.decodeIfPresent(String.self, forKey: .scheduledTime)) ?? nil
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? (try? alt?.decodeIfPresent(String.self, forKey: .location)) ?? nil
        barberName = try c.decodeIfPresent(String.self, forKey: .barberName) ?? (try? alt?.decodeIfPresent(String.self, forKey: .barberName)) ?? nil
        barberBusinessName = try c.decodeIfPresent(String.self, forKey: .barberBusinessName)
            ?? (try? alt?.decodeIfPresent(String.self, forKey: .barberBusinessName))
            ?? nil
        let primaryProfileImage = try c.decodeIfPresent(String.self, forKey: .barberProfileImageUrl)
            ?? (try? alt?.decodeIfPresent(String.self, forKey: .barberProfileImageUrl))
        let altProfileImages: [String?] = [
            try c.decodeIfPresent(String.self, forKey: .barberProfilePhotoUrl),
            try c.decodeIfPresent(String.self, forKey: .barberAvatarUrl),
            try c.decodeIfPresent(String.self, forKey: .providerImageUrl),
            try c.decodeIfPresent(String.self, forKey: .avatarUrl),
            try? alt?.decodeIfPresent(String.self, forKey: .barberProfilePhotoUrl),
            try? alt?.decodeIfPresent(String.self, forKey: .barberAvatarUrl),
            try? alt?.decodeIfPresent(String.self, forKey: .providerImageUrl),
            try? alt?.decodeIfPresent(String.self, forKey: .avatarUrl),
        ]
        barberProfileImageUrl = MessagingNonEmptyURL.first(primaryProfileImage, altProfileImages)

        if let s = try? c.decode(String.self, forKey: .barberId) {
            barberId = s
        } else if let i = try? c.decode(Int.self, forKey: .barberId) {
            barberId = String(i)
        } else if let s = try? alt?.decode(String.self, forKey: .barberId) {
            barberId = s
        } else if let i = try? alt?.decode(Int.self, forKey: .barberId) {
            barberId = String(i)
        } else {
            barberId = nil
        }
    }
    
    /// Memberwise initializer for creating DTOs programmatically (e.g., from `BookingChatContext`).
    init(
        id: String?,
        status: String?,
        serviceName: String?,
        scheduledTime: String?,
        location: String?,
        barberId: String?,
        barberName: String?,
        barberBusinessName: String?,
        barberProfileImageUrl: String?
    ) {
        self.id = id
        self.status = status
        self.serviceName = serviceName
        self.scheduledTime = scheduledTime
        self.location = location
        self.barberId = barberId
        self.barberName = barberName
        self.barberBusinessName = barberBusinessName
        self.barberProfileImageUrl = barberProfileImageUrl
    }
}

/// Shared inbox / booking JSON coalescing for image URLs.
enum MessagingNonEmptyURL {
    static func first(_ primary: String?, _ extras: [String?]) -> String? {
        for raw in [primary] + extras {
            let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return t }
        }
        return nil
    }
}

/// Trailing inbox / thread list line: provider role + booked service (replaces “Last active …”).
enum MessagingProviderRoleLine {
    /// CampusCuts conversations are with barbers; no separate occupation field on `MessagingBookingDTO`.
    static let defaultOccupationTitle = "Barber"

    /// Title-style line such as `Barber · Haircut` (no backend `SHOUTING_CASE`).
    static func occupationAndServicePresentable(booking: MessagingBookingDTO?) -> String {
        let occOut = occupationTitle(booking: booking)
        let svcRaw = (booking?.serviceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if svcRaw.isEmpty {
            return occOut
        }
        return "\(occOut) · \(Self.presentableWordLine(svcRaw))"
    }

    /// Provider kind tag only (e.g. `Barber`) — browse card pill / thread occupation without the booked service.
    static func occupationTitle(booking: MessagingBookingDTO? = nil) -> String {
        _ = booking
        let occ = defaultOccupationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return occ.isEmpty ? defaultOccupationTitle : presentableWordLine(occ)
    }

    private static func presentableWordLine(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return raw }
        if t == t.uppercased() {
            return t.lowercased().localizedCapitalized
        }
        return t
    }

    /// One booking field, e.g. API `HAIRCUT` → `Haircut`.
    static func presentableServiceName(_ raw: String?) -> String {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "—" }
        return presentableWordLine(t)
    }
}

/// Row from `GET …/messages/blocks` (`data.users`) for profile / unblock UI.
struct MessagingBlockedUserProfile: Identifiable, Hashable, Sendable {
    let id: String
    var firstName: String?
    var lastName: String?
    /// CampusCuts `users."displayName"` when `first_name` / `last_name` are empty (e.g. Apple relay sign-up).
    var displayNameOverride: String?
    var avatarUrl: String?

    var displayName: String {
        let f = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let l = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [f, l].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        let o = (displayNameOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !o.isEmpty { return o }
        return "Messaging user"
    }

    init(id: String, firstName: String?, lastName: String?, avatarUrl: String?, displayNameOverride: String? = nil) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.displayNameOverride = displayNameOverride
        self.avatarUrl = avatarUrl
    }
}

extension MessagingBlockedUserProfile: Decodable {
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case firstName
        case first_name
        case lastName
        case last_name
        case avatarUrl
        case avatar_url
        case profilePicture
        case profile_picture
        case profilePictureUrl
        case profile_picture_url
        case displayName
        case display_name
        case name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let idResolved: String
        if let s = try c.decodeIfPresent(String.self, forKey: .id)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            idResolved = s
        } else if let i = try c.decodeIfPresent(Int.self, forKey: .id) {
            idResolved = String(i)
        } else if let s = try c.decodeIfPresent(String.self, forKey: .userId)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            idResolved = s
        } else if let i = try c.decodeIfPresent(Int.self, forKey: .userId) {
            idResolved = String(i)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "blocked user id missing"))
        }
        id = idResolved

        func trimmed(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }

        // Support both camelCase JSON and explicit snake_case keys (when not using `keyDecodingStrategy`).
        var fn = trimmed(try c.decodeIfPresent(String.self, forKey: .firstName))
        if fn == nil { fn = trimmed(try c.decodeIfPresent(String.self, forKey: .first_name)) }
        firstName = fn
        var ln = trimmed(try c.decodeIfPresent(String.self, forKey: .lastName))
        if ln == nil { ln = trimmed(try c.decodeIfPresent(String.self, forKey: .last_name)) }
        lastName = ln
        var dn = trimmed(try c.decodeIfPresent(String.self, forKey: .displayName))
        if dn == nil { dn = trimmed(try c.decodeIfPresent(String.self, forKey: .display_name)) }
        if dn == nil { dn = trimmed(try c.decodeIfPresent(String.self, forKey: .name)) }
        displayNameOverride = dn
        var av = trimmed(try c.decodeIfPresent(String.self, forKey: .avatarUrl))
        if av == nil { av = trimmed(try c.decodeIfPresent(String.self, forKey: .avatar_url)) }
        if av == nil { av = trimmed(try c.decodeIfPresent(String.self, forKey: .profilePicture)) }
        if av == nil { av = trimmed(try c.decodeIfPresent(String.self, forKey: .profile_picture)) }
        if av == nil { av = trimmed(try c.decodeIfPresent(String.self, forKey: .profilePictureUrl)) }
        if av == nil { av = trimmed(try c.decodeIfPresent(String.self, forKey: .profile_picture_url)) }
        avatarUrl = av
    }
}

extension MessagingBlockedUserProfile {
    /// Builds from `JSONSerialization` dictionaries when strict `Decodable` drops rows or the whole payload.
    init?(jsonObject: [String: Any]) {
        func trimmed(_ any: Any?) -> String? {
            if let s = any as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            if let n = any as? NSNumber {
                let t = n.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            if let i = any as? Int { return String(i) }
            return nil
        }
        let idRaw =
            trimmed(jsonObject["id"])
            ?? trimmed(jsonObject["userId"])
            ?? trimmed(jsonObject["user_id"])
        guard let id = idRaw, !id.isEmpty else { return nil }
        self.init(
            id: id,
            firstName: trimmed(jsonObject["firstName"]) ?? trimmed(jsonObject["first_name"]),
            lastName: trimmed(jsonObject["lastName"]) ?? trimmed(jsonObject["last_name"]),
            avatarUrl: trimmed(jsonObject["avatarUrl"])
                ?? trimmed(jsonObject["avatar_url"])
                ?? trimmed(jsonObject["profilePicture"])
                ?? trimmed(jsonObject["profile_picture"])
                ?? trimmed(jsonObject["profilePictureUrl"])
                ?? trimmed(jsonObject["profile_picture_url"]),
            displayNameOverride: trimmed(jsonObject["displayName"])
                ?? trimmed(jsonObject["display_name"])
                ?? trimmed(jsonObject["name"])
        )
    }
}

/// Counterparty on `GET …/messages/conversations` — holds **displayName** when `booking.barber_name` cache is empty.
struct MessagingConversationOtherUserDTO: Decodable, Sendable {
    /// CampusCuts `otherUser.id` (messaging user UUID).
    let id: String?
    let displayName: String?
    let firstName: String?
    let lastName: String?
    /// API: `profilePicture` (user `avatarUrl`).
    let profilePicture: String?

    private struct BarberInfoBlock: Decodable, Sendable {
        let displayName: String?
        let profilePicture: String?
        let profilePictureSnake: String?
        let avatarUrl: String?
        let avatarUrlSnake: String?
        let profileImageUrl: String?
        let profileImageUrlSnake: String?
        let imageUrl: String?
        let photoUrl: String?

        enum CodingKeys: String, CodingKey {
            case displayName
            case profilePicture
            case profilePictureSnake = "profile_picture"
            case avatarUrl
            case avatarUrlSnake = "avatar_url"
            case profileImageUrl
            case profileImageUrlSnake = "profile_image_url"
            case imageUrl
            case photoUrl
        }

        init(from decoder: Decoder) throws {
            let b = try decoder.container(keyedBy: CodingKeys.self)
            displayName = try b.decodeIfPresent(String.self, forKey: .displayName)
            profilePicture = try b.decodeIfPresent(String.self, forKey: .profilePicture)
            profilePictureSnake = try b.decodeIfPresent(String.self, forKey: .profilePictureSnake)
            avatarUrl = try b.decodeIfPresent(String.self, forKey: .avatarUrl)
            avatarUrlSnake = try b.decodeIfPresent(String.self, forKey: .avatarUrlSnake)
            profileImageUrl = try b.decodeIfPresent(String.self, forKey: .profileImageUrl)
            profileImageUrlSnake = try b.decodeIfPresent(String.self, forKey: .profileImageUrlSnake)
            imageUrl = try b.decodeIfPresent(String.self, forKey: .imageUrl)
            photoUrl = try b.decodeIfPresent(String.self, forKey: .photoUrl)
        }

        func firstNonEmptyImageURL() -> String? {
            MessagingNonEmptyURL.first(
                nil,
                [
                    profilePicture, profilePictureSnake, avatarUrl, avatarUrlSnake,
                    profileImageUrl, profileImageUrlSnake, imageUrl, photoUrl,
                ]
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case firstName
        case lastName
        case barberInfo
        case profilePicture
        case profilePictureSnake = "profile_picture"
        case avatarUrl
        case avatarUrlSnake = "avatar_url"
        case profileImageUrl
        case profileImageUrlSnake = "profile_image_url"
        case imageUrl
        case photoUrl
    }

    private static let ws = CharacterSet.whitespacesAndNewlines

    /// First non-empty string among alternate API keys (keeps the `init(from:)` expression small for the type checker).
    private static func decodeRootProfilePicture(from c: KeyedDecodingContainer<CodingKeys>) throws -> String? {
        let keys: [CodingKeys] = [
            .profilePicture, .profilePictureSnake, .avatarUrl, .avatarUrlSnake,
            .profileImageUrl, .profileImageUrlSnake, .imageUrl, .photoUrl,
        ]
        for key in keys {
            guard let raw = try c.decodeIfPresent(String.self, forKey: key) else { continue }
            let t = raw.trimmingCharacters(in: ws)
            if !t.isEmpty { return raw }
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id), !s.isEmpty {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            id = nil
        }
        var dn = try c.decodeIfPresent(String.self, forKey: .displayName)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        var pic = try Self.decodeRootProfilePicture(from: c)

        if let block = try c.decodeIfPresent(BarberInfoBlock.self, forKey: .barberInfo) {
            let dnEmpty = dn.map { $0.trimmingCharacters(in: Self.ws).isEmpty } ?? true
            if dnEmpty,
               let inner = block.displayName?.trimmingCharacters(in: Self.ws),
               !inner.isEmpty {
                dn = inner
            }
            let picEmpty = pic.map { $0.trimmingCharacters(in: Self.ws).isEmpty } ?? true
            if picEmpty, let fromBlock = block.firstNonEmptyImageURL() {
                pic = fromBlock
            }
        }
        displayName = dn
        let trimmedPic = (pic ?? "").trimmingCharacters(in: Self.ws)
        profilePicture = trimmedPic.nilIfEmpty
    }

    func resolvedDisplayName() -> String? {
        if let d = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { return d }
        let f = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let l = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [f, l].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? nil : full
    }
}

struct MessagingMessageDTO: Decodable, Sendable {
    let idString: String?
    let conversationId: String?
    let senderId: String?
    let senderRole: String?
    let content: String?
    let mediaUrl: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case senderRole = "sender_role"
        case content
        case mediaUrl = "media_url"
        case createdAt = "created_at"
    }

    /// Express message rows often use **camelCase** (`senderId`, `createdAt`).
    private enum AltCodingKeys: String, CodingKey {
        case id, content
        case conversationId, senderId, mediaUrl, createdAt, senderRole
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try? decoder.container(keyedBy: AltCodingKeys.self)

        if let i = try? c.decode(Int.self, forKey: .id) {
            idString = String(i)
        } else if let s = try c.decodeIfPresent(String.self, forKey: .id) {
            idString = s
        } else if let i = try? alt?.decode(Int.self, forKey: .id) {
            idString = String(i)
        } else {
            idString = try? alt?.decodeIfPresent(String.self, forKey: .id)
        }

        // POST /messages/... often returns numeric `conversation_id` (e.g. 388); String-only decode would throw and drop the whole DTO.
        conversationId = Self.decodeStringOrInt(c, .conversationId) ?? Self.decodeStringOrIntAlt(alt, .conversationId)
        senderId = Self.decodeStringOrInt(c, .senderId) ?? Self.decodeStringOrIntAlt(alt, .senderId)
        senderRole = try c.decodeIfPresent(String.self, forKey: .senderRole) ?? (try? alt?.decodeIfPresent(String.self, forKey: .senderRole)) ?? nil
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? (try? alt?.decodeIfPresent(String.self, forKey: .content)) ?? nil
        mediaUrl = try c.decodeIfPresent(String.self, forKey: .mediaUrl) ?? (try? alt?.decodeIfPresent(String.self, forKey: .mediaUrl)) ?? nil
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? (try? alt?.decodeIfPresent(String.self, forKey: .createdAt)) ?? nil
    }

    private static func decodeStringOrInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
        return nil
    }

    private static func decodeStringOrIntAlt(_ alt: KeyedDecodingContainer<AltCodingKeys>?, _ key: AltCodingKeys) -> String? {
        guard let alt else { return nil }
        if let s = try? alt.decode(String.self, forKey: key) { return s }
        if let i = try? alt.decode(Int.self, forKey: key) { return String(i) }
        return nil
    }

    init(
        idString: String?,
        conversationId: String?,
        senderId: String?,
        senderRole: String?,
        content: String?,
        mediaUrl: String?,
        createdAt: String?
    ) {
        self.idString = idString
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderRole = senderRole
        self.content = content
        self.mediaUrl = mediaUrl
        self.createdAt = createdAt
    }

    static func syntheticImageMessage(mediaUrl: String, senderId: String) -> MessagingMessageDTO {
        MessagingMessageDTO(
            idString: UUID().uuidString,
            conversationId: nil,
            senderId: senderId,
            senderRole: nil,
            content: nil,
            mediaUrl: mediaUrl,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    func stableId(fallbackIndex: Int) -> String {
        if let idString, !idString.isEmpty { return idString }
        return "tmp-\(fallbackIndex)-\(UUID().uuidString.prefix(8))"
    }
    
    /// One-line preview for inbox list (text or "📷 Photo").
    var inboxPreviewLine: String {
        if let text = content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        if mediaUrl != nil {
            return "📷 Photo"
        }
        return "New message"
    }
}

struct MessagingConversationRowDTO: Decodable, Sendable, Identifiable {
    let id: String
    let booking: MessagingBookingDTO?
    let otherUser: MessagingConversationOtherUserDTO?
    let lastMessagePreview: String?
    /// Messaging user id of the latest message’s sender when `lastMessage` is an object (`senderId` from CampusCuts list API).
    let lastMessageSenderId: String?
    let updatedAt: String?
    /// When `0`, treat thread as fully read for inbox row dimming (when API sends it).
    let unreadCount: Int?

    /// Inbox / legacy: `last_message_preview`, `updated_at`. CampusCuts list API: `lastMessage: { content }`, `createdAt`.
    private enum CodingKeys: String, CodingKey {
        case id
        case booking
        case otherUser
        case lastMessagePreview = "last_message_preview"
        case updatedAt = "updated_at"
        case lastMessage
        case createdAt
        case unreadCount
        case unread_count
    }

    private struct LastMessageBlock: Decodable, Sendable {
        let content: String?
        let senderId: String?

        private enum NestedKeys: String, CodingKey {
            case content
            case senderId
            case sender_id
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: NestedKeys.self)
            content = try c.decodeIfPresent(String.self, forKey: .content)
            if let s = try c.decodeIfPresent(String.self, forKey: .senderId) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                senderId = t.isEmpty ? nil : t
            } else if let s = try c.decodeIfPresent(String.self, forKey: .sender_id) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                senderId = t.isEmpty ? nil : t
            } else if let i = try c.decodeIfPresent(Int.self, forKey: .senderId) {
                senderId = String(i)
            } else if let i = try c.decodeIfPresent(Int.self, forKey: .sender_id) {
                senderId = String(i)
            } else {
                senderId = nil
            }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else if let s = try c.decodeIfPresent(String.self, forKey: .id), !s.isEmpty {
            id = s
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "conversation id missing"))
        }
        booking = try c.decodeIfPresent(MessagingBookingDTO.self, forKey: .booking)
        otherUser = try c.decodeIfPresent(MessagingConversationOtherUserDTO.self, forKey: .otherUser)
        if let flat = try c.decodeIfPresent(String.self, forKey: .lastMessagePreview) {
            lastMessagePreview = flat.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            lastMessageSenderId = nil
        } else if let block = try c.decodeIfPresent(LastMessageBlock.self, forKey: .lastMessage) {
            lastMessagePreview = block.content?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            lastMessageSenderId = block.senderId
        } else {
            lastMessagePreview = nil
            lastMessageSenderId = nil
        }
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? c.decodeIfPresent(String.self, forKey: .createdAt)
        if let u = try c.decodeIfPresent(Int.self, forKey: .unreadCount) {
            unreadCount = u
        } else {
            unreadCount = try c.decodeIfPresent(Int.self, forKey: .unread_count)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Inbox list copy

extension MessagingConversationRowDTO {
    /// List row title: prefer cached booking barber fields, then API **`otherUser.displayName`** (filled from the joined user even when `conversations.barber_name` is null).
    var inboxResolvedProviderTitle: String {
        if let n = booking?.inboxProviderNameIfKnown { return n }
        if let n = otherUser?.resolvedDisplayName() { return n }
        return "Conversation"
    }

    /// Barber listing / booking snapshot first, then counterparty user avatar (`otherUser` merges `barberInfo` + alternate JSON keys in decode).
    var inboxCounterpartyAvatarURLString: String? {
        MessagingNonEmptyURL.first(booking?.barberProfileImageUrl, [otherUser?.profilePicture])
    }
}

extension MessagingBookingDTO {
    /// Terminal / past-continuum booking statuses (aligns with bookings timeline “Past” lane).
    var inboxRowIsTerminalPastContinuum: Bool {
        let s = (status ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        return [
            "COMPLETED", "PAID", "CANCELLED", "REJECTED", "DECLINED", "REFUNDED", "NO_SHOW",
        ].contains(s)
    }

    /// Business or barber name from the booking blob when the server sent it.
    var inboxProviderNameIfKnown: String? {
        let business = (barberBusinessName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !business.isEmpty { return business }
        let name = (barberName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return nil
    }

    /// Meeting place for inbox row; omits empty and API placeholder **TBD**.
    var inboxLocationDisplayLine: String? {
        let loc = (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !loc.isEmpty else { return nil }
        if loc.caseInsensitiveCompare("TBD") == .orderedSame { return nil }
        return loc
    }

    /// Service and status between the provider name and the message preview (Pacific **date/time** is shown on the occupation row instead to avoid duplication).
    var inboxBookingContextSubtitle: String? {
        var segments: [String] = []
        if let s = serviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            segments.append(s)
        }
        if let st = status?.trimmingCharacters(in: .whitespacesAndNewlines), !st.isEmpty {
            segments.append(Self.inboxPrettyBookingStatus(st))
        }
        if segments.isEmpty { return nil }
        return segments.joined(separator: " · ")
    }

    /// Short Pacific date/time for inbox (e.g. `Apr 2 · 9:30am`), same formatter as the former subtitle segment.
    var inboxCompactScheduledDisplay: String? {
        let raw = scheduledTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return BookingPacificSchedule.compactDisplayScheduledTime(raw)
    }

    /// Human-readable booking status for inbox / thread chrome (API often sends `PENDING`, `ACCEPTED`, etc.).
    static func inboxPrettyBookingStatus(_ raw: String) -> String {
        switch raw.uppercased() {
        case "PENDING": return "Pending"
        case "ACCEPTED": return "Confirmed"
        case "COMPLETED": return "Completed"
        case "PAID": return "Paid"
        case "CANCELLED", "CANCELED": return "Cancelled"
        case "REJECTED", "DECLINED": return "Declined"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Socket

struct MessagingSocketNewMessagePayload: Decodable, Sendable {
    let conversationId: String?
    let message: MessagingMessageDTO?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case message
    }

    private enum EnvelopeCamelKeys: String, CodingKey {
        case conversationId
        case message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var resolvedConversationId: String?
        if let s = try? c.decode(String.self, forKey: .conversationId) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedConversationId = t.isEmpty ? nil : t
        } else if let i = try? c.decode(Int.self, forKey: .conversationId) {
            resolvedConversationId = String(i)
        }

        // Some gateways / older emits use camelCase at the envelope root only.
        if resolvedConversationId == nil || resolvedConversationId?.isEmpty == true {
            if let alt = try? decoder.container(keyedBy: EnvelopeCamelKeys.self) {
                if let s = try? alt.decode(String.self, forKey: .conversationId) {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    resolvedConversationId = t.isEmpty ? nil : t
                } else if let i = try? alt.decode(Int.self, forKey: .conversationId) {
                    resolvedConversationId = String(i)
                }
            }
        }

        conversationId = resolvedConversationId
        message = try c.decodeIfPresent(MessagingMessageDTO.self, forKey: .message)
    }
}

// MARK: - UI models

struct ChatThreadMessage: Identifiable, Equatable {
    let id: String
    /// Server `messages.id` when known (for moderation reports). Nil for optimistic / synthetic rows.
    let serverMessageIdForReport: String?
    var clientUUID: UUID?
    let senderId: String
    let isFromCurrentUser: Bool
    let text: String
    let mediaUrl: URL?
    let createdAt: Date
    var uploadProgress: Double?

    var isPendingUpload: Bool { uploadProgress != nil }
}

struct BookingChatContext: Equatable {
    let statusNormalized: String
    let serviceName: String
    let scheduledTimeRaw: String
    let location: String?
    let barberId: String
    let barberName: String
    let barberImageUrl: String?
    /// `bookings.id` when known — used for consumer cancel via `DELETE /bookings-simple/:id`.
    let bookingId: String?

    var isPending: Bool { statusNormalized == "pending" }

    /// Pending or accepted bookings can be cancelled by the consumer (`DELETE /bookings-simple/:id`).
    var consumerMayCancelActiveBooking: Bool {
        guard let bid = bookingId?.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty else { return false }
        let s = statusNormalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return s == "pending" || s == "accepted"
    }
}
