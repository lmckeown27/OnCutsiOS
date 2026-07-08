//
//  GoogleSignInAppSupport.swift
//  OnCuts
//
//  Configures the Google Sign-In SDK, restores sessions, runs interactive sign-in,
//  and maps `GIDGoogleUser` into `UserSession` (email + profile image for the app profile).
//

import Foundation
import GoogleSignIn
import OnCutsModule
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

@MainActor
enum GoogleSignInAppSupport {
    private static var isConfigured = false

    /// Call once at launch. Reads `CLIENT_ID` from `GoogleService-Info.plist` in the bundle.
    @discardableResult
    static func configure() -> Bool {
        if isConfigured { return true }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientID = plist["CLIENT_ID"] as? String,
              !clientID.contains("YOUR_IOS_CLIENT_ID") else {
            #if DEBUG
            print("⚠️ Google Sign-In: add GoogleService-Info.plist with a real CLIENT_ID.")
            #endif
            return false
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        isConfigured = true
        return true
    }

    static func handleURL(_ url: URL) -> Bool {
        _ = configure()
        return GIDSignIn.sharedInstance.handle(url)
    }

    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    /// One Tap–style restore: if the user previously signed in with Google, rehydrate the SDK user.
    static func restorePreviousSignIn(sessionManager: AppSessionManager) async {
        guard configure(), GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                Task { @MainActor in
                    guard error == nil, let user else {
                        continuation.resume()
                        return
                    }
                    do {
                        try await completeLogin(with: user, sessionManager: sessionManager)
                    } catch {
                        #if DEBUG
                        print("Google restore login failed: \(error.localizedDescription)")
                        #endif
                    }
                    continuation.resume()
                }
            }
        }
    }

    /// Presents the system Google sign-in UI (native sheet).
    static func signInInteractively(sessionManager: AppSessionManager) async throws {
        guard configure() else {
            #if DEBUG
            print("❌ Google Sign-In failed: configuration returned false")
            #endif
            throw GoogleSignInFlowError.missingConfiguration
        }
        #if DEBUG
        print("✅ Google Sign-In configured, presenting UI...")
        #endif
        #if os(iOS) || targetEnvironment(macCatalyst)
        let presenter = try presenterViewController()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                Task { @MainActor in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let result else {
                        continuation.resume(throwing: GoogleSignInFlowError.noResult)
                        return
                    }
                    do {
                        try await completeLogin(with: result.user, sessionManager: sessionManager)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        #elseif os(macOS)
        let presenter = try presenterNSViewController()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                Task { @MainActor in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let result else {
                        continuation.resume(throwing: GoogleSignInFlowError.noResult)
                        return
                    }
                    do {
                        try await completeLogin(with: result.user, sessionManager: sessionManager)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        #else
        throw GoogleSignInFlowError.unsupportedPlatform
        #endif
    }

    private static func completeLogin(with user: GIDGoogleUser, sessionManager: AppSessionManager) async throws {
        guard let idToken = user.idToken?.tokenString else {
            #if DEBUG
            print("❌ Google Sign-In failed: no ID token in response")
            #endif
            throw GoogleSignInFlowError.missingIDToken
        }
        #if DEBUG
        print("✅ Got Google ID token, verifying with backend...")
        #endif
        let tokens: SessionAuthTokens
        do {
            tokens = try await AuthBackendVerification.verifyGoogleIDTokenAndFetchSessionTokens(idToken)
        } catch {
            GIDSignIn.sharedInstance.signOut()
            throw error
        }
        #if DEBUG
        print("✅ Backend verification complete, creating session...")
        #endif
        OnCutsAuthTokenStore.save(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
        let session = UserSession(
            googleUser: user,
            backendToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            backendUserId: tokens.backendUserId
        )
        sessionManager.login(session: session)
        #if DEBUG
        print("✅ Google Sign-In complete! User: \(session.email)")
        #endif
    }

    #if os(iOS) || targetEnvironment(macCatalyst)
    private static func presenterViewController() throws -> UIViewController {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow ?? scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              var top = window.rootViewController else {
            throw GoogleSignInFlowError.noPresenter
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
            top = visible
        } else if let tab = top as? UITabBarController, let selected = tab.selectedViewController {
            top = selected
            while let presented = top.presentedViewController {
                top = presented
            }
        }
        return top
    }
    #endif

    #if os(macOS) && !targetEnvironment(macCatalyst)
    private static func presenterNSViewController() throws -> NSViewController {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first,
              let vc = window.contentViewController else {
            throw GoogleSignInFlowError.noPresenter
        }
        return vc
    }
    #endif
}

enum GoogleSignInFlowError: LocalizedError {
    case noPresenter
    case missingIDToken
    case noResult
    case unsupportedPlatform
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .noPresenter:
            return "Could not find a view controller to present Google sign-in."
        case .missingIDToken:
            return "Google did not return an ID token."
        case .noResult:
            return "Google sign-in finished without a result."
        case .unsupportedPlatform:
            return "Google sign-in is not configured for this platform."
        case .missingConfiguration:
            return "Google Sign-In is not configured. Add GoogleService-Info.plist with a valid CLIENT_ID."
        }
    }
}

extension UserSession {
    /// Builds the in-app session used for browsing, booking, and profile (email + avatar URL).
    /// Prefer `backendUserId` (OnCuts `users.id` from auth response) for API calls; fall back to Google `sub` only if missing.
    init(googleUser: GIDGoogleUser, backendToken: String, refreshToken: String? = nil, backendUserId: String? = nil) {
        let profile = googleUser.profile
        let email = profile?.email ?? ""
        let displayName = profile?.name ?? String(email.split(separator: "@").first ?? Substring("User"))
        let imageURLString = profile?.imageURL(withDimension: 256)?.absoluteString
        let trimmedBackend = backendUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let userId: String
        if !trimmedBackend.isEmpty {
            userId = trimmedBackend
        } else if let gid = googleUser.userID, !gid.isEmpty {
            userId = gid
        } else {
            userId = email
        }
        self.init(
            userId: userId,
            token: backendToken,
            email: email,
            displayName: displayName,
            role: .student,
            stripeCustomerId: nil,
            profileImageURL: imageURLString,
            expiresAt: UserSession.preferredAccessExpiration(accessToken: backendToken, refreshToken: refreshToken),
            refreshToken: refreshToken,
            signInProvider: .google
        )
    }
}
