//
//  OnCutsWeeklySchedule.swift
//  OnCutsModule
//
//  Decodes `weekly_schedule` from GET /barbers (object or JSON string).
//

import Foundation

public struct OnCutsTimeIntervalDTO: Decodable, Sendable, Hashable {
    public let start: String?
    public let end: String?
}

public struct OnCutsDayScheduleDTO: Decodable, Sendable, Hashable {
    public let enabled: Bool?
    public let intervals: [OnCutsTimeIntervalDTO]?
    public let start: String?
    public let end: String?
}

/// `weekly_schedule` on barber list/detail rows.
public struct OnCutsWeeklySchedulePayload: Decodable, Sendable, Hashable {
    public let days: [String: OnCutsDayScheduleDTO]

    public init(days: [String: OnCutsDayScheduleDTO]) {
        self.days = days
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: OnCutsDayScheduleDTO].self) {
            days = dict
            return
        }
        if let raw = try? container.decode(String.self),
           let data = raw.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: OnCutsDayScheduleDTO].self, from: data) {
            days = dict
            return
        }
        days = [:]
    }
}

/// One open weekday for browse/card display (`Mon` + `9am-5pm`).
public struct OnCutsBrowseWeeklyDay: Sendable, Hashable, Identifiable {
    public let id: String
    public let dayOfWeek: String
    public let timeSlots: [String]

    public init(id: String, dayOfWeek: String, timeSlots: [String]) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.timeSlots = timeSlots
    }
}

public enum OnCutsWeeklyScheduleMapping {
    private static let dayOrder = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ]

    private static let dayAbbrev: [String: (id: String, label: String)] = [
        "monday": ("mon", "Mon"),
        "tuesday": ("tue", "Tue"),
        "wednesday": ("wed", "Wed"),
        "thursday": ("thu", "Thu"),
        "friday": ("fri", "Fri"),
        "saturday": ("sat", "Sat"),
        "sunday": ("sun", "Sun"),
    ]

    public static func browseDays(from payload: OnCutsWeeklySchedulePayload?) -> [OnCutsBrowseWeeklyDay] {
        guard let payload else { return [] }
        var result: [OnCutsBrowseWeeklyDay] = []
        for key in dayOrder {
            guard let day = payload.days[key], day.enabled == true else { continue }
            guard let abbrev = dayAbbrev[key] else { continue }
            let slots = timeSlots(from: day)
            guard !slots.isEmpty else { continue }
            result.append(
                OnCutsBrowseWeeklyDay(id: abbrev.id, dayOfWeek: abbrev.label, timeSlots: slots)
            )
        }
        return result
    }

    private static func timeSlots(from day: OnCutsDayScheduleDTO) -> [String] {
        if let intervals = day.intervals {
            let mapped = intervals.compactMap { interval -> String? in
                guard let start = interval.start, let end = interval.end,
                      let startLabel = formatClock(start),
                      let endLabel = formatClock(end)
                else { return nil }
                return "\(startLabel)-\(endLabel)"
            }
            if !mapped.isEmpty { return mapped }
        }
        if let start = day.start, let end = day.end,
           let startLabel = formatClock(start),
           let endLabel = formatClock(end) {
            return ["\(startLabel)-\(endLabel)"]
        }
        return []
    }

    /// Web `formatTime`: `09:00` → `9am`, `09:30` → `9:30am`.
    public static func formatClock(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":")
        guard let hour24 = Int(parts[0]) else { return nil }
        let minute: Int = {
            guard parts.count > 1 else { return 0 }
            return Int(parts[1].prefix(2)) ?? 0
        }()
        let ampm = hour24 >= 12 ? "pm" : "am"
        let hour12 = (hour24 % 12 == 0) ? 12 : hour24 % 12
        if minute == 0 {
            return "\(hour12)\(ampm)"
        }
        return String(format: "%d:%02d%@", hour12, minute, ampm)
    }
}
