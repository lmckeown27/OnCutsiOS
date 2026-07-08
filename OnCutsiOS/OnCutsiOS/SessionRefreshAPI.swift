//
//  SessionRefreshAPI.swift
//  Intera
//
//  POST /api/v1/auth/refresh-token — exchanges a refresh JWT for a new access token.
//

import Foundation

enum SessionRefreshAPIError: LocalizedError {
    case invalidHTTPResponse
    case missingRefreshToken
    case missingAccessToken
    case serverRejected(status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "Could not reach the sign-in server."
        case .missingRefreshToken:
            return "No refresh token available."
        case .missingAccessToken:
            return "Server did not return a new access token."
        case .serverRejected(let status):
            return "Could not refresh session (HTTP \(status))."
        }
    }
}

enum SessionRefreshAPI {
    private struct RefreshEnvelope: Decodable {
        let success: Bool?
        let data: RefreshData?
        let token: String?
        let accessToken: String?

        struct RefreshData: Decodable {
            let token: String?
            let accessToken: String?
        }

        var resolvedAccessToken: String? {
            let candidates = [
                data?.accessToken,
                data?.token,
                accessToken,
                token,
            ]
            return candidates
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        }
    }

    static func refreshAccessToken(refreshToken: String) async throws -> String {
        let trimmed = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SessionRefreshAPIError.missingRefreshToken
        }

        var request = URLRequest(url: AppConfiguration.url(forPath: "/auth/refresh-token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["refreshToken": trimmed])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SessionRefreshAPIError.invalidHTTPResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw SessionRefreshAPIError.serverRejected(status: http.statusCode)
        }

        if let envelope = try? JSONDecoder().decode(RefreshEnvelope.self, from: data),
           let token = envelope.resolvedAccessToken {
            return token
        }

        throw SessionRefreshAPIError.missingAccessToken
    }
}
