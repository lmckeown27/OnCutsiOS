//
//  SignupOnboardingPersistence.swift
//  OnCuts
//
//  Resume liquid signup after background: verification email + optional verified session (Keychain).
//

import OnCutsModule
import Foundation
import Security

enum SignupOnboardingPersistence {
    private static let stepKey = "OnCutsSignup.step"
    private static let emailKey = "OnCutsSignup.email"
    private static let kService = "com.oncuts.signup.pendingSession"
    private static let kAccount = "verified.json"

    static func save(step: CustomerOnboardingStep, email: String?) {
        UserDefaults.standard.set(step.rawValue, forKey: stepKey)
        if let email, !email.isEmpty {
            UserDefaults.standard.set(email, forKey: emailKey)
        } else {
            UserDefaults.standard.removeObject(forKey: emailKey)
        }
    }

    static func loadStep() -> CustomerOnboardingStep? {
        guard let raw = UserDefaults.standard.string(forKey: stepKey) else { return nil }
        return CustomerOnboardingStep.fromPersistedString(raw)
    }

    static func loadEmail() -> String? {
        UserDefaults.standard.string(forKey: emailKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// Whether a signup flow was left mid-way (verification or legacy profile/terms Keychain resume).
    static var hasPersistedProgress: Bool {
        guard let s = loadStep() else { return false }
        switch s {
        case .verification, .legacyProfile, .terms:
            return true
        case .name, .contact, .password:
            return false
        }
    }

    static func saveVerifiedSession(_ session: OnCutsVerifiedSession) throws {
        // Advance saved step before Keychain so a Keychain failure cannot leave us stuck on `.verification`
        // (which would make `restoreIfNeeded` snap the user back after a successful verify).
        save(step: .terms, email: session.email)
        let snap = VerifiedSessionSnapshot(session: session)
        let data = try JSONEncoder().encode(snap)
        try saveKeychainData(data)
    }

    static func loadVerifiedSession() throws -> OnCutsVerifiedSession? {
        guard let data = loadKeychainData() else { return nil }
        let snap = try JSONDecoder().decode(VerifiedSessionSnapshot.self, from: data)
        return snap.asVerifiedSession()
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: stepKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
        deleteKeychain()
    }

    /// Clears saved step and email only (e.g. after loading a verified session from Keychain for resume).
    static func clearSignupNavigationState() {
        UserDefaults.standard.removeObject(forKey: stepKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
    }

    /// Removes the pending verified session blob after it has been applied to `AppSessionManager`.
    static func deleteVerifiedSessionFromKeychain() {
        deleteKeychain()
    }

    // MARK: Keychain

    private static func saveKeychainData(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kService,
            kSecAttrAccount as String: kAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "SignupPersistence", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain save failed"])
        }
    }

    private static func loadKeychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kService,
            kSecAttrAccount as String: kAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kService,
            kSecAttrAccount as String: kAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Models

enum CustomerOnboardingStep: String, Codable, CaseIterable, Sendable, Equatable {
    case name
    case contact
    case password
    case verification
    case terms
    /// Legacy persisted value (`"profile"`) for Keychain resume paths.
    case legacyProfile = "profile"
}

extension CustomerOnboardingStep {
    /// Maps older `"identity"` / `"complete"` saves to the new step model.
    fileprivate static func fromPersistedString(_ raw: String) -> CustomerOnboardingStep? {
        if raw == "identity" { return .name }
        if raw == "complete" { return .terms }
        return CustomerOnboardingStep(rawValue: raw)
    }
}

private struct VerifiedSessionSnapshot: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var userId: String
    var email: String
    var firstName: String
    var lastName: String
    var backendRole: String

    init(session: OnCutsVerifiedSession) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        userId = session.userId
        email = session.email
        firstName = session.firstName
        lastName = session.lastName
        backendRole = session.backendRole
    }

    func asVerifiedSession() -> OnCutsVerifiedSession {
        OnCutsVerifiedSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId,
            email: email,
            firstName: firstName,
            lastName: lastName,
            backendRole: backendRole
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
