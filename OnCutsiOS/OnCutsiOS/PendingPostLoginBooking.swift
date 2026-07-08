//
//  PendingPostLoginBooking.swift
//  Intera
//
//  When a guest reaches booking review and taps submit, we prompt sign-in.
//  If `NavigationPath` resets while OAuth is up, we keep `BookingState` here until
//  auth completes (then submit) or the user closes the booking sheet as a guest.
//

import Foundation

@MainActor
enum PendingPostLoginBooking {
    private static var pending: (providerId: String, booking: BookingState)?

    /// Where sign-in was launched from (only **booking review** stashes here; Profile / Messages OAuth does not).
    enum ActiveSignInSurface: Equatable {
        case none
        case bookingReviewAwaitingAuth(barberId: String)

        var isWithinBookingFlow: Bool {
            switch self {
            case .none: return false
            case .bookingReviewAwaitingAuth: return true
            }
        }
    }

    static var activeSignInSurface: ActiveSignInSurface {
        guard let p = pending else { return .none }
        return .bookingReviewAwaitingAuth(barberId: p.providerId)
    }

    /// True while a guest left booking at **review** to complete OAuth.
    static var isBookingSignInInterruptionActive: Bool {
        pending != nil
    }

    static func stashForSignIn(providerId: String, booking: BookingState) {
        pending = (providerId, booking)
    }

    static func peekIfMatches(providerId: String) -> BookingState? {
        guard let entry = pending, entry.providerId == providerId else { return nil }
        return entry.booking
    }

    /// Returns the stashed booking once if `providerId` matches, then clears.
    static func consumeIfMatches(providerId: String) -> BookingState? {
        guard let entry = pending, entry.providerId == providerId else { return nil }
        pending = nil
        return entry.booking
    }

    /// Booking UI closed (e.g. user dismissed sheet) while still a guest — drop incomplete intent for this barber.
    static func clearIfGuestClosedBooking(providerId: String, isAuthenticated: Bool) {
        guard !isAuthenticated else { return }
        clearIfMatches(providerId: providerId)
    }

    static func clearIfMatches(providerId: String) {
        guard let entry = pending, entry.providerId == providerId else { return }
        pending = nil
    }
}
