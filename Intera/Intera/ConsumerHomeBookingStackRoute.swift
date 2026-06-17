//
//  ConsumerHomeBookingStackRoute.swift
//  Intera
//
//  Single `Hashable` type for booking detail **and** booking-thread pushes on the same `NavigationStack`.
//  **Detail routes store only `bookingId` + `presentationID`**, not full `ConsumerBookingSimpleRow`, so a
//  `bookings-simple` refresh cannot change the hash of path entries and tear down navigation.
//
//  **Bookings / home detail → Messages:** append `.messagingThread` on the stack’s `NavigationPath` (never `navigationDestination(item:)` on a path-backed stack).
//  Empty-path browse chat on the home shell uses ``homeStackMessagingHandoff`` + `navigationDestination(item:)` while `navigationPath` is empty.

import Foundation
import SwiftUI

enum ConsumerHomeBookingStackRoute: Hashable {
    case detail(bookingId: String, presentationID: UUID)
    /// Pushed above `.detail` so back returns to `ConsumerBookingDetailView` with a normal slide transition.
    case messagingThread(ChatViewModel.BookingMessagingThreadHandoff)
}

extension ConsumerHomeBookingStackRoute {
    /// Bookings timeline / shared “open detail” entry — deterministic `presentationID` for stable `NavigationLink(value:)`.
    static func bookingsTabDetail(_ row: ConsumerBookingSimpleRow) -> ConsumerHomeBookingStackRoute {
        .detail(bookingId: row.id, presentationID: stablePresentationID(forBookingId: row.id))
    }

    static func stablePresentationID(forBookingId raw: String) -> UUID {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = UUID(uuidString: id) { return u }
        var digest = [UInt8](repeating: 0, count: 16)
        for (i, b) in Data(id.utf8).enumerated() {
            digest[i % 16] ^= b
        }
        digest[6] = (digest[6] & 0x0F) | 0x40
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}

extension NavigationPath {
    /// Pushes (or replaces) the booking thread segment above booking detail. Path-only — safe on `NavigationStack(path:)`.
    mutating func interaAppendBookingMessagingThread(_ handoff: ChatViewModel.BookingMessagingThreadHandoff) {
        if count > 1 {
            removeLast()
        }
        append(ConsumerHomeBookingStackRoute.messagingThread(handoff))
    }
}
