//
//  UpcomingBookingAppBadge.swift
//  OnCuts
//
//  Syncs the home-screen app icon badge with active upcoming/today consumer bookings.
//

import Foundation

#if os(iOS)
import UIKit

enum UpcomingBookingAppBadge {
    /// **ACCEPTED** upcoming/today only — not outgoing PENDING requests.
    @MainActor
    static func syncFromConsumerRows(_ rows: [ConsumerBookingSimpleRow]) {
        let n = rows.upcomingBookingNotificationBadgeCount
        UIApplication.shared.applicationIconBadgeNumber = min(max(0, n), 999)
    }
}
#endif

extension Array where Element == ConsumerBookingSimpleRow {
    /// **PENDING** / **ACCEPTED** bookings whose `scheduleSegment()` is **Today** or **Upcoming** (excludes past-time slots).
    /// Includes the consumer’s own open requests (for “has an active booking” / UI gating, not for notification badges).
    @MainActor
    var upcomingActiveBookingCount: Int {
        let timing = PlatformFrontendConfigStore.shared.paymentTimingMode
        return filter { row in
            let u = row.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard u == "PENDING" || u == "ACCEPTED" else { return false }
            return row.scheduleSegment(timingMode: timing) != .past
        }.count
    }

    /// **ACCEPTED** only, today/upcoming — notification-style indicators; excludes PENDING requests the user submitted.
    @MainActor
    var upcomingBookingNotificationBadgeCount: Int {
        let timing = PlatformFrontendConfigStore.shared.paymentTimingMode
        return filter { row in
            let u = row.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard u == "ACCEPTED" else { return false }
            return row.scheduleSegment(timingMode: timing) != .past
        }.count
    }
}
