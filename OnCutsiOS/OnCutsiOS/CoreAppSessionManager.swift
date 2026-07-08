//
//  AppSessionManager.swift
//  Intera
//
//  Created by Liam McKeown on 3/8/26.
//

import Foundation
import Observation
import OnCutsModule
#if canImport(UIKit) && os(iOS)
import UIKit
#endif

/// Central session manager that tracks authentication state across the app
/// This is the "Brain" of your Shell app
@Observable
@MainActor
public final class AppSessionManager {
    
    // MARK: - Published State
    
    /// Current user session, nil if not authenticated
    public private(set) var currentSession: UserSession?
    
    /// Computed property for authentication status
    public var isAuthenticated: Bool {
        guard let session = currentSession else { return false }
        return session.isValid
    }
    
    /// The current user's role (if authenticated)
    public var userRole: UserRole? {
        currentSession?.role
    }
    
    // MARK: - Private Properties
    
    private let keychainKey = "com.campuscuts.userSession"
    
    // Task stored separately to avoid observation tracking
    @ObservationIgnored private var _sessionTask: Task<Void, Never>?

    /// Push unregister started from `logout()` — cancelled on `login()` so it cannot deactivate after a fresh `register-device`.
    @ObservationIgnored private var _logoutUnregisterTask: Task<Void, Never>?

    @ObservationIgnored private var _refreshInFlight = false
    
    // MARK: - Initialization
    
    public init() {
        loadSessionFromKeychain()
        startSessionValidation()
    }
    
    deinit {
        _sessionTask?.cancel()
        _logoutUnregisterTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Authenticate user and store session
    public func login(session: UserSession) {
        _logoutUnregisterTask?.cancel()
        _logoutUnregisterTask = nil
        self.currentSession = session
        OnCutsAuthTokenStore.save(accessToken: session.token, refreshToken: session.refreshToken)
        saveSessionToKeychain()
        Task {
            #if os(iOS) || os(visionOS)
            PushDeviceRegistration.refreshRemoteRegistrationAndRetryBackend(bearerToken: session.token)
            #else
            await PushDeviceRegistration.registerStoredTokenWithBackendIfPossible(bearerToken: session.token)
            #endif
        }
    }
    
    /// Clear current session and log out
    public func logout() {
        let logoutSince = Date()
        let bearer = OnCutsAuthTokenStore.loadAccessToken()
        let apnsHex = PushDeviceRegistration.storedAPNsHexToken
        if let bearer, let apnsHex, !bearer.isEmpty {
            _logoutUnregisterTask?.cancel()
            _logoutUnregisterTask = Task.detached(priority: .utility) {
                try? await PushNotificationAPI.unregisterDevice(
                    deviceTokenHex: apnsHex,
                    bearerToken: bearer,
                    logoutSince: logoutSince
                )
            }
        }
        FirebaseAuthSignOutSupport.signOut()
        GoogleSignInAppSupport.signOut()
        OnCutsAuthTokenStore.clear()
        currentSession = nil
        clearSessionFromKeychain()
        #if os(iOS)
        UIApplication.shared.applicationIconBadgeNumber = 0
        #endif
    }

    /// Updates visible profile fields after a successful profile save (display name, email, avatar URL).
    public func applyProfileFromServer(displayName: String, email: String, profileImageURL: String?) {
        guard let session = currentSession else { return }
        currentSession = UserSession(
            userId: session.userId,
            token: session.token,
            email: email,
            displayName: displayName,
            role: session.role,
            stripeCustomerId: session.stripeCustomerId,
            profileImageURL: profileImageURL ?? session.profileImageURL,
            expiresAt: session.expiresAt,
            refreshToken: session.refreshToken,
            signInProvider: session.signInProvider
        )
        saveSessionToKeychain()
    }

    /// Loads `GET /users/:id` and merges `profile_picture_url` (and name/email) into the session so the toolbar matches photos uploaded on the platform.
    public func refreshProfileFromServer() async {
        guard let session = currentSession else { return }
        do {
            let p = try await UserProfileAPI.fetchProfile(userId: session.userId, bearerToken: session.token)
            let parts = [p.first_name, p.last_name]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let combined = parts.joined(separator: " ")
            let display = combined.isEmpty ? session.displayName : combined
            let em = p.email.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = em.isEmpty ? session.email : em
            let rawPic = p.profile_picture_url?.trimmingCharacters(in: .whitespacesAndNewlines)
            let pic = (rawPic?.isEmpty == false) ? rawPic : nil
            applyProfileFromServer(displayName: display, email: email, profileImageURL: pic)
        } catch {
            // Keep existing session on failure.
        }
    }
    
    /// Exchange the stored refresh token for a new access JWT and persist the session.
    public func refreshSession() async throws {
        guard let session = currentSession else {
            throw SessionError.noActiveSession
        }
        let refresh = session.refreshToken
            ?? OnCutsAuthTokenStore.loadRefreshToken()
        guard let refresh, !refresh.isEmpty else {
            throw SessionError.refreshFailed
        }

        let newAccess = try await SessionRefreshAPI.refreshAccessToken(refreshToken: refresh)
        applyRefreshedAccessToken(newAccess, refreshToken: refresh)
    }

    /// After a 401, attempt a silent refresh. Never signs the user out — only explicit Sign Out does that.
    @discardableResult
    public func recoverSessionAfterUnauthorized() async -> Bool {
        guard currentSession != nil else { return false }
        do {
            try await refreshSession()
            return true
        } catch {
            return false
        }
    }

    private func applyRefreshedAccessToken(_ accessToken: String, refreshToken: String) {
        guard let session = currentSession else { return }
        let refreshedSession = UserSession(
            userId: session.userId,
            token: accessToken,
            email: session.email,
            displayName: session.displayName,
            role: session.role,
            stripeCustomerId: session.stripeCustomerId,
            profileImageURL: session.profileImageURL,
            expiresAt: UserSession.preferredAccessExpiration(accessToken: accessToken, refreshToken: refreshToken),
            refreshToken: refreshToken,
            signInProvider: session.signInProvider
        )
        currentSession = refreshedSession
        OnCutsAuthTokenStore.save(accessToken: accessToken, refreshToken: refreshToken)
        saveSessionToKeychain()
    }
    
    // MARK: - Private Methods
    
    /// Proactively refresh access tokens before they expire; never auto-sign-out.
    private func startSessionValidation() {
        _sessionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if let session = self.currentSession {
                    if session.needsAccessTokenRefresh {
                        await self.refreshSessionIfNeeded(for: session)
                    } else if !session.isValid {
                        // Refresh token also expired — keep session until the user taps Sign Out.
                    }
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func refreshSessionIfNeeded(for session: UserSession) async {
        guard session.needsAccessTokenRefresh else { return }
        guard !_refreshInFlight else { return }
        _refreshInFlight = true
        defer { _refreshInFlight = false }
        do {
            try await refreshSession()
        } catch {
            // Leave the user signed in; they can use Sign Out or sign in again manually.
        }
    }
    
    /// Save session to Keychain (secure storage)
    private func saveSessionToKeychain() {
        guard let session = currentSession else { return }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(session)
            
            // For production, use proper Keychain API
            // For now, using UserDefaults (NOT SECURE - use Keychain in production!)
            UserDefaults.standard.set(data, forKey: keychainKey)
        } catch {
            print("Failed to save session: \(error)")
        }
    }
    
    /// Load session from Keychain
    private func loadSessionFromKeychain() {
        guard let data = UserDefaults.standard.data(forKey: keychainKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            var session = try decoder.decode(UserSession.self, from: data)
            session = normalizedPersistedSession(session)

            if session.isValid {
                self.currentSession = session
                OnCutsAuthTokenStore.save(accessToken: session.token, refreshToken: session.refreshToken)
                Task {
                    if session.needsAccessTokenRefresh {
                        await self.refreshSessionIfNeeded(for: session)
                    }
                    let bearer = self.currentSession?.token ?? session.token
                    #if os(iOS) || os(visionOS)
                    PushDeviceRegistration.refreshRemoteRegistrationAndRetryBackend(bearerToken: bearer)
                    #else
                    await PushDeviceRegistration.registerStoredTokenWithBackendIfPossible(bearerToken: bearer)
                    #endif
                    await self.refreshProfileFromServer()
                }
            } else {
                clearSessionFromKeychain()
            }
        } catch {
            print("Failed to load session: \(error)")
            clearSessionFromKeychain()
        }
    }
    
    /// Clear session from Keychain
    private func clearSessionFromKeychain() {
        UserDefaults.standard.removeObject(forKey: keychainKey)
    }

    /// Merges Keychain refresh tokens and JWT `exp` into a restored session (fixes legacy 1h client expiry).
    private func normalizedPersistedSession(_ session: UserSession) -> UserSession {
        let trimmedRefresh = session.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mergedRefresh = trimmedRefresh.isEmpty
            ? OnCutsAuthTokenStore.loadRefreshToken()
            : session.refreshToken
        let jwtExpiry = UserSession.preferredAccessExpiration(
            accessToken: session.token,
            refreshToken: mergedRefresh
        )
        let expiresAt = max(session.expiresAt, jwtExpiry)
        return UserSession(
            userId: session.userId,
            token: session.token,
            email: session.email,
            displayName: session.displayName,
            role: session.role,
            stripeCustomerId: session.stripeCustomerId,
            profileImageURL: session.profileImageURL,
            expiresAt: expiresAt,
            refreshToken: mergedRefresh,
            signInProvider: session.signInProvider
        )
    }
}

// MARK: - Session Errors

public enum SessionError: LocalizedError {
    case noActiveSession
    case sessionExpired
    case refreshFailed
    
    public var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active session found"
        case .sessionExpired:
            return "Your session has expired. Please log in again."
        case .refreshFailed:
            return "Failed to refresh session"
        }
    }
}

// MARK: - Mock Authentication (Development Only)

extension AppSessionManager {
    /// Mock login for development and testing
    public func mockLogin(as role: UserRole = .student) {
        let mockSession = role == .barber ? UserSession.mockBarber : UserSession.mock
        login(session: mockSession)
    }
}
