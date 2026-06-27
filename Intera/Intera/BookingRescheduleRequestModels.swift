//
//  BookingRescheduleRequestModels.swift
//  Intera
//
//  Consumer schedule change requests (`POST …/bookings-simple/:id/reschedule-request`).
//

import Foundation

/// Pending provider approval — decoded from `pendingRescheduleRequest` on booking list/detail.
struct PendingRescheduleRequestDTO: Decodable, Sendable, Hashable {
    let id: String?
    let location: String?
    let notes: String?
    let status: String?
    private let requestedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case location
        case notes
        case status
        case requestedAt
        case requested_at
        case proposedScheduledTime
        case proposed_scheduled_time
        case scheduledTime
        case scheduled_time
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decodeFlexibleId(from: c)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        requestedAt = Self.firstString(
            c,
            .requestedAt,
            .requested_at,
            .proposedScheduledTime,
            .proposed_scheduled_time,
            .scheduledTime,
            .scheduled_time
        )
    }

    init(
        id: String? = nil,
        proposedTimeISO: String,
        location: String? = nil,
        notes: String? = nil,
        status: String? = "pending"
    ) {
        self.id = id
        self.requestedAt = proposedTimeISO
        self.location = location
        self.notes = notes
        self.status = status
    }

    var isPending: Bool {
        let s = status?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? "PENDING"
        return s == "PENDING"
    }

    var proposedTimeISO: String? {
        let raw = requestedAt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    var proposedScheduledAtDate: Date? {
        guard let raw = proposedTimeISO else { return nil }
        return ConsumerBookingSimpleRow.parseScheduledISO(raw)
    }

    private static func firstString(_ c: KeyedDecodingContainer<CodingKeys>, _ keys: CodingKeys...) -> String? {
        for key in keys {
            if let s = try? c.decodeIfPresent(String.self, forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty {
                return s
            }
        }
        return nil
    }

    private static func decodeFlexibleId(from c: KeyedDecodingContainer<CodingKeys>) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: .id) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        if let i = try? c.decodeIfPresent(Int.self, forKey: .id) {
            return String(i)
        }
        return nil
    }
}

extension PendingRescheduleRequestDTO {
    func formattedProposedDate(using formatter: DateFormatter) -> String? {
        guard let date = proposedScheduledAtDate else { return nil }
        return formatter.string(from: date)
    }

    func formattedProposedTime(using formatter: DateFormatter) -> String? {
        guard let date = proposedScheduledAtDate else { return nil }
        return formatter.string(from: date)
    }
}
