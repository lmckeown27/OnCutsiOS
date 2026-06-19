//
//  CampusCutsBarbersAPIModels.swift
//  Intera
//
//  Decodes GET /api/v1/barbers — { success, data, pagination, meta } — into ServiceProvider.
//

import Foundation

// MARK: - Response envelope

private struct CampusCutsBarbersResponse: Decodable, Sendable {
    let success: Bool?
    let data: [CampusCutsBarberDTO]?
}

private struct JSONStringOrInt: Decodable, Sendable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            value = s
        } else if let i = try? c.decode(Int.self) {
            value = String(i)
        } else if let d = try? c.decode(Double.self), d == d.rounded() {
            value = String(Int(d))
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected String or Int for id")
        }
    }
}

private struct CampusCutsBarberDTO: Decodable, Sendable {
    let id: JSONStringOrInt
    let userId: JSONStringOrInt?
    let name: String?
    let profilePictureUrl: String?
    let bio: String?
    let specialties: [String]?
    let pricing: [CampusCutsPricingDTO]?
    let averageRating: Double?
    let reviewCount: Int?
    /// Barber table lifetime bookings (`total_bookings` on `GET /barbers`).
    let totalBookings: Int?
    /// Some payloads expose completed-only counts separately (`completed_bookings`).
    let completedBookings: Int?
    let serviceLocations: [CampusCutsServiceLocationDTO]?
    /// Recent reviews when the list endpoint embeds them (see web `Barber.reviews`).
    let reviews: [CampusCutsReviewDTO]?
    /// Present when `GET /barbers` is called with user `lat`/`lng` — server Haversine distance to the barber’s service point.
    let distanceMiles: Double?
    let distanceKm: Double?
}

private struct CampusCutsPricingDTO: Decodable, Sendable {
    let id: String?
    let name: String
    let price: FlexibleIntDecodable
    let durationMinutes: Int?
}

private struct CampusCutsServiceLocationDTO: Decodable, Sendable {
    let id: String?
    let name: String?
}

/// Accepts JSON number as Int or Double.
private struct FlexibleIntDecodable: Decodable, Sendable {
    let value: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            value = i
        } else if let d = try? c.decode(Double.self) {
            value = Int(d.rounded())
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected Int or Double for price")
        }
    }
}

// MARK: - Decode + map

private struct CampusCutsBarberDetailResponse: Decodable, Sendable {
    let success: Bool?
    let data: CampusCutsBarberDTO?
}

enum CampusCutsBarbersDecoder {
    static func decodeServiceProviders(from data: Data) throws -> [ServiceProvider] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(CampusCutsBarbersResponse.self, from: data)
        guard response.success != false, let rows = response.data else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Missing success or data array")
            )
        }
        return rows.enumerated().map { index, dto in
            dto.asServiceProvider(fallbackIndex: index)
        }
    }

    /// `GET /api/v1/barbers/:id` — `data` is a single barber object (same shape as list rows).
    static func decodeSingleServiceProvider(from data: Data) throws -> ServiceProvider {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let envelope = try? decoder.decode(CampusCutsBarberDetailResponse.self, from: data),
           envelope.success != false,
           let dto = envelope.data {
            return dto.asServiceProvider(fallbackIndex: 0)
        }

        let list = try decodeServiceProviders(from: data)
        guard let first = list.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Could not decode barber detail payload")
            )
        }
        return first
    }
}

enum CampusCutsBarberDetailAPI {
    static func fetchServiceProvider(barberId: String, bearerToken: String?) async throws -> ServiceProvider {
        let trimmed = barberId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "CampusCutsBarberDetailAPI",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Missing barber id"]
            )
        }
        guard let url = AppConfiguration.urlCampusCutsBarber(barberId: trimmed) else {
            throw NSError(
                domain: "CampusCutsBarberDetailAPI",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid barber URL"]
            )
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
                domain: "CampusCutsBarberDetailAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }
        return try CampusCutsBarbersDecoder.decodeSingleServiceProvider(from: data)
    }
}

private extension CampusCutsBarberDTO {
    func asServiceProvider(fallbackIndex: Int) -> ServiceProvider {
        let rawId = id.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = rawId.isEmpty ? "barber-\(fallbackIndex)" : rawId
        let uid = userId.map(\.value).flatMap { $0.trimmedNonEmpty } ?? pid
        let business = name.flatMap { $0.trimmedNonEmpty } ?? "Barber"

        let services: [ServiceProvider.Service]? = {
            let mapped = pricing?.enumerated().map { index, p in
                ServiceProvider.Service(
                    id: p.id.flatMap { $0.trimmedNonEmpty } ?? "svc-\(fallbackIndex)-\(index)",
                    name: p.name,
                    price: p.price.value,
                    duration: p.durationMinutes,
                    description: nil
                )
            }
            guard let mapped, !mapped.isEmpty else { return nil }
            return ServiceProvider.orderServicesForDisplay(mapped)
        }()

        let prices = pricing?.map(\.price.value) ?? []
        let range: ServiceProvider.PriceRange? = {
            guard let min = prices.min(), let max = prices.max() else { return nil }
            return ServiceProvider.PriceRange(min: min, max: max)
        }()

        /// Front-of-house **provider kind** (e.g. Barber). Offerings stay in `services` from pricing — not listed here.
        let specialtyString: String? = "Barber"

        let locations: [String]? = {
            let names = serviceLocations?.compactMap { $0.name.flatMap { $0.trimmedNonEmpty } }
            return (names?.isEmpty == false) ? names : nil
        }()

        let embeddedReviews: [ProviderReview]? = {
            guard let rows = reviews, !rows.isEmpty else { return nil }
            let mapped = rows.asProviderReviews(barberId: pid)
            return mapped.isEmpty ? nil : mapped
        }()

        let lifetimeBookings: Int? = {
            switch (totalBookings, completedBookings) {
            case (nil, nil): return nil
            case let (t?, c?): return max(t, c)
            case (let t?, nil): return t
            case (nil, let c?): return c
            }
        }()

        return ServiceProvider(
            id: pid,
            userId: uid,
            businessName: business,
            bio: bio.flatMap { $0.trimmedNonEmpty },
            instagramHandle: nil,
            profileImageUrl: profilePictureUrl.flatMap { $0.trimmedNonEmpty },
            rating: averageRating,
            reviewCount: reviewCount,
            completedBookings: lifetimeBookings,
            isAvailableNow: nil,
            priceRange: range,
            category: .haircuts,
            specialty: specialtyString,
            services: services,
            availability: nil,
            locations: locations,
            distanceMilesFromUser: distanceMiles,
            customerReviews: embeddedReviews
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
