//
//  MyBarbersDiscover.swift
//  OnCuts
//
//  Port of web `myBarbersDiscover` rules: public location labels, My Barbers from
//  bookings-simple, approximate next-open from weekly_schedule, Discover map areas.
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Segment

enum ConsumerHomeBrowseSegment: String, CaseIterable, Identifiable, Hashable, Sendable {
    case myBarbers
    case discover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myBarbers: return "My Operators"
        case .discover: return "Discover"
        }
    }

    /// Short label for the compact glass segment pill beside the utility chrome.
    var compactTitle: String {
        title
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

/// Zoom-dependent map circle: one or more `DiscoverServiceArea`s merged when the camera is far out.
struct DiscoverMapAreaCluster: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let latitude: Double
    let longitude: Double
    /// Drawn circle radius (covers member blobs at the current zoom merge).
    let radiusMeters: CLLocationDistance
    let memberAreaIds: [String]
    let barberIds: [String]
}

enum MyBarbersDiscover {
    /// Approximate map blob radius at 1 mi zoom (scales with zoom for constant on-screen size).
    static let mapAreaRadiusMeters: CLLocationDistance = 400

    /// Prefix for synthetic selection ids that represent a multi-area cluster tap.
    static let mapClusterSelectionPrefix = "cluster:"

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
            let key = seed.barberId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let provider = providersById[key] ?? providersById[seed.barberId] else { return nil }
            let override = labelOverrides[provider.id] ?? labelOverrides[seed.barberId] ?? labelOverrides[key]
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

    // MARK: - Zoom-aware map clustering

    /// Visible map radius (short axis) used as the “1 mi” visual reference for dashed circles.
    private static let mapAreaVisualReferenceVisibleRadiusMeters: CLLocationDistance = 1_609.344

    /// Half of the shorter visible map axis (meters) — matches the olive browse circle / pill radius.
    static func visibleMapRadiusMeters(from region: MKCoordinateRegion) -> CLLocationDistance? {
        guard region.span.latitudeDelta.isFinite, region.span.longitudeDelta.isFinite,
              region.span.latitudeDelta > 0, region.span.longitudeDelta > 0
        else { return nil }
        let halfLatMeters = region.span.latitudeDelta * 111_320 * 0.5
        let cosLat = max(0.2, abs(cos(region.center.latitude * .pi / 180)))
        let halfLngMeters = region.span.longitudeDelta * 111_320 * cosLat * 0.5
        let radius = min(halfLatMeters, halfLngMeters)
        guard radius.isFinite, radius > 0 else { return nil }
        return radius
    }

    /// Dashed-circle ground radius that keeps ~the same on-screen size as at 1 mi zoom.
    static func mapAreaScreenConstantRadiusMeters(for region: MKCoordinateRegion) -> CLLocationDistance {
        let visibleRadius = visibleMapRadiusMeters(from: region) ?? mapAreaVisualReferenceVisibleRadiusMeters
        let scale = max(1, visibleRadius / mapAreaVisualReferenceVisibleRadiusMeters)
        return mapAreaRadiusMeters * scale
    }

    /// Merge when two screen-constant circles would heavily overlap.
    static func mapAreaMergeDistanceMeters(for region: MKCoordinateRegion) -> CLLocationDistance {
        mapAreaScreenConstantRadiusMeters(for: region) * 1.75
    }

    static func clusterMapAreas(
        _ areas: [DiscoverServiceArea],
        mergeDistanceMeters: CLLocationDistance,
        baseRadiusMeters: CLLocationDistance
    ) -> [DiscoverMapAreaCluster] {
        guard !areas.isEmpty else { return [] }
        if areas.count == 1 {
            return [makeMapAreaCluster(from: areas, baseRadiusMeters: baseRadiusMeters)]
        }

        var groups: [[DiscoverServiceArea]] = areas.map { [$0] }
        var didMerge = true
        while didMerge {
            didMerge = false
            var i = 0
            while i < groups.count {
                var j = i + 1
                while j < groups.count {
                    if shouldMergeMapAreaGroups(
                        groups[i],
                        groups[j],
                        mergeDistanceMeters: mergeDistanceMeters
                    ) {
                        groups[i].append(contentsOf: groups[j])
                        groups.remove(at: j)
                        didMerge = true
                    } else {
                        j += 1
                    }
                }
                i += 1
            }
        }

        return groups.map { makeMapAreaCluster(from: $0, baseRadiusMeters: baseRadiusMeters) }
    }

    private static func shouldMergeMapAreaGroups(
        _ a: [DiscoverServiceArea],
        _ b: [DiscoverServiceArea],
        mergeDistanceMeters: CLLocationDistance
    ) -> Bool {
        let ca = centroidLocation(of: a)
        let cb = centroidLocation(of: b)
        return ca.distance(from: cb) <= mergeDistanceMeters
    }

    private static func centroidLocation(of areas: [DiscoverServiceArea]) -> CLLocation {
        let n = max(1, areas.count)
        let lat = areas.reduce(0.0) { $0 + $1.latitude } / Double(n)
        let lng = areas.reduce(0.0) { $0 + $1.longitude } / Double(n)
        return CLLocation(latitude: lat, longitude: lng)
    }

    private static func makeMapAreaCluster(
        from members: [DiscoverServiceArea],
        baseRadiusMeters: CLLocationDistance
    ) -> DiscoverMapAreaCluster {
        let center = centroidLocation(of: members)
        let extent = members
            .map { center.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }
            .max() ?? 0
        // Single: screen-constant size. Combined: cover members and grow as zoom-out scales baseRadius.
        var radius = max(baseRadiusMeters, extent + baseRadiusMeters)
        if members.count > 1 {
            // Combined ring reads slightly larger than a lone operator at the same zoom.
            let clusterBoost = 1 + 0.06 * Double(min(members.count - 1, 10))
            radius = max(radius, baseRadiusMeters * clusterBoost)
        }

        let memberIds = members.map(\.id).sorted()
        let id: String
        if memberIds.count == 1 {
            id = memberIds[0]
        } else {
            id = mapClusterSelectionPrefix + memberIds.joined(separator: "\u{1e}")
        }

        let titles = members.map(\.title)
        let title: String
        if members.count == 1 {
            title = members[0].title
        } else if titles.count <= 2 {
            title = titles.joined(separator: " · ")
        } else {
            title = "\(members.count) areas"
        }

        return DiscoverMapAreaCluster(
            id: id,
            title: title,
            latitude: center.coordinate.latitude,
            longitude: center.coordinate.longitude,
            radiusMeters: radius,
            memberAreaIds: memberIds,
            barberIds: members.flatMap(\.barberIds)
        )
    }

    /// Resolves a single-area or multi-area cluster selection id into a filterable area.
    static func resolvedSelectedArea(
        id: String?,
        from areas: [DiscoverServiceArea]
    ) -> DiscoverServiceArea? {
        guard let id else { return nil }
        if id.hasPrefix(mapClusterSelectionPrefix) {
            let raw = String(id.dropFirst(mapClusterSelectionPrefix.count))
            let memberIds = Set(raw.split(separator: "\u{1e}").map(String.init))
            let members = areas.filter { memberIds.contains($0.id) }
            guard !members.isEmpty else { return nil }
            let cluster = makeMapAreaCluster(from: members, baseRadiusMeters: mapAreaRadiusMeters)
            return DiscoverServiceArea(
                id: cluster.id,
                title: cluster.title,
                latitude: cluster.latitude,
                longitude: cluster.longitude,
                barberIds: cluster.barberIds,
                isTemporaryPinBucket: members.contains(where: \.isTemporaryPinBucket)
            )
        }
        return areas.first(where: { $0.id == id })
    }

    static func selectionContainsArea(selectionId: String?, areaId: String) -> Bool {
        guard let selectionId else { return false }
        if selectionId == areaId { return true }
        if selectionId.hasPrefix(mapClusterSelectionPrefix) {
            let raw = String(selectionId.dropFirst(mapClusterSelectionPrefix.count))
            return raw.split(separator: "\u{1e}").map(String.init).contains(areaId)
        }
        return false
    }

    static func providers(
        _ providers: [ServiceProvider],
        filteredBySelectedArea area: DiscoverServiceArea?
    ) -> [ServiceProvider] {
        guard let area else { return providers }
        let ids = Set(area.barberIds)
        return providers.filter { ids.contains($0.id) }
    }

    /// Providers whose service pin falls inside the visible map region (zoom/pan).
    /// Pads the viewport slightly so sheet chrome doesn’t clip edge pins. Falls back to
    /// `providers` when the region isn’t usable yet or nobody has coordinates.
    static func providers(
        _ providers: [ServiceProvider],
        intersectingVisibleRegion region: MKCoordinateRegion?
    ) -> [ServiceProvider] {
        guard let region,
              region.span.latitudeDelta.isFinite,
              region.span.longitudeDelta.isFinite,
              region.span.latitudeDelta > 0,
              region.span.longitudeDelta > 0
        else { return providers }

        let withCoords = providers.filter(\.hasFiniteServiceCoordinate)
        // No geocoded operators — keep the browse list visible in the pull-up.
        guard !withCoords.isEmpty else { return providers }

        // ~20% pad so operators near the sheet / header aren’t dropped.
        let halfLat = max(region.span.latitudeDelta * 0.6, 0.002)
        let halfLng = max(region.span.longitudeDelta * 0.6, 0.002)
        let minLat = region.center.latitude - halfLat
        let maxLat = region.center.latitude + halfLat
        let minLng = region.center.longitude - halfLng
        let maxLng = region.center.longitude + halfLng

        let inView = withCoords.filter { provider in
            guard let lat = provider.serviceLatitude, let lng = provider.serviceLongitude else { return false }
            return lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng
        }

        if !inView.isEmpty { return inView }

        // Zoomed out far enough that an empty hit is almost certainly a bad region sample —
        // keep showing geocoded nearby operators instead of a blank sheet.
        let visibleHeightMeters = region.span.latitudeDelta * 111_320
        if visibleHeightMeters >= 6_000 {
            return withCoords
        }
        return inView
    }

    /// Approximate visible “radius” label from the map span (for sheet chrome).
    static func visibleRadiusMilesLabel(for region: MKCoordinateRegion?) -> String? {
        guard let region, let radiusMeters = visibleMapRadiusMeters(from: region) else { return nil }
        let radiusMiles = radiusMeters / 1609.344
        guard radiusMiles.isFinite, radiusMiles > 0 else { return nil }
        if radiusMiles < 1 {
            return String(format: "%.1f mi", radiusMiles)
        }
        return "\(Int(radiusMiles.rounded())) mi"
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
