//
//  JWTExpiration.swift
//  OnCuts
//
//  Reads `exp` from JWT payloads without verifying signatures (client-side scheduling only).
//

import Foundation

enum JWTExpiration {
    /// Returns the `exp` claim as a `Date`, or `nil` when the token is not a decodable JWT.
    static func expirationDate(_ jwt: String) -> Date? {
        let trimmed = jwt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let segments = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval
        else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    static func isExpired(_ jwt: String, skew: TimeInterval = 60) -> Bool {
        guard let expiration = expirationDate(jwt) else { return true }
        return Date().addingTimeInterval(skew) >= expiration
    }
}

extension UserSession {
    /// Preferred access-token expiry; falls back to refresh JWT `exp`, then 7 days.
    static func preferredAccessExpiration(accessToken: String, refreshToken: String?) -> Date {
        if let accessExp = JWTExpiration.expirationDate(accessToken) {
            return accessExp
        }
        if let refreshToken, let refreshExp = JWTExpiration.expirationDate(refreshToken) {
            return refreshExp
        }
        return Date().addingTimeInterval(60 * 60 * 24 * 7)
    }
}
