//
//  ConsumerBookingsTimelineProjection.swift
//  OnCuts
//
//  Data preparation for the unified bookings timeline: chronological sections,
//  scroll anchors, and visual timeline position (past / today / upcoming).
//

import Foundation

/// Visual lane for `BookingTimelineRow` (maps 1:1 with `ConsumerBookingScheduleSegment`).
enum TimelinePosition: String, Sendable, Hashable {
    case past
    case today
    case upcoming
}

/// Two or more past bookings with the same provider, shown as one expandable group in the Past section.
struct ConsumerPastProviderGroup: Equatable, Sendable, Identifiable, Hashable {
    let id: String
    let providerDisplayName: String
    let barberAvatar: String?
    /// Newest first (same order as flat past list per provider).
    let bookings: [ConsumerBookingSimpleRow]
}

/// Past section: either a full row (single visit with a provider) or a multi-visit group.
enum PastBookingsListItem: Equatable, Sendable, Hashable {
    case single(ConsumerBookingSimpleRow)
    case group(ConsumerPastProviderGroup)
}

/// Single source of truth for Past / Today / Upcoming buckets and scroll targets.
struct ConsumerBookingsTimelineProjection: Equatable, Sendable {
    let past: [ConsumerBookingSimpleRow]
    /// Past visits grouped by provider: one entry per provider (`.single` or `.group` with 2+ bookings).
    let pastItems: [PastBookingsListItem]
    let today: [ConsumerBookingSimpleRow]
    let upcoming: [ConsumerBookingSimpleRow]

    /// Section header ids for `ScrollViewReader.scrollTo`.
    static let pastHeaderID = "timeline-section-past"
    static let todayHeaderID = "timeline-section-today"
    static let upcomingHeaderID = "timeline-section-upcoming"

    /// One chronological stream: past (newest first) → today (soonest first) → upcoming (soonest first).
    var chronologicalFlat: [(row: ConsumerBookingSimpleRow, position: TimelinePosition)] {
        let p = past.map { ($0, TimelinePosition.past) }
        let t = today.map { ($0, TimelinePosition.today) }
        let u = upcoming.map { ($0, TimelinePosition.upcoming) }
        return p + t + u
    }

    /// Index in `chronologicalFlat` of the first **today** booking (scroll anchor for a row).
    var firstTodayBookingFlatIndex: Int? {
        chronologicalFlat.firstIndex { $0.position == .today }
    }

    /// Preferred section to reveal on first open (Today → Upcoming → Past).
    var preferredScrollAnchorID: String {
        if !today.isEmpty { return Self.todayHeaderID }
        if !upcoming.isEmpty { return Self.upcomingHeaderID }
        if !past.isEmpty { return Self.pastHeaderID }
        return Self.todayHeaderID
    }

    static func build(
        from rows: [ConsumerBookingSimpleRow],
        now: Date = Date(),
        calendar: Calendar = .current,
        timingMode: PaymentTimingMode
    ) -> Self {
        var pastR: [ConsumerBookingSimpleRow] = []
        var todayR: [ConsumerBookingSimpleRow] = []
        var upR: [ConsumerBookingSimpleRow] = []
        for row in rows {
            switch row.scheduleSegment(now: now, calendar: calendar, timingMode: timingMode) {
            case .past: pastR.append(row)
            case .today: todayR.append(row)
            case .upcoming: upR.append(row)
            }
        }
        pastR.sort { ($0.scheduledAtDate ?? .distantPast) > ($1.scheduledAtDate ?? .distantPast) }
        todayR.sort { ($0.scheduledAtDate ?? .distantFuture) < ($1.scheduledAtDate ?? .distantFuture) }
        upR.sort { ($0.scheduledAtDate ?? .distantFuture) < ($1.scheduledAtDate ?? .distantFuture) }
        let pastItems = Self.buildPastItems(from: pastR)
        return Self(past: pastR, pastItems: pastItems, today: todayR, upcoming: upR)
    }

    @MainActor
    static func build(
        from rows: [ConsumerBookingSimpleRow],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Self {
        build(
            from: rows,
            now: now,
            calendar: calendar,
            timingMode: PlatformFrontendConfigStore.shared.paymentTimingMode
        )
    }

    /// Groups past bookings by provider; multiple with the same provider become one `.group`, singles stay `.single`.
    private static func buildPastItems(from past: [ConsumerBookingSimpleRow]) -> [PastBookingsListItem] {
        var buckets: [String: [ConsumerBookingSimpleRow]] = [:]
        for row in past {
            let k = row.providerGroupingKey
            buckets[k, default: []].append(row)
        }
        let orderedKeys: [String] = buckets
            .map { key, rows -> (String, Date) in
                let newest = rows.compactMap(\.scheduledAtDate).max() ?? .distantPast
                return (key, newest)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        var out: [PastBookingsListItem] = []
        out.reserveCapacity(orderedKeys.count)
        for key in orderedKeys {
            guard var rows = buckets[key], !rows.isEmpty else { continue }
            rows.sort { ($0.scheduledAtDate ?? .distantPast) > ($1.scheduledAtDate ?? .distantPast) }
            if rows.count == 1, let one = rows.first {
                out.append(.single(one))
                continue
            }
            let name = rows
                .compactMap { $0.barberName?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Provider"
            let avatar = rows
                .compactMap(\.barberAvatar)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let g = ConsumerPastProviderGroup(
                id: key,
                providerDisplayName: name,
                barberAvatar: avatar,
                bookings: rows
            )
            out.append(.group(g))
        }
        return out
    }
}

extension PastBookingsListItem {
    var itemId: String {
        switch self {
        case .single(let r):
            return "past-single-\(r.id)"
        case .group(let g):
            return "past-group-\(g.id)"
        }
    }
}
