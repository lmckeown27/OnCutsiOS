//
//  InteraAppDelegate.swift
//  Intera
//
//  Firebase (and Google Sign-In) startup on iOS / iPadOS / visionOS / Mac Catalyst.
//  Remote notifications: APNs + Firebase Messaging, registration with CampusCuts API.
//

#if canImport(UIKit) && !os(watchOS)
import FirebaseCore
import FirebaseMessaging
import OSLog
import UserNotifications
import UIKit

private let interaPushDelegateLog = Logger(subsystem: "com.intera", category: "AppDelegate")

/// Registers with `UIApplicationDelegateAdaptor` so `FirebaseApp.configure()` runs at process launch.
/// `GIDSignIn` is configured from `CLIENT_ID` in `GoogleService-Info.plist` via `GoogleSignInAppSupport`.
final class InteraAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        GoogleSignInAppSupport.configure()
        configureRemoteNotifications(application)
        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Self.postMessageNotificationNavigationIfNeeded(from: remote)
                Self.postConsumerBookingsRefreshIfNeeded(from: remote)
                Self.postOpenBookingDetailIfNeeded(from: remote)
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if os(iOS) || os(visionOS)
        let hex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        interaPushDelegateLog.notice("APNs device token received length=\(hex.count) prefix=\(String(hex.prefix(16)))…")
        Messaging.messaging().apnsToken = deviceToken
        PushDeviceRegistration.persistAPNsDeviceToken(deviceToken)
        Task {
            await PushDeviceRegistration.registerStoredTokenWithBackendIfPossible(bearerToken: nil)
        }
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        interaPushDelegateLog.error("APNs registerForRemoteNotifications failed: \(error.localizedDescription)")
    }

    /// Required when `FirebaseAppDelegateProxyEnabled` is false: forward remote payloads to Firebase Messaging.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if let dict = userInfo as? [String: Any] {
            _ = Messaging.messaging().appDidReceiveMessage(dict)
        }
        completionHandler(.newData)
    }

    private func configureRemoteNotifications(_ application: UIApplication) {
        #if os(iOS) || os(visionOS)
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, error in
            if let error {
                interaPushDelegateLog.error("Notification permission request failed: \(error.localizedDescription)")
            } else {
                interaPushDelegateLog.notice("Notification permission granted=\(granted)")
            }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        #endif
    }
}

#if os(iOS) || os(visionOS)
extension InteraAppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Self.postMessageNotificationNavigationIfNeeded(from: userInfo)
        Self.postConsumerBookingsRefreshIfNeeded(from: userInfo)
        Self.postOpenBookingDetailIfNeeded(from: userInfo)
        completionHandler()
    }

    private static func flattenRemoteNotificationUserInfo(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var flat: [String: Any] = [:]
        for (k, v) in userInfo {
            if let ks = k as? String { flat[ks] = v }
        }
        if let data = flat["data"] as? [String: Any] {
            for (k, v) in data { flat[k] = v }
        }
        return flat
    }

    /// Routes message push taps: `conversationId` is set by `pushNotification.service` on the backend.
    private static func postMessageNotificationNavigationIfNeeded(from userInfo: [AnyHashable: Any]) {
        let flat = flattenRemoteNotificationUserInfo(userInfo)
        let type = (flat["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard type == "message" else { return }
        let raw = flat["conversationId"]
        let cid: String? = {
            if let s = raw as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let n = raw as? NSNumber { return n.stringValue }
            if let i = raw as? Int { return String(i) }
            return nil
        }()
        guard let cid, !cid.isEmpty else { return }
        NotificationCenter.default.post(
            name: .interaOpenMessagingConversation,
            object: nil,
            userInfo: ["conversationId": cid]
        )
    }

    /// When the user opens a **booking / payment** push (not chat), refetch consumer bookings so `ChatViewModel.syncPaymentTakeover` can present `ConsumerPaymentTakeoverView` (Socket `booking-completed` is often missed after resume).
    private static func postConsumerBookingsRefreshIfNeeded(from userInfo: [AnyHashable: Any]) {
        let flat = flattenRemoteNotificationUserInfo(userInfo)
        let type = (flat["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if type == "message" { return }

        if flat["bookingId"] != nil || flat["booking_id"] != nil {
            NotificationCenter.default.post(name: .consumerBookingsListShouldRefresh, object: nil)
            return
        }

        let bookingRelatedTypes: Set<String> = [
            "payment_request",
            "booking_confirmation",
            "booking_confirmed",
            "booking_reminder",
            "booking_accepted",
            "booking_cancelled",
            "system",
        ]
        if bookingRelatedTypes.contains(type) {
            NotificationCenter.default.post(name: .consumerBookingsListShouldRefresh, object: nil)
        }
    }

    private static func bookingIdFromPayload(_ flat: [String: Any]) -> String? {
        let raw = flat["bookingId"] ?? flat["booking_id"]
        let s: String? = {
            if let x = raw as? String { return x.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let n = raw as? NSNumber { return n.stringValue }
            if let i = raw as? Int { return String(i) }
            return nil
        }()
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    /// Booking status pushes (`booking_confirmation`, `booking_cancelled`, `booking_reminder`, etc.): deep-link to `ConsumerBookingDetailView` for `bookingId`.
    private static func postOpenBookingDetailIfNeeded(from userInfo: [AnyHashable: Any]) {
        let flat = flattenRemoteNotificationUserInfo(userInfo)
        let type = (flat["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if type == "message" { return }
        guard let bid = bookingIdFromPayload(flat) else { return }

        let opensDetailTypes: Set<String> = [
            "booking_confirmation",
            "booking_confirmed",
            "booking_reminder",
            "booking_accepted",
            "booking_cancelled",
            "payment_request",
            "system",
        ]
        guard opensDetailTypes.contains(type) else { return }

        NotificationCenter.default.post(
            name: .interaOpenBookingDetail,
            object: nil,
            userInfo: ["bookingId": bid]
        )
    }
}

extension InteraAppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // CampusCuts currently delivers iOS pushes via APNs using the hex token from `register-device`.
        // FCM token is still refreshed here for Firebase Console / future use.
        _ = fcmToken
    }
}
#endif
#endif
