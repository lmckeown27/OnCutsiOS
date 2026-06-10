//
//  UserSession.swift
//  Intera
//
//  Created by Liam McKeown on 3/8/26.
//

import Foundation

/// How the user authenticated for this session (drives App Store Guideline 4 — no manual name/email after Sign in with Apple).
public enum UserSessionSignInProvider: String, Codable, Sendable, Equatable {
    case emailPassword
    case apple
    case google
    /// Restored sessions from builds before this field existed.
    case unknown
}

/// Represents an authenticated user's session data
/// This should match your AWS Cognito/Stripe user structure
public struct UserSession: Sendable {
    public let userId: String
    public let token: String
    /// Optional refresh token from the backend (stored in Keychain via `CampusCutsAuthTokenStore` when present).
    public let refreshToken: String?
    public let email: String
    public let displayName: String
    public let role: UserRole
    public let stripeCustomerId: String?
    public let profileImageURL: String?
    public let expiresAt: Date
    public let signInProvider: UserSessionSignInProvider

    public init(
        userId: String,
        token: String,
        email: String,
        displayName: String,
        role: UserRole,
        stripeCustomerId: String?,
        profileImageURL: String?,
        expiresAt: Date,
        refreshToken: String? = nil,
        signInProvider: UserSessionSignInProvider = .unknown
    ) {
        self.userId = userId
        self.token = token
        self.refreshToken = refreshToken
        self.email = email
        self.displayName = displayName
        self.role = role
        self.stripeCustomerId = stripeCustomerId
        self.profileImageURL = profileImageURL
        self.expiresAt = expiresAt
        self.signInProvider = signInProvider
    }

    /// True while the access token is valid, or a refresh token can still renew the session.
    public var isValid: Bool {
        let skew: TimeInterval = 60
        if Date().addingTimeInterval(skew) < expiresAt { return true }
        if let refreshToken,
           !refreshToken.isEmpty,
           let refreshExp = JWTExpiration.expirationDate(refreshToken),
           Date().addingTimeInterval(skew) < refreshExp {
            return true
        }
        return false
    }

    /// Access token is expired (or will be within `skew`) but refresh may still work.
    public var needsAccessTokenRefresh: Bool {
        let skew: TimeInterval = 60
        guard Date().addingTimeInterval(skew) >= expiresAt else { return false }
        guard let refreshToken, !refreshToken.isEmpty else { return false }
        guard let refreshExp = JWTExpiration.expirationDate(refreshToken) else { return true }
        return Date().addingTimeInterval(skew) < refreshExp
    }

    /// Time remaining until token expiration
    public var timeUntilExpiration: TimeInterval {
        expiresAt.timeIntervalSince(Date())
    }
}

extension UserSession: Codable {
    private enum CodingKeys: String, CodingKey {
        case userId, token, refreshToken, email, displayName, role
        case stripeCustomerId, profileImageURL, expiresAt, signInProvider
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        token = try c.decode(String.self, forKey: .token)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        email = try c.decode(String.self, forKey: .email)
        displayName = try c.decode(String.self, forKey: .displayName)
        role = try c.decode(UserRole.self, forKey: .role)
        stripeCustomerId = try c.decodeIfPresent(String.self, forKey: .stripeCustomerId)
        profileImageURL = try c.decodeIfPresent(String.self, forKey: .profileImageURL)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        signInProvider = try c.decodeIfPresent(UserSessionSignInProvider.self, forKey: .signInProvider) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userId, forKey: .userId)
        try c.encode(token, forKey: .token)
        try c.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try c.encode(email, forKey: .email)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(role, forKey: .role)
        try c.encodeIfPresent(stripeCustomerId, forKey: .stripeCustomerId)
        try c.encodeIfPresent(profileImageURL, forKey: .profileImageURL)
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encode(signInProvider, forKey: .signInProvider)
    }
}

/// User roles for CampusCuts
public enum UserRole: String, Codable, Sendable {
    case student
    case barber
    case admin

    public var displayName: String {
        switch self {
        case .student: return "Student"
        case .barber: return "Barber"
        case .admin: return "Admin"
        }
    }
}

// MARK: - Mock Data for Development
extension UserSession {
    public static let mock = UserSession(
        userId: "mock-user-123",
        token: "mock-jwt-token",
        email: "student@campuscuts.com",
        displayName: "Alex Johnson",
        role: .student,
        stripeCustomerId: "cus_mock123",
        profileImageURL: nil,
        expiresAt: Date().addingTimeInterval(3600), // 1 hour from now
        refreshToken: nil,
        signInProvider: .unknown
    )

    public static let mockBarber = UserSession(
        userId: "barber-456",
        token: "mock-barber-token",
        email: "barber@campuscuts.com",
        displayName: "Jordan Smith",
        role: .barber,
        stripeCustomerId: "cus_barber456",
        profileImageURL: nil,
        expiresAt: Date().addingTimeInterval(3600),
        refreshToken: nil,
        signInProvider: .unknown
    )
}
