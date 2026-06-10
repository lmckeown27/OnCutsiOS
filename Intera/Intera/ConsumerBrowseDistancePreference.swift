//
//  ConsumerBrowseDistancePreference.swift
//  Intera
//
//  Persisted max search radius (miles) for GET /barbers when lat/lng are sent (iOS).
//

import Foundation

extension Notification.Name {
    /// Posted when the user changes **Maximum distance** on the browse screen.
    static let consumerBrowseMaxDistanceDidChange = Notification.Name("consumerBrowseMaxDistanceDidChange")
    /// Posted after a thread is loaded and marked read so global message badges can refetch `GET /messages/unread-count`.
    static let messagingUnreadCountShouldRefresh = Notification.Name("messagingUnreadCountShouldRefresh")
    /// Posted after the user blocks someone so inbox lists refetch and hide that counterparty immediately.
    static let messagingBlockedUserDidChange = Notification.Name("messagingBlockedUserDidChange")
    /// Posted when the user opens a **message** push notification; `userInfo["conversationId"]` is the thread id.
    static let interaOpenMessagingConversation = Notification.Name("interaOpenMessagingConversation")
    /// Posted when the user opens a **booking status** push (confirmed, reminder, cancelled, etc.); `userInfo["bookingId"]` opens `ConsumerBookingDetailView`.
    static let interaOpenBookingDetail = Notification.Name("interaOpenBookingDetail")
    /// Posted after the consumer successfully pays (card or cash) so the app returns to Home and clears booking-detail navigation (paid booking is past / detail would error).
    static let interaNavigateToConsumerHomeAfterPayment = Notification.Name("interaNavigateToConsumerHomeAfterPayment")
    /// Posted when the hub switches to the **Messages** tab so ``ConsumerBookingsHubView`` pops booking detail / thread (same as leaving Bookings for Messages).
    static let consumerBookingsHubShouldPopToRoot = Notification.Name("consumerBookingsHubShouldPopToRoot")
}

enum ConsumerBrowseDistancePreference {
    private static let key = "consumer.browse.maxDistanceMiles"
    private static let constrainKey = "consumer.browse.constrainListByDistance"

    static let minimumMiles: Double = 1
    static let maximumMiles: Double = 100
    /// Within 1…100 mi; default 25 mi when no valid preference is stored.
    static let defaultMiles: Double = 25

    /// When `false`, `GET /barbers` is called **without** `lat`/`lng` so the server returns the full consumer list (rating order), same as before location-aware browse.
    static var constrainBrowseListByDistance: Bool {
        get {
            if UserDefaults.standard.object(forKey: constrainKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: constrainKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: constrainKey)
            NotificationCenter.default.post(name: .consumerBrowseMaxDistanceDidChange, object: nil)
        }
    }

    static var maxDistanceMiles: Double {
        get {
            let v = UserDefaults.standard.double(forKey: key)
            if v == 0 || v < minimumMiles || v > maximumMiles {
                return defaultMiles
            }
            return v
        }
        set {
            let clamped = min(maximumMiles, max(minimumMiles, newValue))
            UserDefaults.standard.set(clamped, forKey: key)
            NotificationCenter.default.post(name: .consumerBrowseMaxDistanceDidChange, object: nil)
        }
    }

    /// Kilometers for `GET /barbers?maxDistance=` (backend expects km).
    static func maxDistanceKmForLocationQuery() -> Double {
        maxDistanceMiles * 1.60934
    }
}
