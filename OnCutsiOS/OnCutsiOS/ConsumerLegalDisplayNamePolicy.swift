//
//  ConsumerLegalDisplayNamePolicy.swift
//  OnCuts
//
//  Heuristic for when a consumer display name looks like a placeholder (relay / legacy tokens).
//  Sign-in with Apple must not be followed by mandatory manual name collection (App Store Guideline 4).
//

import Foundation

enum ConsumerLegalDisplayNamePolicy {
    /// Tokens Apple / iOS / older backends sometimes persist instead of a real person name (Sign in with Apple).
    /// Checked on **either** first or last so swapped or single-field garbage still triggers re-collection.
    private static let legacyPlaceholderNameTokens: Set<String> = [
        "apple", "user", "member", "guest", "consumer", "customer", "unknown", "nickname", "friend",
        "private", "public", "ms8j", "notprovided", "noname", "firstname", "lastname", "fullname",
        "relay", "icloud", "useruser"
    ]

    static func isApplePrivateRelayEmail(_ email: String) -> Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix("@privaterelay.appleid.com")
    }

    /// Short alphanumeric + digit fragments (e.g. `Ms8j`) that are not credible legal names — **relay only** to limit false positives.
    private static func relayLikelyAutofillFragment(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 3, s.count <= 10 else { return false }
        guard s.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        guard s.contains(where: { $0.isNumber }), s.contains(where: { $0.isLetter }) else { return false }
        return true
    }

    /// `true` when the user should be prompted to enter a proper first + last name before continuing.
    static func requiresLegalNameCollection(
        backendFirstName: String?,
        backendLastName: String?,
        accountEmail: String
    ) -> Bool {
        let f = backendFirstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let l = backendLastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let local = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let localLower = local.lowercased()
        let relay = isApplePrivateRelayEmail(email)

        if f.isEmpty || l.isEmpty { return true }

        let fl = f.lowercased()
        let ll = l.lowercased()

        if legacyPlaceholderNameTokens.contains(fl) || legacyPlaceholderNameTokens.contains(ll) { return true }
        if fl == "apple" && ll == "user" { return true }

        // Hide My Email local parts are often long opaque strings used as DB placeholders for first name.
        if relay, !localLower.isEmpty, fl == localLower, local.count >= 8 {
            return true
        }

        // Formatter-style fragments on relay (e.g. last name `Ms8j`) when both fields look like scaffold tokens.
        if relay, relayLikelyAutofillFragment(f), relayLikelyAutofillFragment(l) {
            return true
        }

        return false
    }
}

// MARK: - One-time in-app confirmation (Sign in with Apple)

extension ConsumerLegalDisplayNamePolicy {
    /// Reserved for optional in-app polish; must not gate Sign in with Apple (Guideline 4).
    enum LegalDisplayNameOnboardingMarker {
        private static let defaults = UserDefaults.standard
        private static let key = "intera.consumerLegalDisplayNameConfirmedUserIds"

        private static var idSet: Set<String> {
            get { Set(defaults.stringArray(forKey: key) ?? []) }
            set { defaults.set(Array(newValue).sorted(), forKey: key) }
        }

        static func hasConfirmedLegalName(userId: String) -> Bool {
            let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return false }
            return idSet.contains(id)
        }

        static func markLegalNameConfirmed(userId: String) {
            let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return }
            var s = idSet
            s.insert(id)
            idSet = s
        }
    }
}
