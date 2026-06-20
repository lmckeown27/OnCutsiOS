//
//  ProviderListAPIModels.swift
//  Intera
//
//  Lenient decoding for `/providers/list` so missing bio or avatar never crashes the app.
//

import Foundation

// MARK: - Decoding helpers (keeps `init(from:)` small for the type checker)

private extension KeyedDecodingContainer where K == ProviderListAPIItem.CodingKeys {
    /// Int, numeric string, or whole Double (avoids picking the wrong key when JSON has several counters).
    func flexibleInt(forKey key: K) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v = Int(t) { return v }
        }
        if let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite {
            return Int(d.rounded())
        }
        return nil
    }

    /// Uses the **maximum** across keys so a stray `completedBookings: 0` does not hide `total_bookings`.
    func maxFlexibleInt(keys: [K]) -> Int? {
        let values = keys.compactMap { flexibleInt(forKey: $0) }
        return values.max()
    }

    func firstDecodedInt(keys: [K]) -> Int? {
        for key in keys {
            if let v = flexibleInt(forKey: key) {
                return v
            }
        }
        return nil
    }
}

// MARK: - API item (all optional except identity fallbacks)

/// Raw JSON element from the live API; maps into `ServiceProvider` with safe defaults.
struct ProviderListAPIItem: Decodable, Sendable {
    var id: String?
    var userId: String?
    var businessName: String?
    var bio: String?
    var instagramHandle: String?
    var profileImageUrl: String?
    var rating: Double?
    var reviewCount: Int?
    var completedBookings: Int?
    var isAvailableNow: Bool?
    var category: String?
    var specialty: String?
    var priceMin: Int?
    var priceMax: Int?

    enum CodingKeys: String, CodingKey {
        case id, userId, user_id, businessName, business_name, name, bio
        case instagramHandle, instagram_handle
        case profileImageUrl, profile_image_url, avatar, imageUrl
        case rating, reviewCount, review_count, completedBookings, completed_bookings, totalBookings, total_bookings
        case isAvailableNow, is_available_now, category, specialty
        case priceMin, price_max, priceMax, price_min
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        func str(_ k: CodingKeys) -> String? {
            if let s = try? c.decodeIfPresent(String.self, forKey: k) { return s }
            if let i = try? c.decodeIfPresent(Int.self, forKey: k) { return String(i) }
            return nil
        }

        id = str(.id)
        userId = str(.userId) ?? str(.user_id)
        businessName = str(.businessName) ?? str(.business_name) ?? str(.name)
        bio = str(.bio)
        instagramHandle = str(.instagramHandle) ?? str(.instagram_handle)
        profileImageUrl = str(.profileImageUrl) ?? str(.profile_image_url) ?? str(.avatar) ?? str(.imageUrl)
        profileImageUrl = ProfileImageURLResolver.normalizedStorageString(from: profileImageUrl)

        rating = try? c.decodeIfPresent(Double.self, forKey: .rating)

        reviewCount = c.maxFlexibleInt(keys: [.reviewCount, .review_count])

        completedBookings = c.maxFlexibleInt(keys: [
            .completedBookings,
            .completed_bookings,
            .totalBookings,
            .total_bookings,
        ])

        let availableCamel = try? c.decodeIfPresent(Bool.self, forKey: .isAvailableNow)
        let availableSnake = try? c.decodeIfPresent(Bool.self, forKey: .is_available_now)
        isAvailableNow = availableCamel ?? availableSnake

        category = str(.category)
        specialty = str(.specialty)

        priceMin = c.firstDecodedInt(keys: [.priceMin, .price_min])
        priceMax = c.firstDecodedInt(keys: [.priceMax, .price_max])
    }

    /// Stable `ServiceProvider` for the shell UI.
    func asServiceProvider(fallbackIndex: Int) -> ServiceProvider {
        let pid: String
        if let validId = id, !validId.isEmpty {
            pid = validId
        } else {
            pid = "live-\(fallbackIndex)"
        }

        let uid: String
        if let validUserId = userId, !validUserId.isEmpty {
            uid = validUserId
        } else {
            uid = pid
        }

        let business: String
        if let validBusinessName = businessName, !validBusinessName.isEmpty {
            business = validBusinessName
        } else {
            business = "Provider"
        }

        let cat = parsedCategory()
        let range = parsedPriceRange()

        return ServiceProvider(
            id: pid,
            userId: uid,
            businessName: business,
            bio: bio,
            instagramHandle: instagramHandle,
            profileImageUrl: profileImageUrl,
            rating: rating,
            reviewCount: reviewCount,
            completedBookings: completedBookings,
            isAvailableNow: isAvailableNow,
            priceRange: range,
            category: cat,
            specialty: specialty,
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        )
    }

    private func parsedCategory() -> ServiceProvider.ServiceCategory? {
        guard let categoryString = category else { return nil }

        let trimmed = categoryString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()

        if lowercased.contains("hair") { return .haircuts }
        if lowercased.contains("barber") { return .haircuts }
        if lowercased.contains("cut") { return .haircuts }

        if lowercased.contains("beauty") { return .beauty }
        if lowercased.contains("makeup") { return .beauty }
        if lowercased.contains("nail") { return .beauty }

        if lowercased.contains("well") { return .wellness }
        if lowercased.contains("massage") { return .wellness }

        if lowercased.contains("fit") { return .fitness }
        if lowercased.contains("train") { return .fitness }

        return ServiceProvider.ServiceCategory(rawValue: categoryString)
    }

    private func parsedPriceRange() -> ServiceProvider.PriceRange? {
        let minValue = priceMin ?? priceMax
        let maxValue = priceMax ?? priceMin

        guard let min = minValue, let max = maxValue else {
            return nil
        }

        return ServiceProvider.PriceRange(min: min, max: max)
    }
}

private struct ProviderListEnvelope: Decodable, Sendable {
    let providers: [ProviderListAPIItem]?
    let data: [ProviderListAPIItem]?
    let results: [ProviderListAPIItem]?
    let items: [ProviderListAPIItem]?
    let barbers: [ProviderListAPIItem]?
}

enum ProviderListDecoder {
    static func decodeItems(from data: Data) throws -> [ServiceProvider] {
        let decoder = JSONDecoder()
        if let array = try? decoder.decode([ProviderListAPIItem].self, from: data) {
            return array.enumerated().map { $0.element.asServiceProvider(fallbackIndex: $0.offset) }
        }
        let env = try decoder.decode(ProviderListEnvelope.self, from: data)
        let raw = env.providers
            ?? env.data
            ?? env.results
            ?? env.items
            ?? env.barbers
            ?? []
        return raw.enumerated().map { $0.element.asServiceProvider(fallbackIndex: $0.offset) }
    }
}
