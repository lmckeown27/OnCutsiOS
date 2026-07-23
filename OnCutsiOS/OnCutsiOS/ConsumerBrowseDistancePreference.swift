//
//  ConsumerBrowseDistancePreference.swift
//  OnCuts
//
//  Persisted max search radius (miles) for GET /barbers when lat/lng are sent (iOS).
//

import Foundation

extension Notification.Name {
    /// Posted when the user changes **Maximum distance** on the browse screen.
    static let consumerBrowseMaxDistanceDidChange = Notification.Name("consumerBrowseMaxDistanceDidChange")
    /// Posted when device tracking or the manual browse place changes (Home should reload providers).
    static let consumerBrowseLocationDidChange = Notification.Name("consumerBrowseLocationDidChange")
    /// Posted after a thread is loaded and marked read so global message badges can refetch `GET /messages/unread-count`.
    static let messagingUnreadCountShouldRefresh = Notification.Name("messagingUnreadCountShouldRefresh")
    /// Posted after the user blocks someone so inbox lists refetch and hide that counterparty immediately.
    static let messagingBlockedUserDidChange = Notification.Name("messagingBlockedUserDidChange")
    /// Posted when the user opens a **message** push notification; `userInfo["conversationId"]` is the thread id.
    static let onCutsOpenMessagingConversation = Notification.Name("onCutsOpenMessagingConversation")
    /// Posted when the user opens a **booking status** push (confirmed, reminder, cancelled, etc.); `userInfo["bookingId"]` opens `ConsumerBookingDetailView`.
    static let onCutsOpenBookingDetail = Notification.Name("onCutsOpenBookingDetail")
    /// Posted after the consumer successfully pays (card or cash) so the app returns to Home and clears booking-detail navigation (paid booking is past / detail would error).
    static let onCutsNavigateToConsumerHomeAfterPayment = Notification.Name("onCutsNavigateToConsumerHomeAfterPayment")
    /// Posted when the hub switches to the **Messages** tab so ``ConsumerBookingsHubView`` pops booking detail / thread (same as leaving Bookings for Messages).
    static let consumerBookingsHubShouldPopToRoot = Notification.Name("consumerBookingsHubShouldPopToRoot")
}

/// Parses push / deep-link payload fields from `NotificationCenter` `userInfo`.
enum OnCutsPushNavigationPayload {
    static func conversationId(from userInfo: [AnyHashable: Any]?) -> String? {
        guard let userInfo else { return nil }
        var flat: [String: Any] = [:]
        for (key, value) in userInfo {
            if let key = key as? String {
                flat[key] = value
            }
        }
        if let nested = flat["data"] as? [String: Any] {
            for (key, value) in nested {
                flat[key] = value
            }
        }
        for key in ["conversationId", "conversation_id"] {
            let raw = flat[key]
            let parsed: String? = {
                if let s = raw as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let n = raw as? NSNumber { return n.stringValue }
                if let i = raw as? Int { return String(i) }
                return nil
            }()
            if let parsed, !parsed.isEmpty { return parsed }
        }
        return nil
    }
}

/// Saved town/place used when device tracking is off (web key: `oncuts_selected_college_town`).
struct ConsumerBrowsePlace: Codable, Hashable, Sendable {
    var label: String
    var latitude: Double
    var longitude: Double

    var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ConsumerBrowseDistancePreference {
    private static let key = "consumer.browse.maxDistanceMiles"
    private static let constrainKey = "consumer.browse.constrainListByDistance"
    private static let deviceTrackingKey = "consumer.browse.deviceTracking"
    private static let manualPlaceKey = "oncuts_selected_college_town"

    static let minimumMiles: Double = 1
    static let maximumMiles: Double = 100
    /// Within 1…100 mi; default 25 mi when no valid preference is stored.
    static let defaultMiles: Double = 25

    /// When `true` (default), browse center prefers device GPS; when `false`, uses ``manualPlace``.
    static var deviceTrackingEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: deviceTrackingKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: deviceTrackingKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: deviceTrackingKey)
            NotificationCenter.default.post(name: .consumerBrowseLocationDidChange, object: nil)
        }
    }

    /// Manually chosen place (city/town) for browse centering when tracking is off.
    static var manualPlace: ConsumerBrowsePlace? {
        get {
            guard let data = UserDefaults.standard.data(forKey: manualPlaceKey) else { return nil }
            return try? JSONDecoder().decode(ConsumerBrowsePlace.self, from: data)
        }
        set {
            if let newValue {
                if let data = try? JSONEncoder().encode(newValue) {
                    UserDefaults.standard.set(data, forKey: manualPlaceKey)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: manualPlaceKey)
            }
            NotificationCenter.default.post(name: .consumerBrowseLocationDidChange, object: nil)
        }
    }

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
