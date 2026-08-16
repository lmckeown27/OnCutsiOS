//
//  PlatformFrontendConfig.swift
//  OnCuts
//
//  Public `GET /api/v1/platform/frontend-config` — admin switch for consumer Home
//  (`providers` nearby list vs `waitlist` user count), cash checkout, Service Fee quote, and home reviews.
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
    /// Who pays the platform Service Fee. Missing / unknown → operator (no client fee).
    var feeBurden: PlatformFeeBurden
    /// Missing → `true` (same as web). Combined with operator burden, quote stays $0.
    var platformCommissionEnabled: Bool
    /// 0–100. Invalid or missing → 15.
    var platformFeePercent: Double
    /// Consumer Home provider cards / profile sheet. Missing → `true` (same as web `!== false`).
    var consumerHomeReviewsEnabled: Bool

    static let fallbackProviders = PlatformFrontendConfig(
        cashPaymentEnabled: false,
        consumerHomeMode: .providers,
        consumerUserCount: 0,
        feeBurden: .operatorBurden,
        platformCommissionEnabled: true,
        platformFeePercent: 15,
        consumerHomeReviewsEnabled: true
    )

    static func sanitizedPercent(_ raw: Double?) -> Double {
        guard let raw, raw.isFinite, raw >= 0, raw <= 100 else { return 15 }
        return raw
    }

    enum CodingKeys: String, CodingKey {
        case cashPaymentEnabled
        case consumerHomeMode
        case consumerUserCount
        case feeBurden
        case platformCommissionEnabled
        case platformFeePercent
        case consumerHomeReviewsEnabled
    }

    init(
        cashPaymentEnabled: Bool,
        consumerHomeMode: ConsumerHomeMode,
        consumerUserCount: Int,
        feeBurden: PlatformFeeBurden,
        platformCommissionEnabled: Bool,
        platformFeePercent: Double,
        consumerHomeReviewsEnabled: Bool
    ) {
        self.cashPaymentEnabled = cashPaymentEnabled
        self.consumerHomeMode = consumerHomeMode
        self.consumerUserCount = consumerUserCount
        self.feeBurden = feeBurden
        self.platformCommissionEnabled = platformCommissionEnabled
        self.platformFeePercent = platformFeePercent
        self.consumerHomeReviewsEnabled = consumerHomeReviewsEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cashPaymentEnabled = try c.decodeIfPresent(Bool.self, forKey: .cashPaymentEnabled) ?? false
        consumerHomeMode = try c.decodeIfPresent(ConsumerHomeMode.self, forKey: .consumerHomeMode) ?? .providers
        consumerUserCount = try c.decodeIfPresent(Int.self, forKey: .consumerUserCount) ?? 0
        feeBurden = PlatformFeeBurden.parse(try c.decodeIfPresent(String.self, forKey: .feeBurden))
        platformCommissionEnabled = try c.decodeIfPresent(Bool.self, forKey: .platformCommissionEnabled) ?? true
        platformFeePercent = Self.sanitizedPercent(try c.decodeIfPresent(Double.self, forKey: .platformFeePercent))
        consumerHomeReviewsEnabled = try c.decodeIfPresent(Bool.self, forKey: .consumerHomeReviewsEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cashPaymentEnabled, forKey: .cashPaymentEnabled)
        try c.encode(consumerHomeMode, forKey: .consumerHomeMode)
        try c.encode(consumerUserCount, forKey: .consumerUserCount)
        try c.encode(feeBurden.rawValue, forKey: .feeBurden)
        try c.encode(platformCommissionEnabled, forKey: .platformCommissionEnabled)
        try c.encode(platformFeePercent, forKey: .platformFeePercent)
        try c.encode(consumerHomeReviewsEnabled, forKey: .consumerHomeReviewsEnabled)
    }
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
        let feeBurden: String?
        let platformCommissionEnabled: Bool?
        let platformFeePercent: Double?
        let consumerHomeReviewsEnabled: Bool?

        private enum CodingKeys: String, CodingKey {
            case cashPaymentEnabled
            case consumerHomeMode
            case consumerUserCount
            case feeBurden
            case platformCommissionEnabled
            case platformFeePercent
            case consumerHomeReviewsEnabled
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            cashPaymentEnabled = try c.decodeIfPresent(Bool.self, forKey: .cashPaymentEnabled)
            consumerHomeMode = try c.decodeIfPresent(String.self, forKey: .consumerHomeMode)
            consumerUserCount = try c.decodeIfPresent(Int.self, forKey: .consumerUserCount)
            feeBurden = try c.decodeIfPresent(String.self, forKey: .feeBurden)
            platformCommissionEnabled = try c.decodeIfPresent(Bool.self, forKey: .platformCommissionEnabled)
            if let d = try c.decodeIfPresent(Double.self, forKey: .platformFeePercent) {
                platformFeePercent = d
            } else if let i = try c.decodeIfPresent(Int.self, forKey: .platformFeePercent) {
                platformFeePercent = Double(i)
            } else if let s = try c.decodeIfPresent(String.self, forKey: .platformFeePercent),
                      let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                platformFeePercent = d
            } else {
                platformFeePercent = nil
            }
            consumerHomeReviewsEnabled = try c.decodeIfPresent(Bool.self, forKey: .consumerHomeReviewsEnabled)
        }
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
            consumerUserCount: max(0, payload.consumerUserCount ?? 0),
            feeBurden: PlatformFeeBurden.parse(payload.feeBurden),
            platformCommissionEnabled: payload.platformCommissionEnabled ?? true,
            platformFeePercent: PlatformFrontendConfig.sanitizedPercent(payload.platformFeePercent),
            consumerHomeReviewsEnabled: payload.consumerHomeReviewsEnabled ?? true
        )
    }
}

/// Shared cache so Home can paint last-known mode while refreshing.
@Observable
@MainActor
final class PlatformFrontendConfigStore {
    static let shared = PlatformFrontendConfigStore()

    private static let cacheKey = "oncuts.platformFrontendConfig.v2"

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

    /// Consumer Home ratings/reviews. Missing config treats as on; a failed fetch also falls back to on (same as web).
    var consumerHomeReviewsEnabled: Bool {
        config.consumerHomeReviewsEnabled
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
            // Fail closed for cash and client Service Fee: never invent a fee when config is unknown.
            config = PlatformFrontendConfig(
                cashPaymentEnabled: false,
                consumerHomeMode: config.consumerHomeMode,
                consumerUserCount: config.consumerUserCount,
                feeBurden: .operatorBurden,
                platformCommissionEnabled: config.platformCommissionEnabled,
                platformFeePercent: config.platformFeePercent,
                consumerHomeReviewsEnabled: true
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
