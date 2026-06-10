//
//  PushNotificationAPI.swift
//  Intera
//
//  Registers the APNs device token with CampusCuts (`POST /api/v1/notifications/register-device`).
//

import Foundation
import OSLog

enum PushNotificationAPI {
    private static let log = Logger(subsystem: "com.intera", category: "PushNotificationAPI")
    private static func throwIfHTTPError(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(
                domain: "PushNotificationAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }

    /// Hex-encoded APNs device token (what the Node `apn` provider expects for iOS).
    static func registerDevice(deviceTokenHex: String, bearerToken: String) async throws {
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/notifications/register-device") else {
            throw URLError(.badURL)
        }
        log.notice("Starting POST register-device host=\(url.host ?? "?", privacy: .public) path=\(url.path, privacy: .public)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let body: [String: String] = [
            "deviceToken": deviceTokenHex,
            "platform": "ios",
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
    }

    /// - Parameter logoutSince: Moment logout began (UTC). Server only deactivates if the row was not
    ///   updated by a newer `register-device` after this time — prevents a stale unregister from racing past re-login.
    static func unregisterDevice(deviceTokenHex: String, bearerToken: String, logoutSince: Date) async throws {
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/notifications/unregister-device") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body: [String: String] = [
            "deviceToken": deviceTokenHex,
            "logoutSince": formatter.string(from: logoutSince),
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
    }
}
