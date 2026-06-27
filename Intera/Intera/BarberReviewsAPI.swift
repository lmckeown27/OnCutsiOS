//
//  BarberReviewsAPI.swift
//  Intera
//
//  Loads reviews for a barber. Production serves them on `GET /barbers/:id` (`data.reviews`);
//  dedicated list routes are used as fallbacks when present.
//

import Foundation

private struct BarberDetailEnvelope: Decodable, Sendable {
    let success: Bool?
    let data: BarberDetailData?
}

private struct BarberDetailData: Decodable, Sendable {
    let reviews: [AvilaPlatformsReviewDTO]?
}

enum BarberReviewsAPI {
    /// Loads review rows for a barber. Public; sends Bearer when available.
    static func fetchReviews(barberId: String, bearerToken: String?) async throws -> [ProviderReview] {
        let trimmed = barberId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // 1) Production: `GET /barbers/:id` embeds `data.reviews` (bookings-backed).
        if let detailURL = AppConfiguration.urlAvilaPlatformsBarber(barberId: trimmed) {
            do {
                let data = try await getJSON(from: detailURL, bearerToken: bearerToken)
                let envelope = try decoder.decode(BarberDetailEnvelope.self, from: data)
                if envelope.success != false {
                    let rows = envelope.data?.reviews ?? []
                    // Successful barber payload is authoritative (empty `reviews` = none yet).
                    return rows.asProviderReviews(barberId: trimmed)
                }
            } catch {
                #if DEBUG
                print("⚠️ BarberReviewsAPI: detail \(detailURL.absoluteString) — \(error.localizedDescription)")
                #endif
            }
        }

        return try await fetchReviewsFromListEndpoints(barberId: trimmed, bearerToken: bearerToken, decoder: decoder)
    }

    private static func fetchReviewsFromListEndpoints(
        barberId: String,
        bearerToken: String?,
        decoder: JSONDecoder
    ) async throws -> [ProviderReview] {
        let candidates: [URL?] = [
            AppConfiguration.urlBarberReviews(barberId: barberId),
            AppConfiguration.urlReviewsForBarber(barberId: barberId),
        ]

        for candidate in candidates.compactMap({ $0 }) {
            do {
                let data = try await getJSON(from: candidate, bearerToken: bearerToken)
                let envelope = try decoder.decode(AvilaPlatformsBarberReviewsListResponse.self, from: data)
                guard envelope.success != false, let rows = envelope.data, !rows.isEmpty else { continue }
                return rows.asProviderReviews(barberId: barberId)
            } catch {
                #if DEBUG
                print("⚠️ BarberReviewsAPI: list \(candidate.absoluteString) — \(error.localizedDescription)")
                #endif
            }
        }

        return []
    }

    private static func getJSON(from url: URL, bearerToken: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw NSError(
                domain: "BarberReviewsAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }
        return data
    }
}
