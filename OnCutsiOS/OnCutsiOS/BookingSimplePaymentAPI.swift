//
//  BookingSimplePaymentAPI.swift
//  OnCuts
//
//  Native checkout: `create-payment-intent` + `confirm-payment` (see `booking-simple.routes.ts`).
//

import Foundation

private struct CreatePIEnvelope: Decodable, Sendable {
    let success: Bool?
    let data: CreatePIData?
}

private struct CreatePIData: Decodable, Sendable {
    let clientSecret: String?
    let paymentIntentId: String?
}

private struct ConfirmPIEnvelope: Decodable, Sendable {
    let success: Bool?
}

enum BookingSimplePaymentAPI {
    static func isUnauthorizedHTTPError(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == "BookingSimplePaymentAPI" && ns.code == 401
    }

    /// `POST /api/v1/bookings-simple/:id/create-payment-intent`
    static func createPaymentIntent(
        bookingId: String,
        tipAmountCents: Int = 0,
        stripeAccountId: String? = nil,
        bearerToken: String?
    ) async throws -> (clientSecret: String, paymentIntentId: String) {
        let enc = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let url = URL(string: base + "/bookings-simple/\(enc)/create-payment-intent") else {
            throw URLError(.badURL)
        }
        var body: [String: Any] = [:]
        if tipAmountCents > 0 {
            body["tipAmountCents"] = tipAmountCents
        }
        if let sid = stripeAccountId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty {
            body["stripeAccountId"] = sid
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await authorizedJSON(url: url, method: "POST", bearerToken: bearerToken, body: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(CreatePIEnvelope.self, from: responseData)
        guard let d = decoded.data,
              let secret = d.clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty,
              let pi = d.paymentIntentId?.trimmingCharacters(in: .whitespacesAndNewlines), !pi.isEmpty else {
            throw NSError(
                domain: "BookingSimplePaymentAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing payment intent data."]
            )
        }
        return (secret, pi)
    }

    /// `POST /api/v1/bookings-simple/:id/confirm-payment` — marks booking `PAID` after Stripe succeeds.
    static func confirmPayment(
        bookingId: String,
        paymentIntentId: String,
        tipAmountCents: Int = 0,
        bearerToken: String?
    ) async throws {
        let enc = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let url = URL(string: base + "/bookings-simple/\(enc)/confirm-payment") else {
            throw URLError(.badURL)
        }
        let body: [String: Any] = [
            "paymentIntentId": paymentIntentId,
            "tipAmountCents": tipAmountCents,
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await authorizedJSON(url: url, method: "POST", bearerToken: bearerToken, body: data)
    }

    /// `POST /api/v1/bookings-simple/:id/pay` with `paymentMethod: cash` — marks booking `PAID` when the consumer paid in person (see `booking-simple.routes.ts`).
    static func payWithCash(bookingId: String, tipAmountCents: Int, bearerToken: String?) async throws {
        let enc = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let url = URL(string: base + "/bookings-simple/\(enc)/pay") else {
            throw URLError(.badURL)
        }
        let body: [String: Any] = [
            "tipAmountCents": tipAmountCents,
            "paymentMethod": "cash",
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await authorizedJSON(url: url, method: "POST", bearerToken: bearerToken, body: data)
    }

    /// `POST /api/v1/bookings-simple/:id/review` — `rating` must be 1…5 on the server; `comment` optional.
    static func submitReview(
        bookingId: String,
        rating: Int,
        comment: String?,
        bearerToken: String?
    ) async throws {
        let enc = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        let base = AppConfiguration.messagingAPIRootTrimmed
        guard let url = URL(string: base + "/bookings-simple/\(enc)/review") else {
            throw URLError(.badURL)
        }
        var body: [String: Any] = ["rating": rating]
        if let c = comment?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            body["comment"] = c
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await authorizedJSON(url: url, method: "POST", bearerToken: bearerToken, body: data)
    }

    private static func authorizedJSON(
        url: URL,
        method: String,
        bearerToken: String?,
        body: Data?
    ) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = bearerToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NSError(
                domain: "BookingSimplePaymentAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
        return data
    }
}
