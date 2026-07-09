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
    private static let apnsHexDefaultsKey = "com.oncuts.push.apnsHexToken"

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

    /// Retries registration when the JWT or APNs token is not ready yet (common at cold launch).
    static func registerWithRetries(bearerToken: String? = nil, maxAttempts: Int = 4) async {
        let delaysNs: [UInt64] = [0, 400_000_000, 900_000_000, 1_800_000_000]
        for attempt in 0 ..< maxAttempts {
            if attempt > 0 {
                let delay = delaysNs[min(attempt, delaysNs.count - 1)]
                try? await Task.sleep(nanoseconds: delay)
            }
            let ignoreThrottle = attempt > 0
            if await registerStoredTokenWithBackendIfPossible(bearerToken: bearerToken, ignoreThrottle: ignoreThrottle) {
                return
            }
        }
    }

    /// Call after login or when the device token is first received.
    /// Pass `bearerToken` from `UserSession.token` when available so push registration uses the same JWT as other API calls (keychain can lag some sign-in paths).
    @discardableResult
    static func registerStoredTokenWithBackendIfPossible(
        bearerToken: String? = nil,
        ignoreThrottle: Bool = false
    ) async -> Bool {
        guard let hex = storedAPNsHexToken else {
            log.notice("register-device skipped: no APNs hex yet (waiting for system didRegisterForRemoteNotifications)")
            return false
        }
        var jwt = bearerToken ?? OnCutsAuthTokenStore.loadAccessToken()
        if jwt?.isEmpty != false {
            log.notice("register-device skipped: no JWT (session token or OnCutsAuthTokenStore)")
            return false
        }

        if !ignoreThrottle {
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
                return true
            }
        }

        do {
            try await PushNotificationAPI.registerDevice(deviceTokenHex: hex, bearerToken: jwt!)
            log.notice("register-device succeeded for OnCuts API")
            throttleLock.lock()
            lastSuccessfulBackendRegister = (hex, jwt!, Date())
            throttleLock.unlock()
            return true
        } catch {
            if PushNotificationAPI.isUnauthorizedHTTPError(error) {
                let refreshed = await recoverSessionAfterUnauthorizedIfPossible()
                if refreshed, let retryJWT = OnCutsAuthTokenStore.loadAccessToken(), !retryJWT.isEmpty {
                    jwt = retryJWT
                    do {
                        try await PushNotificationAPI.registerDevice(deviceTokenHex: hex, bearerToken: retryJWT)
                        log.notice("register-device succeeded after session refresh")
                        throttleLock.lock()
                        lastSuccessfulBackendRegister = (hex, retryJWT, Date())
                        throttleLock.unlock()
                        return true
                    } catch {
                        log.error("register-device failed after session refresh: \(error.localizedDescription, privacy: .public)")
                        return false
                    }
                }
            }
            log.error("register-device failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @MainActor
    private static func recoverSessionAfterUnauthorizedIfPossible() async -> Bool {
        await OnCutsSessionSync.appSessionManager?.recoverSessionAfterUnauthorized() ?? false
    }

    /// After login or resume, ask the system for a push token again and retry backend registration (JWT now available).
    #if os(iOS) || os(visionOS)
    static func refreshRemoteRegistrationAndRetryBackend(bearerToken: String? = nil) {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        Task {
            await registerWithRetries(bearerToken: bearerToken)
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
