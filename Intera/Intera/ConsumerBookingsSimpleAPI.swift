//
//  ConsumerBookingsSimpleAPI.swift
//  Intera
//
//  Fetches consumer bookings from `GET /api/v1/bookings-simple?role=consumer` (same as the CampusCuts web app).
//

import Foundation

// MARK: - API

enum ConsumerBookingsSimpleAPI {
    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    /// `true` when the server rejected the Bearer token.
    static func isUnauthorizedHTTPError(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == "ConsumerBookingsSimpleAPI" && ns.code == 401
    }

    /// All bookings for the signed-in consumer (no `status` filter); segment client-side into Past / Today / Upcoming like the web.
    /// Pass `consumerUserId` so rows hidden locally (e.g. before `hide-from-list` exists on the server) stay filtered.
    static func fetchConsumerBookings(bearerToken: String?, consumerUserId: String? = nil) async throws -> [ConsumerBookingSimpleRow] {
        var components = URLComponents(string: AppConfiguration.messagingAPIRootTrimmed + "/bookings-simple")!
        components.queryItems = [
            URLQueryItem(name: "role", value: "consumer"),
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp)
        let decoded: [ConsumerBookingSimpleRow]
        if let env = try? jsonDecoder.decode(BookingsSimpleTopEnvelope.self, from: data),
           let rows = env.data?.bookings {
            decoded = rows
        } else if let inner = try? jsonDecoder.decode(BookingsSimpleDataOnly.self, from: data) {
            decoded = inner.bookings
        } else {
            throw NSError(
                domain: "ConsumerBookingsSimpleAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not decode bookings list."]
            )
        }
        return ConsumerHiddenBookingsStore.filterRows(decoded, consumerUserId: consumerUserId)
    }

    /// `GET /api/v1/bookings-simple/:id` — authoritative booking row (avoids stale **PENDING** in the list right after a barber accepts).
    static func fetchConsumerBookingById(bookingId: String, bearerToken: String?) async throws -> ConsumerBookingSimpleRow {
        let enc = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/bookings-simple/\(enc)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
        let env = try jsonDecoder.decode(BookingSingleEnvelope.self, from: data)
        guard let b = env.booking else {
            throw NSError(
                domain: "ConsumerBookingsSimpleAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing booking in response."]
            )
        }
        return ConsumerBookingSimpleRow(fromSingleBooking: b)
    }

    /// Best-effort barber profile image: `GET /bookings-simple/:id` nested barber, then `GET /barbers/:id` when `barberId` is known (matches browse cards).
    static func resolveBarberAvatarURL(bookingId: String, bearerToken: String?) async -> String? {
        let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { return nil }
        do {
            let row = try await fetchConsumerBookingById(bookingId: bookingId, bearerToken: token)
            var chosen: String?
            if let av = row.barberAvatar?.trimmingCharacters(in: .whitespacesAndNewlines), !av.isEmpty {
                chosen = av
            }
            if let bid = row.barberId?.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty {
                do {
                    let provider = try await CampusCutsBarberDetailAPI.fetchServiceProvider(
                        barberId: bid,
                        bearerToken: token
                    )
                    if let u = provider.profileImageUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                        chosen = u
                    }
                } catch {
                    // Keep booking-row URL if barber detail fails.
                }
            }
            if let c = chosen?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
                return c
            }
            return nil
        } catch {
            return nil
        }
    }

    /// `POST /api/v1/bookings-simple/:id/reschedule-request` — consumer proposes a new time (and optional location/notes); provider must approve.
    static func submitRescheduleRequest(
        bookingId: String,
        scheduledTimeISO: String,
        location: String?,
        notes: String?,
        bearerToken: String?
    ) async throws -> PendingRescheduleRequestDTO {
        let enc = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/bookings-simple/\(enc)/reschedule-request") else {
            throw URLError(.badURL)
        }
        var body: [String: Any] = ["scheduledTime": scheduledTimeISO]
        if let location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["location"] = location
        }
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["notes"] = notes
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [])

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }

        let (respData, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: respData)
        return try decodePendingRescheduleRequest(from: respData)
    }

    /// `PUT /api/v1/bookings-simple/:id` — metadata only (service name). Consumers must not send `scheduledTime` (server returns 403).
    static func updateConsumerBookingMetadata(
        bookingId: String,
        location: String?,
        serviceName: String?,
        bearerToken: String?
    ) async throws {
        let enc = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/bookings-simple/\(enc)") else {
            throw URLError(.badURL)
        }
        var body: [String: Any] = [:]
        if let location {
            body["location"] = location
        }
        if let serviceName, !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["serviceName"] = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !body.isEmpty else { return }
        let data = try JSONSerialization.data(withJSONObject: body, options: [])

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }

        let (respData, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: respData)
    }

    private static func decodePendingRescheduleRequest(from data: Data) throws -> PendingRescheduleRequestDTO {
        if let env = try? jsonDecoder.decode(RescheduleRequestEnvelope.self, from: data),
           let pending = env.data?.pendingRescheduleRequest ?? env.pendingRescheduleRequest {
            return pending
        }
        if let pending = try? jsonDecoder.decode(PendingRescheduleRequestDTO.self, from: data) {
            return pending
        }
        throw NSError(
            domain: "ConsumerBookingsSimpleAPI",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Could not read reschedule request from the server."]
        )
    }

    /// `POST /api/v1/bookings-simple/:id/hide-from-list` — consumer removes a **past** booking from their timeline (booking row is retained for the provider).
    /// - Returns: `true` if the server persisted the hide; `false` on HTTP 404 (route not deployed or booking id unknown) — caller should use ``ConsumerHiddenBookingsStore/recordHidden(bookingId:consumerUserId:)``.
    @discardableResult
    static func hidePastBookingFromConsumerList(bookingId: String, bearerToken: String?) async throws -> Bool {
        let enc = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/bookings-simple/\(enc)/hide-from-list") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        switch http.statusCode {
        case 200 ... 299:
            return true
        case 404:
            return false
        default:
            let msg = serverErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw NSError(
                domain: "ConsumerBookingsSimpleAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }

    private static func throwIfHTTPError(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw NSError(
                domain: "ConsumerBookingsSimpleAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }
    }

    private static func throwIfHTTPError(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg = serverErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw NSError(
                domain: "ConsumerBookingsSimpleAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }

    private static func serverErrorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        if let s = obj["error"] as? String {
            return s.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        if let block = obj["error"] as? [String: Any],
           let msg = block["message"] as? String {
            return msg.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        if let msg = obj["message"] as? String {
            return msg.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Decoding (matches Express `GET /bookings-simple`)

private struct BookingsSimpleTopEnvelope: Decodable, Sendable {
    let success: Bool?
    let data: BookingsSimpleDataBlock?
}

private struct BookingsSimpleDataOnly: Decodable, Sendable {
    let bookings: [ConsumerBookingSimpleRow]
}

private struct BookingsSimpleDataBlock: Decodable, Sendable {
    let bookings: [ConsumerBookingSimpleRow]
}

private struct BookingSingleEnvelope: Decodable, Sendable {
    let success: Bool?
    let booking: BookingSingleDetail?
}

private struct RescheduleRequestEnvelope: Decodable, Sendable {
    let success: Bool?
    let pendingRescheduleRequest: PendingRescheduleRequestDTO?
    let data: RescheduleRequestDataBlock?
}

private struct RescheduleRequestDataBlock: Decodable, Sendable {
    let pendingRescheduleRequest: PendingRescheduleRequestDTO?
}

private struct BookingSingleDetail: Decodable, Sendable {
    let id: String
    let barberId: String?
    let serviceType: String?
    let serviceName: String?
    let scheduledTime: String
    let status: String
    let location: String?
    let notes: String?
    let priceUsdCents: Int?
    let pendingRescheduleRequest: PendingRescheduleRequestDTO?
    let barber: BookingSingleBarber?
}

private struct BookingSingleBarber: Decodable, Sendable {
    let firstName: String?
    let lastName: String?
    let profileImageUrl: String?

    /// Accepts camelCase / snake_case / alternate keys some deployments use for the user avatar on `GET /bookings-simple/:id`.
    private enum CodingKeys: String, CodingKey {
        case firstName
        case lastName
        case profileImageUrl
        case profile_image_url
        case avatarUrl
        case avatar_url
        /// List `GET /bookings-simple` nests `barber.avatar` (same URL as `barberAvatar` on the row).
        case avatar
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        let candidates: [String?] = [
            try c.decodeIfPresent(String.self, forKey: .profileImageUrl),
            try c.decodeIfPresent(String.self, forKey: .profile_image_url),
            try c.decodeIfPresent(String.self, forKey: .avatarUrl),
            try c.decodeIfPresent(String.self, forKey: .avatar_url),
            try c.decodeIfPresent(String.self, forKey: .avatar),
        ]
        profileImageUrl = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

struct ConsumerBookingSimpleRow: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let barberId: String?
    let serviceType: String?
    let serviceName: String?
    let scheduledTime: String
    let status: String
    let barberName: String?
    /// From `GET /bookings-simple` (barber profile photo URL or path).
    let barberAvatar: String?
    let location: String?
    let notes: String?
    let priceUsdCents: Int?
    /// When present and pending, the confirmed `scheduledTime` is unchanged until the provider approves.
    let pendingRescheduleRequest: PendingRescheduleRequestDTO?
}

extension ConsumerBookingSimpleRow {
    /// Stable key for grouping list rows by service provider (barber). Prefer `barberId`, then name.
    var providerGroupingKey: String {
        if let id = barberId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return "id:" + id.lowercased()
        }
        if let n = barberName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return "name:" + n.lowercased()
        }
        return "booking:" + id
    }

    /// Maps `GET /bookings-simple/:id` payload to the same row shape as the consumer list.
    fileprivate init(fromSingleBooking b: BookingSingleDetail) {
        let fn = b.barber?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ln = b.barber?.lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = [fn, ln].filter { !$0.isEmpty }.joined(separator: " ")
        let barberName: String? = combined.isEmpty ? nil : combined
        self.init(
            id: b.id,
            barberId: b.barberId,
            serviceType: b.serviceType,
            serviceName: b.serviceName,
            scheduledTime: b.scheduledTime,
            status: b.status,
            barberName: barberName,
            barberAvatar: b.barber?.profileImageUrl,
            location: b.location,
            notes: b.notes,
            priceUsdCents: b.priceUsdCents,
            pendingRescheduleRequest: b.pendingRescheduleRequest
        )
    }

    var hasPendingRescheduleRequest: Bool {
        pendingRescheduleRequest?.isPending == true
    }
}

// MARK: - Past / Today / Upcoming (aligned with web `BookingsModal` filters + consumer PENDING rows)

extension ConsumerBookingSimpleRow {
    /// Calendar segment for profile tabs — mirrors web **Today / Upcoming / Past** behavior and includes **PENDING** where consumers expect to see open requests.
    func scheduleSegment(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ConsumerBookingScheduleSegment {
        let s = status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Provider marked the visit complete but the consumer still owes payment: keep the row under **Today**
        // (action item). **PAID** and other terminal states stay in Past — that is when "Book again" is appropriate.
        if s == "COMPLETED", BookingPaymentRequestPayload.from(bookingRow: self) != nil {
            return .today
        }

        guard let t = Self.parseScheduledISO(scheduledTime) else {
            return .past
        }

        if ["PAID", "CANCELLED", "REJECTED", "DECLINED", "REFUNDED", "NO_SHOW"].contains(s) {
            return .past
        }

        if s == "COMPLETED" {
            return .past
        }

        if s == "ACCEPTED" || s == "PENDING" {
            let isToday = calendar.isDate(t, inSameDayAs: now)
            if isToday {
                return .today
            }
            if t > now {
                return .upcoming
            }
            return .past
        }

        return .past
    }

    static func parseScheduledISO(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: trimmed)
    }

    var scheduledAtDate: Date? {
        Self.parseScheduledISO(scheduledTime)
    }
}

// MARK: - List / detail copy (bookings-simple)

extension ConsumerBookingSimpleRow {
    /// Snapshot for messaging inbox / thread header when opening chat from a booking row.
    var messagingBookingSnapshot: MessagingBookingDTO {
        MessagingBookingDTO(
            id: id,
            status: status,
            serviceName: displayServiceName,
            scheduledTime: scheduledTime,
            location: location,
            barberId: barberId,
            barberName: barberName,
            barberBusinessName: nil,
            barberProfileImageUrl: barberAvatar
        )
    }

    var displayServiceName: String {
        if let n = serviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return Self.humanizeShoutingCapsServiceNameIfNeeded(n)
        }
        if let t = serviceType?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return Self.titleCaseServiceTypeForDisplay(t)
        }
        return "Service"
    }

    /// Backend often stores `serviceName` in ALL CAPS; present like the rest of consumer UI (“Haircut”).
    private static func humanizeShoutingCapsServiceNameIfNeeded(_ raw: String) -> String {
        let letters = raw.filter(\.isLetter)
        // Keep short tokens (e.g. “VIP”) as-is.
        guard letters.count > 3, !letters.isEmpty, letters.allSatisfy(\.isUppercase) else { return raw }
        return raw.localizedLowercase.localizedCapitalized
    }

    var displayStatus: String {
        let u = status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch u {
        case "PENDING": return "Pending"
        case "ACCEPTED": return "Confirmed"
        case "COMPLETED": return "Awaiting payment"
        case "PAID": return "Paid"
        case "CANCELLED": return "Cancelled"
        case "REJECTED": return "Declined"
        default: return status.capitalized
        }
    }

    private static func titleCaseServiceTypeForDisplay(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

enum ConsumerBookingScheduleSegment: String, CaseIterable, Sendable {
    case past = "Past"
    case today = "Today"
    case upcoming = "Upcoming"
}

extension ConsumerBookingSimpleRow {
    func toUserProfileAppointment() -> UserProfileAppointment? {
        guard let at = Self.parseScheduledISO(scheduledTime) else { return nil }
        let barber = barberName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Provider"
        return UserProfileAppointment(
            id: id,
            serviceName: displayServiceName,
            providerName: barber,
            scheduledAt: at,
            statusNote: Self.displayStatusForProfile(status)
        )
    }

    private static func displayStatusForProfile(_ raw: String) -> String? {
        let u = raw.uppercased()
        switch u {
        case "PENDING": return "Pending"
        case "ACCEPTED": return "Confirmed"
        case "COMPLETED": return "Awaiting payment"
        case "PAID": return "Paid"
        case "CANCELLED": return "Cancelled"
        case "REJECTED": return "Declined"
        default: return raw.capitalized
        }
    }
}

extension UserProfileAppointment {
    /// Splits **bookings-simple** rows into Past / Today / Upcoming lists (sorted like the web: ascending for today/upcoming, descending for past).
    static func listsFromBookingsSimple(rows: [ConsumerBookingSimpleRow]) -> (
        past: [UserProfileAppointment],
        today: [UserProfileAppointment],
        upcoming: [UserProfileAppointment]
    ) {
        var past: [UserProfileAppointment] = []
        var today: [UserProfileAppointment] = []
        var upcoming: [UserProfileAppointment] = []

        for row in rows {
            guard let appt = row.toUserProfileAppointment() else { continue }
            switch row.scheduleSegment() {
            case .past:
                past.append(appt)
            case .today:
                today.append(appt)
            case .upcoming:
                upcoming.append(appt)
            }
        }

        past.sort { $0.scheduledAt > $1.scheduledAt }
        today.sort { $0.scheduledAt < $1.scheduledAt }
        upcoming.sort { $0.scheduledAt < $1.scheduledAt }

        return (past, today, upcoming)
    }
}
