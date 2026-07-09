//
//  BookingModels.swift
//  OnCuts
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

    static var pacificCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacificTimeZone
        return cal
    }

    /// Start of the Pacific calendar day containing `date`.
    static func pacificStartOfDay(for date: Date) -> Date {
        pacificCalendar.startOfDay(for: date)
    }

    /// Maps a Pacific wall-clock instant to a local `Date` whose hour/minute match Pacific (for `DatePicker` wheels).
    static func localWheelDate(forPacificInstant instant: Date) -> Date {
        var local = Calendar.current
        var dc = DateComponents()
        dc.year = local.component(.year, from: Date())
        dc.month = local.component(.month, from: Date())
        dc.day = local.component(.day, from: Date())
        dc.hour = pacificCalendar.component(.hour, from: instant)
        dc.minute = pacificCalendar.component(.minute, from: instant)
        dc.second = 0
        return local.date(from: dc) ?? instant
    }

    /// Combines a Pacific calendar day with hour/minute taken from a wheel `Date` (local components = Pacific wall clock).
    static func pacificInstant(calendarDay: Date, localWheelDate wheel: Date) -> Date? {
        let hour = Calendar.current.component(.hour, from: wheel)
        let minute = Calendar.current.component(.minute, from: wheel)
        return pacificInstant(selectedDay: calendarDay, timeHHmm: String(format: "%02d:%02d", hour, minute))
    }

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
    static func formattedDisplayScheduledTime(_ raw: String, fullMonthName: Bool = false) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Time TBD" }
        guard let instant = parseScheduledInstantForDisplay(trimmed) else { return trimmed }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = pacificTimeZone
        out.dateFormat = fullMonthName ? "EEEE, MMMM d 'at' h:mm a" : "EEEE, MMM d 'at' h:mm a"
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
        parseAPIInstant(trimmed)
    }

    /// Single parser for API `scheduledTime` strings (UTC `Z`, fractional seconds, or Pacific wall-clock without offset).
    static func parseAPIInstant(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: trimmed) { return d }
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        if let d = isoPlain.date(from: trimmed) { return d }
        let pacificFull = ISO8601DateFormatter()
        pacificFull.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        pacificFull.timeZone = pacificTimeZone
        if let d = pacificFull.date(from: trimmed) { return d }
        let pg = DateFormatter()
        pg.locale = Locale(identifier: "en_US_POSIX")
        pg.timeZone = pacificTimeZone
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            pg.dateFormat = format
            if let d = pg.date(from: trimmed) { return d }
        }
        return nil
    }

    /// Whether `scheduledAt` falls on the same **Pacific** calendar day as `now` (matches bookings Today / Upcoming tabs).
    static func isSamePacificBookingDay(scheduledAt: Date, now: Date = Date()) -> Bool {
        pacificCalendar.isDate(scheduledAt, inSameDayAs: now)
    }

    /// Whole Pacific calendar days from `start` to `end` (start-of-day to start-of-day).
    static func pacificCalendarDayOffset(from start: Date, to end: Date) -> Int {
        let fromDay = pacificCalendar.startOfDay(for: start)
        let toDay = pacificCalendar.startOfDay(for: end)
        return pacificCalendar.dateComponents([.day], from: fromDay, to: toDay).day ?? 0
    }

    /// Pacific `HH:mm` key for availability matching and validation.
    static func pacificHHmmKey(from date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacificTimeZone
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return String(format: "%02d:%02d", h, m)
    }

    /// Wall-clock label that always includes minutes (e.g. `9:07 am`), for booking detail and lists.
    static func displayTimeWithMinutes(from date: Date, timeZone: TimeZone = pacificTimeZone) -> String {
        let out = DateFormatter()
        out.locale = Locale.current
        out.timeZone = timeZone
        out.dateFormat = "h:mm a"
        var s = out.string(from: date)
        s = s.replacingOccurrences(of: "AM", with: "am")
        s = s.replacingOccurrences(of: "PM", with: "pm")
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Pacific weekday + month + day (e.g. `Wed, Jul 10`) for reminder cards and lists.
    static func displayAbbreviatedPacificDay(from date: Date) -> String {
        let out = DateFormatter()
        out.locale = Locale.current
        out.timeZone = pacificTimeZone
        out.dateFormat = "E, MMM d"
        return out.string(from: date)
    }

    /// Pacific weekday + month + day + time (e.g. `Wed, Jul 10 · 9:30 am`).
    static func displayAbbreviatedPacificDayWithTime(from date: Date) -> String {
        let out = DateFormatter()
        out.locale = Locale.current
        out.timeZone = pacificTimeZone
        out.dateFormat = "E, MMM d · h:mm a"
        var s = out.string(from: date)
        s = s.replacingOccurrences(of: "AM", with: "am")
        s = s.replacingOccurrences(of: "PM", with: "pm")
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// After availability reload, keep the user's minute when still open; otherwise snap to the first open minute.
    static func reconcileAppointmentTime(_ selected: inout Date, calendarDay: Date, availableKeys: Set<String>) {
        guard !availableKeys.isEmpty else { return }
        if availableKeys.contains(pacificHHmmKey(from: selected)) { return }
        guard let first = availableKeys.sorted().first,
              let instant = pacificInstant(
                  selectedDay: pacificStartOfDay(for: calendarDay),
                  timeHHmm: first
              ) else { return }
        selected = instant
    }

    /// Every start-of-day in `monthAnchor`'s month that also falls inside `range` (`Calendar.current`).
    static func dayStartsInMonth(containing monthAnchor: Date, clippedTo range: ClosedRange<Date>) -> [Date] {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor)),
              let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count else { return [] }
        let rangeLower = cal.startOfDay(for: range.lowerBound)
        let rangeUpper = cal.startOfDay(for: range.upperBound)
        var days: [Date] = []
        for offset in 0 ..< dayCount {
            guard let date = cal.date(byAdding: .day, value: offset, to: monthStart) else { continue }
            let start = cal.startOfDay(for: date)
            if start >= rangeLower, start <= rangeUpper {
                days.append(date)
            }
        }
        return days
    }

    static func monthCacheKey(for monthAnchor: Date) -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month], from: monthAnchor)
        guard let y = c.year, let m = c.month else { return "" }
        return String(format: "%04d-%02d", y, m)
    }

    /// Month starts to prefetch for a calendar grid: displayed month plus leading/trailing padding months.
    static func monthAnchorsForCalendarOpenDayPrefetch(
        containing displayedMonth: Date,
        clippedTo range: ClosedRange<Date>
    ) -> [Date] {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth)) else {
            return [displayedMonth]
        }

        var anchors: [Date] = []
        func appendUnique(_ anchor: Date) {
            let key = monthCacheKey(for: anchor)
            guard !key.isEmpty else { return }
            guard !anchors.contains(where: { monthCacheKey(for: $0) == key }) else { return }
            guard !dayStartsInMonth(containing: anchor, clippedTo: range).isEmpty else { return }
            anchors.append(anchor)
        }

        appendUnique(monthStart)
        if let previous = cal.date(byAdding: .month, value: -1, to: monthStart) {
            appendUnique(previous)
        }
        if let next = cal.date(byAdding: .month, value: 1, to: monthStart) {
            appendUnique(next)
        }
        return anchors
    }

    /// Merges cached open-day sets for all months visible on the calendar (displayed + padding + selected month).
    static func mergedCalendarAllowedDayStarts(
        openDaysByMonthKey: [String: Set<Date>],
        loadingMonthKeys: Set<String>,
        displayedMonth: Date,
        selectedDate: Date?,
        selectionCommitted: Bool,
        range: ClosedRange<Date>,
        weeklyTemplate: Set<Date>?,
        preservedDayStarts: Set<Date> = []
    ) -> Set<Date>? {
        let cal = Calendar.current
        var monthAnchors = monthAnchorsForCalendarOpenDayPrefetch(containing: displayedMonth, clippedTo: range)

        if selectionCommitted, let selectedDate {
            let selectedMonth = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
            let selectedKey = monthCacheKey(for: selectedMonth)
            if !selectedKey.isEmpty,
               !monthAnchors.contains(where: { monthCacheKey(for: $0) == selectedKey }) {
                monthAnchors.append(selectedMonth)
            }
        }

        var merged = preservedDayStarts
        var loadedAny = !preservedDayStarts.isEmpty
        var loadingAny = false

        for anchor in monthAnchors {
            let key = monthCacheKey(for: anchor)
            guard !key.isEmpty else { continue }
            if let days = openDaysByMonthKey[key] {
                merged.formUnion(days)
                loadedAny = true
            }
            if loadingMonthKeys.contains(key) {
                loadingAny = true
            }
        }

        if selectionCommitted, let selectedDate {
            merged.insert(cal.startOfDay(for: selectedDate))
        }

        if loadedAny {
            if let weeklyTemplate {
                var allowed = merged.intersection(weeklyTemplate)
                allowed.formUnion(preservedDayStarts)
                if selectionCommitted, let selectedDate {
                    allowed.insert(cal.startOfDay(for: selectedDate))
                }
                return allowed
            }
            return merged
        }

        if loadingAny {
            return weeklyTemplate
        }

        return weeklyTemplate
    }

    /// Last bookable start-of-day in `monthAnchor`'s month (within `range`) from `allowedDayStarts`, or any in-range day when `allowed` is `nil`.
    static func latestAvailableDayInMonth(
        containing monthAnchor: Date,
        allowedDayStarts: Set<Date>?,
        range: ClosedRange<Date>
    ) -> Date? {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor)) else {
            return nil
        }
        let rangeLower = cal.startOfDay(for: range.lowerBound)
        let rangeUpper = cal.startOfDay(for: range.upperBound)
        let days = dayStartsInMonth(containing: monthAnchor, clippedTo: range)
        let candidates: [Date]
        if let allowedDayStarts {
            candidates = days.filter { allowedDayStarts.contains(cal.startOfDay(for: $0)) }
        } else {
            candidates = days
        }
        return candidates
            .map { cal.startOfDay(for: $0) }
            .filter { $0 >= rangeLower && $0 <= rangeUpper }
            .max()
    }
}

enum BookingWeekdaySchedule {
    private static let weekdayToAbbrev: [Int: String] = [
        1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat",
    ]

    /// Maps `"Mon"`, `"Tue"`, … to `Calendar.current` start-of-day dates inside `range`.
    static func dayStarts(matchingWeekdayAbbrevs abbrevs: Set<String>, in range: ClosedRange<Date>) -> Set<Date> {
        guard !abbrevs.isEmpty else { return [] }
        let cal = Calendar.current
        var day = cal.startOfDay(for: range.lowerBound)
        let upper = cal.startOfDay(for: range.upperBound)
        var matches = Set<Date>()
        while day <= upper {
            let wd = cal.component(.weekday, from: day)
            if let abbrev = weekdayToAbbrev[wd], abbrevs.contains(abbrev) {
                matches.insert(day)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return matches
    }
}

extension ServiceProvider {
    /// Weekly template days from profile availability, or `nil` when the provider has no schedule on file.
    func weeklyTemplateDayStarts(in range: ClosedRange<Date>) -> Set<Date>? {
        guard let availability, !availability.isEmpty else { return nil }
        let openAbbrevs = Set(availability.filter(\.isAvailable).map(\.dayOfWeek))
        return BookingWeekdaySchedule.dayStarts(matchingWeekdayAbbrevs: openAbbrevs, in: range)
    }
}
