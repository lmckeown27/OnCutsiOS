//
//  PlatformFrontendConfig.swift
//  OnCuts
//
//  Public `GET /api/v1/platform/frontend-config` — admin switch for consumer Home
//  (`providers` nearby list vs `waitlist` user count) plus cash checkout flag.
//

import Foundation
import Observation

enum ConsumerHomeMode: String, Codable, Sendable, Equatable {
    case providers
    case waitlist
}

struct PlatformFrontendConfig: Sendable, Equatable, Codable {
    var cashPaymentEnabled: Bool
    var consumerHomeMode: ConsumerHomeMode
    var consumerUserCount: Int

    static let fallbackProviders = PlatformFrontendConfig(
        cashPaymentEnabled: false,
        consumerHomeMode: .providers,
        consumerUserCount: 0
    )
}

enum PlatformFrontendConfigAPI {
    private struct Envelope: Decodable {
        let success: Bool?
        let data: Payload?
    }

    private struct Payload: Decodable {
        let cashPaymentEnabled: Bool?
        let consumerHomeMode: String?
        let consumerUserCount: Int?
    }

    enum FetchError: LocalizedError {
        case invalidURL
        case httpStatus(Int)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid frontend-config URL."
            case .httpStatus(let code):
                return "Frontend config request failed (\(code))."
            case .decodingFailed:
                return "Could not read frontend config."
            }
        }
    }

    /// Unauthenticated. Matches web `useFrontendConfig`.
    static func fetch(apiV1BaseTrimmed: String = AppConfiguration.messagingAPIRootTrimmed) async throws -> PlatformFrontendConfig {
        let base = apiV1BaseTrimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/platform/frontend-config") else {
            throw FetchError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200 ... 299).contains(code) else {
            throw FetchError.httpStatus(code)
        }
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data),
              envelope.success != false,
              let payload = envelope.data
        else {
            throw FetchError.decodingFailed
        }
        let modeRaw = (payload.consumerHomeMode ?? "providers")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let mode = ConsumerHomeMode(rawValue: modeRaw) ?? .providers
        return PlatformFrontendConfig(
            cashPaymentEnabled: payload.cashPaymentEnabled ?? false,
            consumerHomeMode: mode,
            consumerUserCount: max(0, payload.consumerUserCount ?? 0)
        )
    }
}

/// Shared cache so Home can paint last-known mode while refreshing.
@Observable
@MainActor
final class PlatformFrontendConfigStore {
    static let shared = PlatformFrontendConfigStore()

    private static let cacheKey = "oncuts.platformFrontendConfig.v1"

    private(set) var config: PlatformFrontendConfig
    private(set) var isLoading = false
    /// `false` until the first network attempt finishes (avoids flashing providers before waitlist mode resolves).
    private(set) var hasCompletedInitialFetch = false
    private(set) var lastErrorMessage: String?

    private init() {
        if let cached = Self.loadCache() {
            config = cached
            hasCompletedInitialFetch = true
        } else {
            config = .fallbackProviders
        }
    }

    var showsWaitlistHome: Bool {
        config.consumerHomeMode == .waitlist
    }

    /// Strict Admin flag — only `true` after a successful fetch (or a prior successful cache). Never invent `true` on error.
    var cashPaymentEnabled: Bool {
        config.cashPaymentEnabled == true
    }

    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            hasCompletedInitialFetch = true
        }
        do {
            let fresh = try await PlatformFrontendConfigAPI.fetch()
            config = fresh
            lastErrorMessage = nil
            Self.saveCache(fresh)
        } catch {
            // Fail closed for cash: never keep a stale `true` when the config request fails.
            config = PlatformFrontendConfig(
                cashPaymentEnabled: false,
                consumerHomeMode: config.consumerHomeMode,
                consumerUserCount: config.consumerUserCount
            )
            Self.saveCache(config)
            lastErrorMessage = error.localizedDescription
            ProductionLogging.recordNonFatal(error, context: ["area": "platform_frontend_config"])
        }
    }

    private static func loadCache() -> PlatformFrontendConfig? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(PlatformFrontendConfig.self, from: data)
    }

    private static func saveCache(_ value: PlatformFrontendConfig) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
