//
//  PushDeviceRegistration.swift
//  OnCuts
//
//  Persists the APNs token and syncs it with the backend when a JWT is available.
//

import Foundation
import OSLog
import OnCutsModule
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

enum PushDeviceRegistration {
    private static let log = Logger(subsystem: "com.oncuts", category: "PushRegistration")
    private static let apnsHexDefaultsKey = "com.intera.push.apnsHexToken"

    /// Suppresses duplicate `POST /register-device` when `didRegisterForRemoteNotifications` and
    /// `refreshRemoteRegistrationAndRetryBackend` fire close together (or SwiftUI re-evaluates often).
    private static let throttleLock = NSLock()
    private static var lastSuccessfulBackendRegister: (hex: String, jwt: String, at: Date)?
    /// Minimum interval between successful backend registrations for the same token + JWT.
    private static let minRegisterInterval: TimeInterval = 120

    /// Hex string from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    static var storedAPNsHexToken: String? {
        get {
            let s = UserDefaults.standard.string(forKey: apnsHexDefaultsKey)
            return (s?.isEmpty == false) ? s : nil
        }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: apnsHexDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: apnsHexDefaultsKey)
            }
        }
    }

    static func persistAPNsDeviceToken(_ data: Data) {
        let hex = data.map { String(format: "%02.2hhx", $0) }.joined()
        storedAPNsHexToken = hex
        let prefix = String(hex.prefix(16))
        log.info("APNs device token stored length=\(hex.count) prefix=\(prefix)…")
    }

    /// Call after login or when the device token is first received.
    /// Pass `bearerToken` from `UserSession.token` when available so push registration uses the same JWT as other API calls (keychain can lag some sign-in paths).
    static func registerStoredTokenWithBackendIfPossible(bearerToken: String? = nil) async {
        guard let hex = storedAPNsHexToken else {
            log.notice("register-device skipped: no APNs hex yet (waiting for system didRegisterForRemoteNotifications)")
            return
        }
        let jwt = bearerToken ?? OnCutsAuthTokenStore.loadAccessToken()
        guard let jwt, !jwt.isEmpty else {
            log.notice("register-device skipped: no JWT (session token or OnCutsAuthTokenStore)")
            return
        }

        throttleLock.lock()
        let skip: Bool
        if let last = lastSuccessfulBackendRegister,
           last.hex == hex,
           last.jwt == jwt,
           Date().timeIntervalSince(last.at) < minRegisterInterval
        {
            skip = true
        } else {
            skip = false
        }
        throttleLock.unlock()
        if skip {
            log.notice("register-device skipped (throttled: same token+JWT within \(Int(minRegisterInterval))s)")
            return
        }

        do {
            try await PushNotificationAPI.registerDevice(deviceTokenHex: hex, bearerToken: jwt)
            log.notice("register-device succeeded for OnCuts API")
            throttleLock.lock()
            lastSuccessfulBackendRegister = (hex, jwt, Date())
            throttleLock.unlock()
        } catch {
            log.error("register-device failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// After login, ask the system for a push token again and retry `registerStoredTokenWithBackendIfPossible` (JWT now available).
    #if os(iOS) || os(visionOS)
    static func refreshRemoteRegistrationAndRetryBackend(bearerToken: String? = nil) {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        // `didRegisterForRemoteNotifications` will call `registerStoredTokenWithBackendIfPossible` with throttling.
        // Still schedule one explicit attempt for the case where the system does not re-invoke the delegate (cached token).
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await registerStoredTokenWithBackendIfPossible(bearerToken: bearerToken)
        }
    }
    #endif

    /// Call before clearing auth (e.g. logout). Pass the same `logoutSince` you captured at the instant logout began.
    static func unregisterStoredTokenFromBackendIfPossible(logoutSince: Date) async {
        guard let hex = storedAPNsHexToken else { return }
        guard let token = OnCutsAuthTokenStore.loadAccessToken(), !token.isEmpty else { return }
        try? await PushNotificationAPI.unregisterDevice(deviceTokenHex: hex, bearerToken: token, logoutSince: logoutSince)
    }
}
