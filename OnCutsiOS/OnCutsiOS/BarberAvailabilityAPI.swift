//
//  BarberAvailabilityAPI.swift
//  Intera
//
//  GET /api/v1/barbers/:id/availability?date=YYYY-MM-DD
//

import Foundation

struct BarberAvailabilitySlotDTO: Decodable, Sendable, Hashable {
    let time: String
    let available: Bool
}

private struct BarberAvailabilityDayEnvelope: Decodable, Sendable {
    let success: Bool?
    let data: BarberAvailabilityDayData?
}

private struct BarberAvailabilityDayData: Decodable, Sendable {
    let date: String?
    let slots: [BarberAvailabilitySlotDTO]?
}

enum BarberAvailabilityAPI {
    /// Fetches 15-minute slots for a barber on a given calendar day (Pacific `date` string).
    static func fetchDaySlots(barberId: String, dateYYYYMMDD: String, bearerToken: String?) async throws -> [BarberAvailabilitySlotDTO] {
        let trimmedId = barberId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return [] }

        guard let url = AppConfiguration.urlBarberAvailability(barberId: trimmedId, dateYYYYMMDD: dateYYYYMMDD) else {
            throw URLError(.badURL)
        }

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
                domain: "BarberAvailabilityAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(BarberAvailabilityDayEnvelope.self, from: data)
        guard envelope.success != false else {
            return []
        }
        return envelope.data?.slots ?? []
    }
}
