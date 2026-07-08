//
//  UserProfileAPI.swift
//  OnCuts
//
//  OnCuts user profile REST client: GET/PUT `/api/v1/users/:id`,
//  multipart profile photo upload, and account deletion. The deployed Express API uses **PUT**
//  for profile updates (not POST `/users/profile`).
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - API

enum UserProfileAPI {
    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    static func isUnauthorizedHTTPError(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == "UserProfileAPI" && ns.code == 401
    }

    // MARK: Profile

    static func fetchProfile(userId: String, bearerToken: String?) async throws -> UserProfileAPIModel {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/users/" + encoded) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
        let env = try jsonDecoder.decode(ProfileTopEnvelope.self, from: data)
        guard let d = env.data else {
            throw NSError(domain: "UserProfileAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing profile data."])
        }
        return d
    }

    /// Persists profile fields supported by `updateUserProfile` in the Express backend.
    static func updateProfile(
        userId: String,
        bearerToken: String?,
        firstName: String,
        lastName: String,
        displayName: String,
        bio: String
    ) async throws {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/users/" + encoded) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let body = ProfileUpdateBody(
            first_name: firstName,
            last_name: lastName,
            displayName: displayName,
            bio: bio
        )
        req.httpBody = try jsonEncoder.encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
    }

    // MARK: Security

    /// For OAuth-only accounts (`needsPlatformPassword` from auth/me), send `password: nil` after local device confirmation.
    static func deleteAccount(userId: String, bearerToken: String?, password: String?) async throws {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/users/" + encoded) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        } else {
            throw NSError(domain: "UserProfileAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in."])
        }
        var body: [String: String] = [:]
        if let password, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["password"] = password.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
    }

    /// `PUT /api/v1/users/me/set-initial-password` — first-time password for OAuth-only accounts (Bearer required).
    static func setInitialPassword(bearerToken: String?, newPassword: String) async throws {
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/users/me/set-initial-password") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        } else {
            throw NSError(domain: "UserProfileAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in."])
        }
        req.httpBody = try jsonSerializationEncode(["newPassword": newPassword])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
    }

    /// `GET /api/v1/auth/me` — reads **`needsPlatformPassword`** or **`needs_platform_password`** (OnCuts returns both).
    static func authMeIndicatesNeedsPlatformPassword(bearerToken: String) async throws -> Bool {
        let url = AppConfiguration.urlAuthMe
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
        guard let env = try? jsonDecoder.decode(AuthMeEnvelope.self, from: data), let u = env.data else {
            return false
        }
        if let c = u.needsPlatformPassword { return c }
        if let s = u.needs_platform_password { return s }
        return false
    }

    /// Same `GET /auth/me` envelope — returns `data.email` when the Apple login JSON omitted it (new device / no Keychain replay).
    static func authMeEmailIfPresent(bearerToken: String) async throws -> String? {
        let url = AppConfiguration.urlAuthMe
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
        guard let env = try? jsonDecoder.decode(AuthMeEnvelope.self, from: data), let u = env.data else {
            return nil
        }
        let raw = u.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    /// `PUT /api/v1/users/me` — confirm name / profile (Bearer). Body uses camelCase `firstName` / `lastName` per API contract.
    static func updateMyProfileNames(firstName: String, lastName: String, bearerToken: String?) async throws {
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/users/me") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        } else {
            throw NSError(domain: "UserProfileAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in."])
        }
        req.httpBody = try jsonEncoder.encode(MyProfileNameBody(firstName: firstName, lastName: lastName))
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
    }

    // MARK: Profile photo (multipart)

    /// `POST /api/v1/upload/profile-photo` — field name `image`. Returns the public image URL.
    /// Large library photos are downscaled and recompressed before upload to avoid HTTP **413 Payload Too Large**.
    static func uploadProfilePhoto(imageData: Data, fileName: String, mimeType: String, bearerToken: String?) async throws -> String {
        guard let url = URL(string: AppConfiguration.messagingAPIRootTrimmed + "/upload/profile-photo") else {
            throw URLError(.badURL)
        }
        #if canImport(UIKit)
        let payload = prepareProfilePhotoPayload(imageData)
        #else
        let payload = imageData
        #endif
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(payload)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfHTTPError(resp, data: data)
        let env = try jsonDecoder.decode(UploadPhotoEnvelope.self, from: data)
        guard let u = env.data?.url, !u.isEmpty else {
            throw NSError(domain: "UserProfileAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload did not return an image URL."])
        }
        return u
    }

    #if canImport(UIKit)
    /// Downscales and JPEG-recompresses so typical Express/nginx body limits are not exceeded.
    private static func prepareProfilePhotoPayload(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        var working = resizeProfileImage(image, maxPixelDimension: 1024)
        let targetMaxBytes = 750_000
        var quality: CGFloat = 0.78
        var out = working.jpegData(compressionQuality: quality) ?? data
        while out.count > targetMaxBytes && quality > 0.42 {
            quality -= 0.06
            guard let next = working.jpegData(compressionQuality: quality) else { break }
            out = next
        }
        if out.count > targetMaxBytes {
            working = resizeProfileImage(working, maxPixelDimension: 640)
            quality = 0.72
            out = working.jpegData(compressionQuality: quality) ?? out
            while out.count > targetMaxBytes && quality > 0.42 {
                quality -= 0.06
                guard let next = working.jpegData(compressionQuality: quality) else { break }
                out = next
            }
        }
        return out.isEmpty ? data : out
    }

    private static func resizeProfileImage(_ image: UIImage, maxPixelDimension: CGFloat) -> UIImage {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        let maxSide = max(w, h)
        guard maxSide > maxPixelDimension else { return image }
        let ratio = maxPixelDimension / maxSide
        let newSize = CGSize(width: floor(image.size.width * ratio), height: floor(image.size.height * ratio))
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    #endif

    // MARK: HTTP helpers

    private static func throwIfHTTPError(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let parsed = serverErrorMessage(from: data)
            let msg: String
            if let parsed, !parsed.isEmpty {
                msg = parsed
            } else if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                msg = raw
            } else {
                msg = "Request failed (HTTP \(http.statusCode))."
            }
            throw NSError(
                domain: "UserProfileAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }

    /// Top-level `message` (e.g. `DELETE /users/:id` wrong password) or nested `error.message` from the global error handler.
    private static func serverErrorMessage(from data: Data) -> String? {
        struct Envelope: Decodable {
            let message: String?
            let error: ErrorBlock?
            struct ErrorBlock: Decodable {
                let message: String?
            }
        }
        guard let env = try? jsonDecoder.decode(Envelope.self, from: data) else { return nil }
        let top = env.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let top, !top.isEmpty { return top }
        let nested = env.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nested, !nested.isEmpty { return nested }
        return nil
    }

    private struct AuthMeEnvelope: Decodable, Sendable {
        let success: Bool?
        let data: AuthMeUser?
        struct AuthMeUser: Decodable, Sendable {
            let email: String?
            let needs_platform_password: Bool?
            let needsPlatformPassword: Bool?
        }
    }

    private struct MyProfileNameBody: Encodable, Sendable {
        let firstName: String
        let lastName: String
    }

    private static func jsonSerializationEncode(_ object: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
}

// MARK: - Models

struct UserProfileAPIModel: Codable, Sendable {
    let id: JSONValue
    let email: String
    let first_name: String?
    let last_name: String?
    let profile_picture_url: String?
    let bio: String?
    let is_verified: Bool?
}

private struct ProfileUpdateBody: Encodable, Sendable {
    let first_name: String
    let last_name: String
    let displayName: String
    let bio: String
}

private struct ProfileTopEnvelope: Decodable, Sendable {
    let success: Bool?
    let data: UserProfileAPIModel?
}

private struct UploadPhotoEnvelope: Decodable, Sendable {
    let success: Bool?
    let data: UploadPhotoData?
}

private struct UploadPhotoData: Decodable, Sendable {
    let url: String?
}

/// Decodes JSON `id` as either a string or number (Postgres / Express may emit either).
enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected string or int for id")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        }
    }

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        }
    }
}
