//
//  AccountRegistrationAPI.swift
//  OnCuts
//
//  POST /api/v1/auth/register (see AppConfiguration.urlAuthRegister) with onboarding metadata.
//

import Foundation

struct AccountRegistrationPayload: Encodable, Sendable {
    let email: String
    let password: String
    let firstName: String
    let lastName: String
    let acceptedTerms: Bool

    enum CodingKeys: String, CodingKey {
        case email, password
        case firstName = "first_name"
        case lastName = "last_name"
        case acceptedTerms = "accepted_terms"
    }
}

enum AccountRegistrationError: LocalizedError {
    case invalidHTTPResponse
    case serverRejected(status: Int, message: String?)
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "Could not reach the registration server."
        case .serverRejected(let status, let message):
            if let message, !message.isEmpty { return message }
            return "Registration failed (HTTP \(status))."
        case .missingAccessToken:
            return "The server did not return an access token."
        }
    }
}

enum AccountRegistrationAPI {
    /// POST JSON body; expects the same success envelope as email/Google login when possible (`data.accessToken`, `data.user`, …).
    static func register(payload: AccountRegistrationPayload) async throws -> UserSession {
        var request = URLRequest(url: AppConfiguration.urlAuthRegister)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await URLSession.shared.data(for: request)
            guard let h = response as? HTTPURLResponse else {
                throw AccountRegistrationError.invalidHTTPResponse
            }
            data = d
            http = h
        } catch let error as AccountRegistrationError {
            throw error
        } catch {
            ProductionLogging.recordNonFatal(error, context: ["area": "auth_register"])
            throw error
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let msg = serverMessage(from: data)
            ProductionLogging.recordNonFatal(
                NSError(domain: "AccountRegistration", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg ?? "HTTP \(http.statusCode)"]),
                context: ["area": "auth_register"]
            )
            throw AccountRegistrationError.serverRejected(status: http.statusCode, message: msg)
        }

        return try decodeSession(from: data, fallbackEmail: payload.email, fallbackDisplayName: "\(payload.firstName) \(payload.lastName)".trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private struct APIErrorEnvelope: Decodable {
        let success: Bool?
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
            let first_name: String?
            let last_name: String?
            let role: String?
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

    private static func decodeSession(from data: Data, fallbackEmail: String, fallbackDisplayName: String) throws -> UserSession {
        if let envelope = try? JSONDecoder().decode(LoginEnvelope.self, from: data),
           let block = envelope.data {
            let access = block.accessToken ?? block.token
            let refresh = block.refreshToken ?? block.refresh_token
            let uid = block.user?.id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let email = block.user?.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackEmail
            let fn = block.user?.first_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let ln = block.user?.last_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let joinedName = [fn, ln].filter { !$0.isEmpty }.joined(separator: " ")
            let display = joinedName.isEmpty ? fallbackDisplayName : joinedName
            let role = UserRole(rawValue: block.user?.role?.lowercased() ?? "") ?? .student

            if let access, !access.isEmpty {
                let userId = uid ?? email
                return UserSession(
                    userId: userId,
                    token: access,
                    email: email,
                    displayName: display.isEmpty ? email : display,
                    role: role,
                    stripeCustomerId: nil,
                    profileImageURL: nil,
                    expiresAt: UserSession.preferredAccessExpiration(accessToken: access, refreshToken: refresh),
                    refreshToken: refresh,
                    signInProvider: .emailPassword
                )
            }
        }

        if let flat = try? JSONDecoder().decode(FlatTokens.self, from: data) {
            let access = flat.accessToken ?? flat.token
            let refresh = flat.refreshToken ?? flat.refresh_token
            if let access, !access.isEmpty {
                return UserSession(
                    userId: fallbackEmail,
                    token: access,
                    email: fallbackEmail,
                    displayName: fallbackDisplayName.isEmpty ? fallbackEmail : fallbackDisplayName,
                    role: .student,
                    stripeCustomerId: nil,
                    profileImageURL: nil,
                    expiresAt: UserSession.preferredAccessExpiration(accessToken: access, refreshToken: refresh),
                    refreshToken: refresh,
                    signInProvider: .emailPassword
                )
            }
        }

        throw AccountRegistrationError.missingAccessToken
    }

    private static func serverMessage(from data: Data) -> String? {
        if let env = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return env.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
