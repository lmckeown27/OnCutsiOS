//
//  MyBarbersDiscover.swift
//  OnCuts
//
//  Port of web `myBarbersDiscover` rules: public location labels, My Barbers from
//  bookings-simple, approximate next-open from weekly_schedule, Discover map areas.
//

import Foundation
import CoreLocation

// MARK: - Segment

enum ConsumerHomeBrowseSegment: String, CaseIterable, Identifiable, Hashable, Sendable {
    case myBarbers
    case discover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myBarbers: return "My Barbers"
        case .discover: return "Discover"
        }
    }
}

// MARK: - Models

struct MyBarbersBookingSeed: Sendable, Hashable {
    let barberId: String
    let bookingCount: Int
    let latestScheduledTime: Date?
}

struct MyBarbersTile: Identifiable, Sendable {
    let provider: ServiceProvider
    let bookingCount: Int
    let latestScheduledTime: Date?
    let isMain: Bool
    let publicLocationLabel: String?

    var id: String { provider.id }
}

struct MyBarbersSection: Identifiable, Sendable {
    /// `nil` = unlabeled group (no section heading).
    let label: String?
    let tiles: [MyBarbersTile]

    var id: String { label ?? "__unlabeled__" }
}

struct DiscoverServiceArea: Identifiable, Sendable, Hashable {
    let id: String
    /// Display title (public label or temporary pin bucket).
    let title: String
    let latitude: Double
    let longitude: Double
    let barberIds: [String]
    /// True when title is a temporary `pin:…` bucket pending reverse geocode.
    let isTemporaryPinBucket: Bool
}

enum MyBarbersDiscover {
    /// Approximate map blob radius (not full `service_radius_km`).
    static let mapAreaRadiusMeters: CLLocationDistance = 400

    // MARK: - Public location label

    /// Coarsen a free-text place: street → next comma segment (city); else first segment.
    /// Rejects empty / literal `"Other"`.
    static func coarsenPublicLocationLabel(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.compare("Other", options: .caseInsensitive) == .orderedSame {
            return nil
        }
        // Collapse whitespace
        text = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = text
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }

        // Street-like first segment → prefer next comma segment (city / campus).
        if parts.count >= 2, looksLikeStreetSegment(parts[0]) {
            let city = parts[1]
            if city.compare("Other", options: .caseInsensitive) == .orderedSame { return nil }
            return city.isEmpty ? nil : city
        }

        let first = parts[0]
        if first.compare("Other", options: .caseInsensitive) == .orderedSame { return nil }
        return first
    }

    private static func looksLikeStreetSegment(_ segment: String) -> Bool {
        let lower = segment.lowercased()
        let streetTokens = [
            " st", " street", " ave", " avenue", " rd", " road", " blvd", " boulevard",
            " dr", " drive", " ln", " lane", " ct", " court", " way", " hwy", " highway",
            " pl", " place", " ter", " terrace",
        ]
        if streetTokens.contains(where: { lower.hasSuffix($0) || lower.contains($0 + " ") }) {
            return true
        }
        // Leading house number
        if lower.range(of: #"^\d+\s"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// Never invent `"Other"`. Prefer `serviceLocationLabel`, then primary `locations` name.
    static func publicBroadLocationLabel(
        serviceLocationLabel: String?,
        locations: [String]?
    ) -> String? {
        if let fromService = coarsenPublicLocationLabel(serviceLocationLabel) {
            return fromService
        }
        if let primary = locations?.first {
            return coarsenPublicLocationLabel(primary)
        }
        return nil
    }

    static func publicBroadLocationLabel(for provider: ServiceProvider) -> String? {
        publicBroadLocationLabel(
            serviceLocationLabel: provider.serviceLocationLabel,
            locations: provider.locations
        )
    }

    // MARK: - My Barbers from bookings

    /// Group non-cancelled bookings by barber id (count + latest scheduled time).
    static func bookingSeeds(from rows: [ConsumerBookingSimpleRow], now: Date = Date()) -> [MyBarbersBookingSeed] {
        var aggregates: [String: (count: Int, latest: Date?)] = [:]
        for row in rows {
            let status = row.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if status == "CANCELLED" || status == "REJECTED" { continue }
            guard let rawId = row.barberId?.trimmingCharacters(in: .whitespacesAndNewlines), !rawId.isEmpty else {
                continue
            }
            let id = rawId
            let scheduled = parseISODate(row.scheduledTime)
            var entry = aggregates[id] ?? (0, nil)
            entry.count += 1
            if let scheduled {
                if let existing = entry.latest {
                    if scheduled > existing { entry.latest = scheduled }
                } else {
                    entry.latest = scheduled
                }
            }
            aggregates[id] = entry
        }
        return aggregates.map { key, value in
            MyBarbersBookingSeed(
                barberId: key,
                bookingCount: value.count,
                latestScheduledTime: value.latest
            )
        }
        .sorted(by: sortSeeds)
    }

    private static func sortSeeds(_ a: MyBarbersBookingSeed, _ b: MyBarbersBookingSeed) -> Bool {
        if a.bookingCount != b.bookingCount {
            return a.bookingCount > b.bookingCount
        }
        switch (a.latestScheduledTime, b.latestScheduledTime) {
        case let (l?, r?):
            if l != r { return l > r }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return a.barberId.localizedCaseInsensitiveCompare(b.barberId) == .orderedAscending
    }

    /// Resolve seeds → tiles. `MAIN` = first after sort (client-only).
    static func buildMyBarbersTiles(
        seeds: [MyBarbersBookingSeed],
        providersById: [String: ServiceProvider],
        labelOverrides: [String: String] = [:]
    ) -> [MyBarbersTile] {
        let orderedSeeds = seeds.sorted(by: sortSeeds)
        return orderedSeeds.enumerated().compactMap { index, seed in
            guard let provider = providersById[seed.barberId] else { return nil }
            let override = labelOverrides[seed.barberId]
            let label = coarsenPublicLocationLabel(override)
                ?? publicBroadLocationLabel(for: provider)
            return MyBarbersTile(
                provider: provider,
                bookingCount: seed.bookingCount,
                latestScheduledTime: seed.latestScheduledTime,
                isMain: index == 0,
                publicLocationLabel: label
            )
        }
    }

    /// Group tiles by public label A–Z; unlabeled tiles last without a heading.
    static func groupMyBarbersSections(tiles: [MyBarbersTile]) -> [MyBarbersSection] {
        var labeled: [String: [MyBarbersTile]] = [:]
        var unlabeled: [MyBarbersTile] = []
        for tile in tiles {
            if let label = tile.publicLocationLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
               !label.isEmpty {
                labeled[label, default: []].append(tile)
            } else {
                unlabeled.append(tile)
            }
        }
        let labeledSections = labeled.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { key in
                MyBarbersSection(label: key, tiles: labeled[key] ?? [])
            }
        if unlabeled.isEmpty {
            return labeledSections
        }
        return labeledSections + [MyBarbersSection(label: nil, tiles: unlabeled)]
    }

    // MARK: - Next open (approximate from weekly_schedule)

    struct NextOpenInfo: Sendable, Hashable {
        let displayString: String
        /// Minutes from `now` until the next open moment (0 if open now). Larger = later. `nil` if unknown.
        let sortMinutesFromNow: Int?
    }

    static func nextOpenInfo(
        availability: [ServiceProvider.DayAvailability]?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NextOpenInfo {
        guard let availability, !availability.isEmpty else {
            return NextOpenInfo(displayString: "Hours not listed", sortMinutesFromNow: nil)
        }

        let weekdayIndex = calendar.component(.weekday, from: now) // 1=Sun … 7=Sat
        let dayKeys = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let todayKey = dayKeys[weekdayIndex - 1]
        let nowMinutes = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)

        func slots(for abbrev: String) -> [ParsedDaySlot] {
            guard let day = availability.first(where: {
                $0.dayOfWeek.compare(abbrev, options: .caseInsensitive) == .orderedSame
            }) else { return [] }
            return day.timeSlots.compactMap(parseDaySlot)
        }

        let todaySlots = slots(for: todayKey)
        for slot in todaySlots {
            if nowMinutes >= slot.startMinutes && nowMinutes < slot.endMinutes {
                let until = formatClockMinutes(slot.endMinutes) ?? ""
                let suffix = until.isEmpty ? "" : " · until \(until)"
                return NextOpenInfo(displayString: "Open now\(suffix)", sortMinutesFromNow: 0)
            }
        }
        if let later = todaySlots.first(where: { $0.startMinutes > nowMinutes }),
           let startLabel = formatClockMinutes(later.startMinutes) {
            let mins = later.startMinutes - nowMinutes
            return NextOpenInfo(displayString: "Today \(startLabel)", sortMinutesFromNow: mins)
        }

        for offset in 1 ... 7 {
            let idx = (weekdayIndex - 1 + offset) % 7
            let key = dayKeys[idx]
            let daySlots = slots(for: key).sorted { $0.startMinutes < $1.startMinutes }
            guard let first = daySlots.first,
                  let startLabel = formatClockMinutes(first.startMinutes)
            else { continue }
            let mins = offset * 24 * 60 - nowMinutes + first.startMinutes
            if offset == 1 {
                return NextOpenInfo(displayString: "Tomorrow \(startLabel)", sortMinutesFromNow: mins)
            }
            return NextOpenInfo(displayString: "\(key) \(startLabel)", sortMinutesFromNow: mins)
        }

        return NextOpenInfo(displayString: "Hours not listed", sortMinutesFromNow: nil)
    }

    static func nextOpenDisplayString(for provider: ServiceProvider, now: Date = Date()) -> String {
        nextOpenInfo(availability: provider.availability, now: now).displayString
    }

    // MARK: - Discover sort

    static func sortDiscoverProviders(_ providers: [ServiceProvider], now: Date = Date()) -> [ServiceProvider] {
        providers.sorted { a, b in
            switch (a.distanceMilesFromUser, b.distanceMilesFromUser) {
            case let (da?, db?) where abs(da - db) > 0.05:
                return da < db
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            let na = nextOpenInfo(availability: a.availability, now: now).sortMinutesFromNow
            let nb = nextOpenInfo(availability: b.availability, now: now).sortMinutesFromNow
            switch (na, nb) {
            case let (la?, lb?) where la != lb:
                return la < lb
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return a.businessName.localizedCaseInsensitiveCompare(b.businessName) == .orderedAscending
            }
        }
    }

    // MARK: - Discover map areas

    static func buildDiscoverServiceAreas(
        from providers: [ServiceProvider],
        labelOverrides: [String: String] = [:]
    ) -> [DiscoverServiceArea] {
        struct Bucket {
            var title: String
            var latSum: Double = 0
            var lngSum: Double = 0
            var count: Int = 0
            var barberIds: [String] = []
            var isTemporary: Bool
        }

        var buckets: [String: Bucket] = [:]

        for provider in providers {
            guard let lat = provider.serviceLatitude, let lng = provider.serviceLongitude,
                  lat.isFinite, lng.isFinite
            else { continue }

            let override = labelOverrides[provider.id]
            let label = coarsenPublicLocationLabel(override)
                ?? publicBroadLocationLabel(for: provider)

            let key: String
            let title: String
            let temporary: Bool
            if let label {
                key = "label:" + label.lowercased()
                title = label
                temporary = false
            } else {
                let pinKey = String(format: "pin:%.2f,%.2f", lat, lng)
                key = pinKey
                title = pinKey
                temporary = true
            }

            var bucket = buckets[key] ?? Bucket(title: title, isTemporary: temporary)
            bucket.latSum += lat
            bucket.lngSum += lng
            bucket.count += 1
            bucket.barberIds.append(provider.id)
            buckets[key] = bucket
        }

        return buckets.map { key, bucket in
            let n = max(1, bucket.count)
            return DiscoverServiceArea(
                id: key,
                title: bucket.isTemporary ? "Nearby area" : bucket.title,
                latitude: bucket.latSum / Double(n),
                longitude: bucket.lngSum / Double(n),
                barberIds: bucket.barberIds,
                isTemporaryPinBucket: bucket.isTemporary
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func providers(
        _ providers: [ServiceProvider],
        filteredBySelectedArea area: DiscoverServiceArea?
    ) -> [ServiceProvider] {
        guard let area else { return providers }
        let ids = Set(area.barberIds)
        return providers.filter { ids.contains($0.id) }
    }

    // MARK: - Helpers

    private struct ParsedDaySlot {
        let startMinutes: Int
        let endMinutes: Int
    }

    private static func parseDaySlot(_ raw: String) -> ParsedDaySlot? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = trimmed.split(separator: "-", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2,
              let start = parseClockToMinutes(parts[0]),
              let end = parseClockToMinutes(parts[1]),
              end > start
        else { return nil }
        return ParsedDaySlot(startMinutes: start, endMinutes: end)
    }

    /// Parses `9am`, `9:30pm`, `09:00`.
    static func parseClockToMinutes(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }

        if let match = s.range(of: #"^(\d{1,2}):(\d{2})\s*(am|pm)?$"#, options: .regularExpression) {
            let token = String(s[match])
            let comps = token.split(whereSeparator: { $0 == ":" || $0 == " " })
            guard let h = Int(comps[0].filter(\.isNumber)) else { return nil }
            let mPart = comps.count > 1 ? String(comps[1].prefix(while: \.isNumber)) : "0"
            let m = Int(mPart) ?? 0
            let ampm: String? = {
                if token.contains("am") { return "am" }
                if token.contains("pm") { return "pm" }
                return nil
            }()
            return clockComponentsToMinutes(hour: h, minute: m, ampm: ampm)
        }

        if let match = s.range(of: #"^(\d{1,2})\s*(am|pm)$"#, options: .regularExpression) {
            let token = String(s[match])
            guard let h = Int(token.prefix(while: \.isNumber)) else { return nil }
            let ampm = token.contains("pm") ? "pm" : "am"
            return clockComponentsToMinutes(hour: h, minute: 0, ampm: ampm)
        }

        // 24h `HH:mm`
        let parts = s.split(separator: ":")
        if parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1].prefix(2)),
           (0 ... 23).contains(h), (0 ... 59).contains(m) {
            return h * 60 + m
        }
        return nil
    }

    private static func clockComponentsToMinutes(hour: Int, minute: Int, ampm: String?) -> Int? {
        guard (0 ... 59).contains(minute) else { return nil }
        var h = hour
        if let ampm {
            guard (1 ... 12).contains(h) else { return nil }
            if ampm == "am" {
                if h == 12 { h = 0 }
            } else {
                if h != 12 { h += 12 }
            }
        } else {
            guard (0 ... 23).contains(h) else { return nil }
        }
        return h * 60 + minute
    }

    static func formatClockMinutes(_ minutes: Int) -> String? {
        guard minutes >= 0, minutes < 24 * 60 else { return nil }
        let h24 = minutes / 60
        let m = minutes % 60
        let ampm = h24 >= 12 ? "pm" : "am"
        let h12 = (h24 % 12 == 0) ? 12 : h24 % 12
        if m == 0 {
            return "\(h12)\(ampm)"
        }
        return String(format: "%d:%02d%@", h12, m, ampm)
    }

    static func parseISODate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let d = fallback.date(from: raw) { return d }
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return fallback.date(from: raw)
    }
}

extension ServiceProvider {
    var publicBroadLocationLabel: String? {
        MyBarbersDiscover.publicBroadLocationLabel(for: self)
    }

    var hasFiniteServiceCoordinate: Bool {
        guard let lat = serviceLatitude, let lng = serviceLongitude else { return false }
        return lat.isFinite && lng.isFinite
    }

    var serviceCoordinate: CLLocationCoordinate2D? {
        guard hasFiniteServiceCoordinate, let lat = serviceLatitude, let lng = serviceLongitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
