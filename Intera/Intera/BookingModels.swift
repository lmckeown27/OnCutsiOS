//
//  BookingModels.swift
//  Intera
//
//  Booking intake and review metadata. `scheduledAt` is formatted for Pacific per backend contract.
//

import Foundation

/// Navigation payload for review / payment (same fields as `BookingState`).
typealias BookingMetadata = BookingState

/// Captured booking details after the intake form validates; carried through the review step.
struct BookingState: Hashable, Sendable {
    let barberId: String
    let barberDisplayName: String
    let serviceName: String
    let location: String
    /// ISO-8601 date/time interpreted in `America/Los_Angeles` (matches backend expectation).
    let scheduledAtPacificISO: String
    let resolvedPriceUsd: Int
    let durationMinutes: Int
    let profileImageUrl: String?
    let instagramHandle: String?
    /// Minimum from barber `services` / `priceRange` when building the booking; defaults to 30.
    let pricingBaselineUsd: Int

    /// Price shown at checkout: selected service price when set, else barber pricing baseline (≥ 30).
    var finalServicePriceUsd: Int {
        if resolvedPriceUsd > 0 { return resolvedPriceUsd }
        let base = pricingBaselineUsd > 0 ? pricingBaselineUsd : 30
        return base
    }
}

extension BookingState {
    /// Same rules as `ServiceProvider.instagramProfileURL` for the stored handle.
    var instagramProfileURL: URL? {
        guard let raw = instagramHandle?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let username = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
        guard !username.isEmpty else { return nil }
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return URL(string: "https://www.instagram.com/\(encoded)/")
    }
}

/// Routes inside the booking `NavigationStack` (review step only; submit handles auth + completion).
enum BookingNavigationDestination: Hashable {
    case review(BookingState)
}

enum BookingPacificSchedule {
    static let pacificTimeZone = TimeZone(identifier: "America/Los_Angeles")!

    /// Calendar day in Pacific as `yyyy-MM-dd` for the availability API.
    static func apiDateString(from date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacificTimeZone
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Combines a picked calendar day + `HH:mm` slot into one ISO string in Pacific (not the phone’s local zone).
    static func scheduledAtISO(selectedDate: Date, timeHHmm: String) -> String? {
        let parts = timeHHmm.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacificTimeZone
        let dc = cal.dateComponents([.year, .month, .day], from: selectedDate)
        guard let y = dc.year, let mo = dc.month, let day = dc.day else { return nil }

        var full = DateComponents(calendar: cal, timeZone: pacificTimeZone)
        full.year = y
        full.month = mo
        full.day = day
        full.hour = hour
        full.minute = minute
        full.second = 0
        guard let instant = cal.date(from: full) else { return nil }

        // Unambiguous instant for Node/Postgres: offset-free local strings are often parsed as UTC.
        return scheduledTimeStringForAPI(from: instant)
    }

    /// RFC 3339 / ISO-8601 **UTC** (`…Z`) for `scheduledTime` on `bookings-simple` (POST/PUT). Same absolute instant as Pacific wall-clock picks.
    static func scheduledTimeStringForAPI(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return formatter.string(from: date)
    }

    /// Formats API `scheduledTime` strings (UTC with `Z`, Pacific without offset, etc.) for UI — **America/Los_Angeles**, same as booking intake.
    static func formattedDisplayScheduledTime(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Time TBD" }
        guard let instant = parseScheduledInstantForDisplay(trimmed) else { return trimmed }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = pacificTimeZone
        out.dateFormat = "EEEE, MMM d 'at' h:mma"
        var s = out.string(from: instant)
        s = s.replacingOccurrences(of: "AM", with: "am")
        s = s.replacingOccurrences(of: "PM", with: "pm")
        s = s.replacingOccurrences(of: "  ", with: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Shorter line for inbox lists (Pacific), e.g. `Apr 2 · 9:30am`.
    static func compactDisplayScheduledTime(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let instant = parseScheduledInstantForDisplay(trimmed) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = pacificTimeZone
        out.dateFormat = "MMM d · h:mm a"
        var s = out.string(from: instant)
        s = s.replacingOccurrences(of: "AM", with: "am")
        s = s.replacingOccurrences(of: "PM", with: "pm")
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func parseScheduledInstantForDisplay(_ trimmed: String) -> Date? {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: trimmed) { return d }
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        if let d = isoPlain.date(from: trimmed) { return d }
        let pacificFull = ISO8601DateFormatter()
        pacificFull.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        pacificFull.timeZone = pacificTimeZone
        return pacificFull.date(from: trimmed)
    }
}
