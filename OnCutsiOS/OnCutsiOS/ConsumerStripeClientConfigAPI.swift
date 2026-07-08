//
//  ConsumerStripeClientConfigAPI.swift
//  OnCuts
//
//  Fetches the Stripe publishable key (`/api/v1/stripe/client-config`, with a bookings-simple alias) so the
//  app matches the server’s Stripe mode when `STRIPE_PUBLISHABLE_KEY` is set (xcconfig can still lag).
//

import Foundation

enum ConsumerStripeClientConfigAPI {
    private struct Envelope: Decodable {
        let success: Bool?
        let publishableKey: String?
    }

    /// Returns the server’s publishable key when an endpoint returns 200 + `pk_…`; otherwise `nil` (caller keeps plist / xcconfig).
    static func fetchPublishableKeyIfAvailable(apiBaseURLTrimmed: String) async -> String? {
        let root = apiBaseURLTrimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return nil }
        let candidates = [
            root + "/stripe/client-config",
            root + "/bookings-simple/stripe/client-config",
        ]
        for path in candidates {
            guard let url = URL(string: path) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  let http = resp as? HTTPURLResponse,
                  http.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(Envelope.self, from: data),
                  decoded.success == true,
                  let pk = decoded.publishableKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  pk.hasPrefix("pk_")
            else {
                continue
            }
            return pk
        }
        return nil
    }
}
