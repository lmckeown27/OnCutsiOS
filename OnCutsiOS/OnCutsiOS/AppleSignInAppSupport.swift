//
//  AppleSignInAppSupport.swift
//  OnCuts
//
//  Sign in with Apple → `POST /api/v1/auth/apple` → OnCuts JWT session (Guideline 4.8).
//

import AuthenticationServices
import OnCutsModule
import Foundation

/// Reads `email` from Apple’s identity JWT payload (still present when `ASAuthorizationAppleIDCredential.email` is nil on later authorizations).
private enum AppleIdentityTokenJWT {
    static func emailClaim(from jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let segment = String(parts[1])
        guard let data = decodeBase64URL(segment) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = obj["email"] as? String else { return nil }
        let t = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func decodeBase64URL(_ segment: String) -> Data? {
        var s = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        if pad > 0 { s.append(String(repeating: "=", count: pad)) }
        return Data(base64Encoded: s)
    }
}

enum AppleSignInFlowError: LocalizedError {
    case missingIdentityToken
    case missingEmail

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            return "Apple did not return an identity token."
        case .missingEmail:
            return "We could not determine your account email from Apple or the server. Try Sign in with Apple again, or contact support if this keeps happening."
        }
    }
}

@MainActor
enum AppleSignInAppSupport {
    /// Completes Apple sign-in using only `ASAuthorizationAppleIDCredential` + Keychain replay + JWT claims — no in-app name/email fields (App Store Guideline 4).
    static func completeLogin(
        identityToken: String,
        credential: ASAuthorizationAppleIDCredential,
        sessionManager: AppSessionManager,
        presetPlatformPassword: String? = nil
    ) async throws {
        AppleSignInSupplementStore.mergeFromCredentialIfPresent(credential)

        let resolved = AppleSignInSupplementStore.resolvedGivenFamily(from: credential)
        let credFirst = resolved.given
        let credLast = resolved.family

        let appleFirst = credFirst ?? AppleSignInSupplementStore.savedGivenName()
        let appleLast = credLast ?? AppleSignInSupplementStore.savedFamilyName()

        let credEmail = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let jwtEmail = AppleIdentityTokenJWT.emailClaim(from: identityToken)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        /// Relay / real address from Apple or prior device Keychain — never from manual app text fields.
        let supplementalEmail =
            credEmail
            ?? jwtEmail
            ?? AppleSignInSupplementStore.savedEmail()

        let tokens = try await AuthBackendVerification.verifyAppleIdentityTokenAndFetchSessionTokens(
            identityToken,
            firstName: appleFirst,
            lastName: appleLast,
            supplementalEmail: supplementalEmail
        )
        var trimmedEmail = resolvedEmail(tokens: tokens, credential: credential)
        if trimmedEmail.isEmpty, let j = jwtEmail {
            trimmedEmail = j
        }
        if trimmedEmail.isEmpty, let me = try? await UserProfileAPI.authMeEmailIfPresent(bearerToken: tokens.accessToken) {
            trimmedEmail = me
        }
        guard !trimmedEmail.isEmpty else {
            throw AppleSignInFlowError.missingEmail
        }

        OnCutsAuthTokenStore.save(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)

        let trimmedBackendId = tokens.backendUserId
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.nilIfEmpty }
        let userId = trimmedBackendId ?? trimmedEmail

        let displayName = displayName(
            from: tokens,
            credential: credential,
            email: trimmedEmail
        )

        sessionManager.login(
            session: UserSession(
                userId: userId,
                token: tokens.accessToken,
                email: trimmedEmail,
                displayName: displayName,
                role: .student,
                stripeCustomerId: nil,
                profileImageURL: tokens.backendProfilePictureURL,
                expiresAt: UserSession.preferredAccessExpiration(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken),
                refreshToken: tokens.refreshToken,
                signInProvider: .apple
            )
        )

        if tokens.needsPlatformPassword == true,
           let preset = presetPlatformPassword?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           preset.count >= 8
        {
            do {
                try await UserProfileAPI.setInitialPassword(bearerToken: tokens.accessToken, newPassword: preset)
                _ = try await UserProfileAPI.authMeIndicatesNeedsPlatformPassword(bearerToken: tokens.accessToken)
            } catch {
                // Session remains valid; user can set a password later in account settings if required.
            }
        }
    }

    private static func resolvedEmail(
        tokens: SessionAuthTokens,
        credential: ASAuthorizationAppleIDCredential
    ) -> String {
        let fromBackend = tokens.backendEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromBackend.isEmpty { return fromBackend }
        let fromCredential = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromCredential.isEmpty { return fromCredential }
        return ""
    }

    private static func displayName(
        from tokens: SessionAuthTokens,
        credential: ASAuthorizationAppleIDCredential,
        email: String
    ) -> String {
        let fn = tokens.backendFirstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ln = tokens.backendLastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !combined.isEmpty { return combined }
        let resolved = AppleSignInSupplementStore.resolvedGivenFamily(from: credential)
        let rCombined = [resolved.given, resolved.family].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rCombined.isEmpty { return rCombined }
        if let full = credential.fullName {
            let formatted = PersonNameComponentsFormatter().string(from: full).trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty { return formatted }
        }
        return String(email.split(separator: "@").first ?? Substring("User"))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
