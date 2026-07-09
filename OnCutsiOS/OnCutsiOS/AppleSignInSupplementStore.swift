//
//  AppleSignInSupplementStore.swift
//  OnCuts
//
//  Persists Apple `email` and `fullName` from the **first** successful Sign in with Apple only.
//  On later sign-ins Apple often returns `nil`; replay from Keychain in `POST /api/v1/auth/apple` (OnCuts contract).
//

import AuthenticationServices
import Foundation
import Security

private struct AppleSignInSupplement: Codable, Sendable {
    var email: String?
    var givenName: String?
    var familyName: String?
}

enum AppleSignInSupplementStore {
    private static let service = "com.oncuts.apple-sign-in.supplement"
    private static let account = "credential.json"

    /// Only Apple’s explicit `givenName` / `familyName` are sent to the API and stored in Keychain.
    /// Do **not** use `PersonNameComponentsFormatter` or `nickname` here: for relay-only credentials the formatter
    /// can emit misleading tokens (e.g. "Member …") that are not the user’s real name.
    static func resolvedGivenFamily(from credential: ASAuthorizationAppleIDCredential) -> (given: String?, family: String?) {
        guard let components = credential.fullName else { return (nil, nil) }
        let g0 = components.givenName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let f0 = components.familyName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return (g0, f0)
    }

    /// Call with every successful Apple authorization. Updates Keychain when Apple returns non-nil fields.
    static func mergeFromCredentialIfPresent(_ credential: ASAuthorizationAppleIDCredential) {
        var current = load() ?? AppleSignInSupplement()
        if let e = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            current.email = e
        }
        let resolved = resolvedGivenFamily(from: credential)
        if let given = resolved.given {
            current.givenName = given
        }
        if let family = resolved.family {
            current.familyName = family
        }
        if current.email != nil || current.givenName != nil || current.familyName != nil {
            save(current)
        }
    }

    private static func load() -> AppleSignInSupplement? {
        guard let data = readKeychainData() else { return nil }
        return try? JSONDecoder().decode(AppleSignInSupplement.self, from: data)
    }

    static func savedEmail() -> String? {
        load()?.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func savedGivenName() -> String? {
        load()?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func savedFamilyName() -> String? {
        load()?.familyName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// After the user enters a legal name in-app, persist it so later Sign in with Apple requests can replay it to the API.
    static func replaceSavedName(given: String, family: String) {
        var current = load() ?? AppleSignInSupplement()
        let g = given.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = family.trimmingCharacters(in: .whitespacesAndNewlines)
        if !g.isEmpty { current.givenName = g }
        if !f.isEmpty { current.familyName = f }
        save(current)
    }

    // MARK: - Keychain

    private static func save(_ value: AppleSignInSupplement) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readKeychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
