//
//  CampusCutsAPIDecoding.swift
//  CampusCutsModule
//
//  Shared JSON envelope + flexible field decoding for Express `{ success, data }` responses.
//

import Foundation

internal struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool?
    let data: T?
    let message: String?
    let error: String?
}

internal struct FlexibleStringID: Decodable, Hashable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self), double == double.rounded() {
            value = String(Int(double))
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected String or Int id")
        }
    }
}

internal struct FlexibleIntValue: Decodable, Hashable, Sendable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = Int(double.rounded())
        } else if let string = try? container.decode(String.self),
                  let parsed = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            value = parsed
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected numeric value")
        }
    }
}

internal struct FlexibleDoubleValue: Decodable, Hashable, Sendable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let int = try? container.decode(Int.self) {
            value = Double(int)
        } else if let string = try? container.decode(String.self),
                  let parsed = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            value = parsed
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected numeric value")
        }
    }
}

internal enum CampusCutsAPIDecoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func decodePayload<T: Decodable>(_ type: T.Type, from data: Data, decoder: JSONDecoder) throws -> T {
        if data.isEmpty {
            throw CampusCutsAPIError.decodingError(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Empty response body"))
            )
        }

        if let prefix = String(data: data.prefix(64), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           prefix.hasPrefix("<") {
            throw CampusCutsAPIError.decodingError(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Server returned HTML instead of JSON"))
            )
        }

        if let envelope = try? decoder.decode(APIEnvelope<T>.self, from: data) {
            if envelope.success == false {
                let message = envelope.message ?? envelope.error ?? "Request failed"
                throw CampusCutsAPIError.serverError(statusCode: 0, message: message)
            }
            if let payload = envelope.data {
                return payload
            }
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CampusCutsAPIError.decodingError(error)
        }
    }
}

internal struct BarberListRowDTO: Decodable {
    let id: FlexibleStringID
    let userId: FlexibleStringID?
    let name: String?
    let displayName: String?
    let firstName: String?
    let lastName: String?
    let bio: String?
    let profilePictureUrl: String?
    let profileImageUrl: String?
    let avatarUrl: String?
    let campusId: FlexibleStringID?
    let campusName: String?
    let averageRating: Double?
    let reviewCount: Int?
    let totalBookings: Int?
    let isActive: Bool?

    func asBarber() -> Barber {
        let business = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? [firstName, lastName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                .joined(separator: " ")
                .nilIfEmpty
            ?? "Provider"
        let image = [profilePictureUrl, profileImageUrl, avatarUrl]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .first
        return Barber(
            id: id.value,
            userId: userId?.value ?? id.value,
            businessName: business,
            bio: bio?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            profileImageUrl: image,
            campusId: campusId?.value,
            campusName: campusName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            rating: averageRating,
            reviewCount: reviewCount,
            isAvailableNow: isActive,
            completedBookings: totalBookings
        )
    }
}

internal struct BarberDetailDTO: Decodable {
    let id: FlexibleStringID?
    let userId: FlexibleStringID?
    let name: String?
    let displayName: String?
    let firstName: String?
    let lastName: String?
    let bio: String?
    let profilePictureUrl: String?
    let profileImageUrl: String?
    let avatarUrl: String?
    let campusId: FlexibleStringID?
    let campusName: String?
    let averageRating: Double?
    let reviewCount: Int?
    let totalBookings: Int?
    let pricing: [BarberPricingRowDTO]?
    let portfolioImages: [BarberPortfolioImageDTO]?
    let reviews: [BarberReviewRowDTO]?

    func asProfile(fallbackBarberId: String) -> BarberProfile {
        let business = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? [firstName, lastName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                .joined(separator: " ")
                .nilIfEmpty
            ?? "Provider"
        let image = [profilePictureUrl, profileImageUrl, avatarUrl]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .first
        let services = pricing?.enumerated().map { index, row in
            BarberService(
                id: row.id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "svc-\(index)",
                barberId: id?.value ?? fallbackBarberId,
                name: row.name,
                description: row.description,
                price: row.price.value,
                durationMinutes: row.durationMinutes?.value ?? 30,
                isActive: row.isActive ?? true
            )
        }
        let portfolio = portfolioImages?
            .compactMap { $0.imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? $0.url?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        return BarberProfile(
            id: id?.value ?? fallbackBarberId,
            userId: userId?.value ?? id?.value ?? fallbackBarberId,
            businessName: business,
            bio: bio?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            profileImageUrl: image,
            campusId: campusId?.value,
            campusName: campusName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            rating: averageRating,
            reviewCount: reviewCount,
            services: services,
            availability: nil,
            portfolioImages: portfolio,
            reviews: reviews?.map { $0.asReview(barberId: id?.value ?? fallbackBarberId) }
        )
    }
}

internal struct BarberPricingRowDTO: Decodable {
    let id: String?
    let name: String
    let price: FlexibleDoubleValue
    let durationMinutes: FlexibleIntValue?
    let description: String?
    let isActive: Bool?
}

internal struct BarberPortfolioImageDTO: Decodable {
    let imageUrl: String?
    let url: String?
}

internal struct BarberReviewRowDTO: Decodable {
    let id: FlexibleStringID?
    let consumerName: String?
    let rating: FlexibleIntValue?
    let comment: String?
    let createdAt: String?

    func asReview(barberId: String) -> Review {
        Review(
            id: id?.value ?? UUID().uuidString,
            bookingId: "",
            barberId: barberId,
            consumerId: "",
            consumerName: consumerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            rating: rating?.value ?? 0,
            comment: comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: createdAt ?? ""
        )
    }
}

internal struct AvailabilityDayDTO: Decodable {
    let date: String?
    let slots: [AvailabilitySlotDTO]?
}

internal struct AvailabilitySlotDTO: Decodable {
    let time: String?
    let available: Bool?
    let startTime: String?
    let endTime: String?
    let start: String?
    let end: String?

    var normalizedStartTime: String {
        let candidates = [time, startTime, start]
        for candidate in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                return value
            }
        }
        return ""
    }

    var normalizedEndTime: String {
        let candidates = [endTime, end]
        for candidate in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                return value
            }
        }
        return normalizedStartTime
    }

    var isAvailableSlot: Bool {
        available ?? true
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
