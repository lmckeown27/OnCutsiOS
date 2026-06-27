//
//  AuthBackendVerification.swift
//  Intera
//
//  POSTs Google ID tokens to `AppConfiguration.urlAuthGoogle` (`POST /api/v1/auth/google`).
//  Expects the same JSON shape as email login: `{ "success": true, "data": { "accessToken", "refreshToken", "user" } }`.
//  Never uses the Google ID token as the AvilaPlatforms API Bearer (that caused 401 on messaging).
//

import Foundation

struct SessionAuthTokens: Sendable {
    let accessToken: String
    let refreshToken: String?
    /// AvilaPlatforms `users.id` when returned by auth (required for APIs keyed by DB user id).
    let backendUserId: String?
    /// Present on Google / Apple campus JWT login when `data.user` includes profile fields.
    let backendEmail: String?
    let backendFirstName: String?
    let backendLastName: String?
    /// From `data.user.profile_picture_url` when the server stores an avatar (Apple does not supply a photo URL).
    let backendProfilePictureURL: String?
    /// From `data.user.needsPlatformPassword` after Sign in with Apple when the account has no user-chosen password yet.
    let needsPlatformPassword: Bool?
}

enum AuthBackendVerificationError: LocalizedError {
    case invalidHTTPResponse
    case serverRejected(status: Int, message: String?)
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "Could not reach the sign-in server."
        case .serverRejected(let status, let message):
            if let message, !message.isEmpty { return message }
            if status == 404 {
                return "That sign-in method isn’t available on this API yet (HTTP 404). Use email/password, or deploy POST /api/v1/auth/google and POST /api/v1/auth/apple (same JSON as email login)."
            }
            return "Sign-in failed (HTTP \(status))."
        case .missingAccessToken:
            return "Server did not return an access token. The auth endpoint should return the same JSON as email login (data.accessToken)."
        }
    }
}

enum AuthBackendVerification {
    /// Backend route from `AppConfiguration` (`/auth/google` under `/api/v1`).
    static var googleTokenVerifyURL: URL { AppConfiguration.urlAuthGoogle }

    /// `POST …/api/v1/auth/apple` — Sign in with Apple (Guideline 4.8).
    static var appleTokenVerifyURL: URL { AppConfiguration.urlAuthApple }

    private struct APIErrorEnvelope: Decodable {
        let success: Bool?
        let message: String?
        let error: ErrorBlock?
        struct ErrorBlock: Decodable {
            let message: String?
        }
    }

    private struct LoginDataPayload: Decodable {
        let accessToken: String?
        let token: String?
        let refreshToken: String?
        let refresh_token: String?
        let user: UserPayload?
        struct UserPayload: Decodable {
            let id: String?
            let email: String?
            let firstName: String?
            let lastName: String?
            let profile_picture_url: String?
            let needsPlatformPassword: Bool?

            private enum CK: String, CodingKey {
                case id, email
                case firstName, lastName
                case first_name, last_name
                case profile_picture_url
                case needsPlatformPassword, needs_platform_password
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CK.self)
                id = try c.decodeIfPresent(String.self, forKey: .id)
                email = try c.decodeIfPresent(String.self, forKey: .email)
                firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
                    ?? c.decodeIfPresent(String.self, forKey: .first_name)
                lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
                    ?? c.decodeIfPresent(String.self, forKey: .last_name)
                profile_picture_url = try c.decodeIfPresent(String.self, forKey: .profile_picture_url)
                needsPlatformPassword = try c.decodeIfPresent(Bool.self, forKey: .needsPlatformPassword)
                    ?? c.decodeIfPresent(Bool.self, forKey: .needs_platform_password)
            }
        }
    }

    private struct LoginEnvelope: Decodable {
        let success: Bool?
        let data: LoginDataPayload?
    }

    private struct FlatTokens: Decodable {
        let token: String?
        let accessToken: String?
        let refreshToken: String?
        let refresh_token: String?
    }

    /// POST JSON `{ "idToken": "<Google JWT>" }` and return AvilaPlatforms access (and optional refresh) tokens.
    /// - Throws: On non-2xx, network failure, or missing access token. Does **not** fall back to the Google token.
    static func verifyGoogleIDTokenAndFetchSessionTokens(_ idToken: String) async throws -> SessionAuthTokens {
        var request = URLRequest(url: googleTokenVerifyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let payload = ["idToken": idToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await URLSession.shared.data(for: request)
            guard let h = response as? HTTPURLResponse else {
                throw AuthBackendVerificationError.invalidHTTPResponse
            }
            data = d
            http = h
        } catch let error as AuthBackendVerificationError {
            throw error
        } catch {
            ProductionLogging.recordNonFatal(error, context: ["area": "auth_google"])
            throw error
        }

        #if DEBUG
        print("📡 Google auth verify status: \(http.statusCode)")
        #endif

        guard (200 ... 299).contains(http.statusCode) else {
            let msg = Self.serverMessage(from: data)
            ProductionLogging.recordNonFatal(
                NSError(domain: "AuthBackend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg ?? "HTTP \(http.statusCode)"]),
                context: ["area": "auth_google"]
            )
            throw AuthBackendVerificationError.serverRejected(status: http.statusCode, message: msg)
        }

        if let envelope = try? JSONDecoder().decode(LoginEnvelope.self, from: data),
           let block = envelope.data {
            let access = block.accessToken ?? block.token
            let refresh = block.refreshToken ?? block.refresh_token
            let uid = block.user?.id
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.nilIfEmpty }
            let u = block.user
            let be = u?.email.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.nilIfEmpty }
            let bfn = u?.firstName.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.nilIfEmpty }
            let bln = u?.lastName.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.nilIfEmpty }
            let bpic = u?.profile_picture_url.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.nilIfEmpty }
            let needPw = u?.needsPlatformPassword
            if let access, !access.isEmpty {
                return SessionAuthTokens(
                    accessToken: access,
                    refreshToken: refresh,
                    backendUserId: uid,
                    backendEmail: be,
                    backendFirstName: bfn,
                    backendLastName: bln,
                    backendProfilePictureURL: bpic,
                    needsPlatformPassword: needPw
                )
            }
        }

        if let flat = try? JSONDecoder().decode(FlatTokens.self, from: data) {
            let access = flat.accessToken ?? flat.token
            let refresh = flat.refreshToken ?? flat.refresh_token
            if let access, !access.isEmpty {
                return SessionAuthTokens(
                    accessToken: access,
                    refreshToken: refresh,
                    backendUserId: nil,
                    backendEmail: nil,
                    backendFirstName: nil,
                    backendLastName: nil,
                    backendProfilePictureURL: nil,
                    needsPlatformPassword: nil
                )
            }
        }

        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           raw.split(separator: ".").count == 3 {
            return SessionAuthTokens(
                accessToken: raw,
                refreshToken: nil,
                backendUserId: nil,
                backendEmail: nil,
                backendFirstName: nil,
                backendLastName: nil,
                backendProfilePictureURL: nil,
                needsPlatformPassword: nil
            )
        }

        throw AuthBackendVerificationError.missingAccessToken
    }

    private static func serverMessage(from data: Data) -> String? {
        if let env = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            let top = env.message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            if let top { return top }
            return env.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// Legacy helper returning only the access token string.
    static func verifyGoogleIDTokenAndFetchSessionJWT(_ idToken: String) async throws -> String {
        let tokens = try await verifyGoogleIDTokenAndFetchSessionTokens(idToken)
        return tokens.accessToken
    }

    /// POST JSON `{ "identityToken", optional "firstName"/"lastName" }` — same success envelope as Google / email login.
    /// Apple only includes the person’s name on the **first** successful authorization; pass it here so the backend can persist it.
    /// Tries `…/api/v1/auth/apple` first, then `…/api/auth/apple` if the server returns 404 (older or split routing).
    static func verifyAppleIdentityTokenAndFetchSessionTokens(
        _ identityToken: String,
        firstName: String? = nil,
        lastName: String? = nil,
        supplementalEmail: String? = nil
    ) async throws -> SessionAuthTokens {
        var candidates: [URL] = [appleTokenVerifyURL]
        let legacy = AppConfiguration.urlAuthAppleLegacy
        if legacy != appleTokenVerifyURL {
            candidates.append(legacy)
        }

        var body: [String: Any] = ["identityToken": identityToken]
        if let firstName, !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["firstName"] = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let lastName, !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["lastName"] = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let supplementalEmail, !supplementalEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["email"] = supplementalEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        var lastData = Data()
        var lastHTTP: HTTPURLResponse?
        for url in candidates {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let data: Data
            let http: HTTPURLResponse
            do {
                let (d, response) = try await URLSession.shared.data(for: request)
                guard let h = response as? HTTPURLResponse else {
                    throw AuthBackendVerificationError.invalidHTTPResponse
                }
                data = d
                http = h
            } catch let error as AuthBackendVerificationError {
                throw error
            } catch {
                ProductionLogging.recordNonFatal(error, context: ["area": "auth_apple"])
                throw error
            }

            lastData = data
            lastHTTP = http

            if http.statusCode == 404, url != candidates.last {
                #if DEBUG
                print("📡 Apple auth verify 404 at \(url.absoluteString); retrying legacy path if available.")
                #endif
                continue
            }

            guard (200 ... 299).contains(http.statusCode) else {
                let msg = Self.serverMessage(from: data)
                ProductionLogging.recordNonFatal(
                    NSError(domain: "AuthBackend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg ?? "HTTP \(http.statusCode)"]),
                    context: ["area": "auth_apple"]
                )
                throw AuthBackendVerificationError.serverRejected(status: http.statusCode, message: msg)
            }

            if let envelope = try? JSONDecoder().decode(LoginEnvelope.self, from: data),
               let block = envelope.data {
                let access = block.accessToken ?? block.token
                let refresh = block.refreshToken ?? block.refresh_token
                let uid = block.user?.id
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .flatMap { $0.nilIfEmpty }
                let u = block.user
                let be = u?.email.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.nilIfEmpty }
                let bfn = u?.firstName.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.nilIfEmpty }
                let bln = u?.lastName.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.nilIfEmpty }
                let bpic = u?.profile_picture_url.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.nilIfEmpty }
                let needPw = u?.needsPlatformPassword
                if let access, !access.isEmpty {
                    return SessionAuthTokens(
                        accessToken: access,
                        refreshToken: refresh,
                        backendUserId: uid,
                        backendEmail: be,
                        backendFirstName: bfn,
                        backendLastName: bln,
                        backendProfilePictureURL: bpic,
                        needsPlatformPassword: needPw
                    )
                }
            }

            throw AuthBackendVerificationError.missingAccessToken
        }

        let status = lastHTTP?.statusCode ?? 404
        let msg = Self.serverMessage(from: lastData)
        throw AuthBackendVerificationError.serverRejected(status: status, message: msg)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
