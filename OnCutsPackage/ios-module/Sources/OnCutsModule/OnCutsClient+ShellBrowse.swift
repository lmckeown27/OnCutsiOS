//
//  OnCutsClient+ShellBrowse.swift
//  OnCutsModule
//
//  Public browse-list API for host apps (Intera) — same `/barbers` payload the shell decodes locally.
//

import Foundation

/// One priced service from a browse-list row (`barbers.pricing`).
public struct OnCutsBrowseServiceRow: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let price: Int
    public let durationMinutes: Int?

    public init(id: String, name: String, price: Int, durationMinutes: Int?) {
        self.id = id
        self.name = name
        self.price = price
        self.durationMinutes = durationMinutes
    }
}

/// Min/max from a provider's pricing menu.
public struct OnCutsBrowsePriceRange: Sendable, Hashable {
    public let min: Int
    public let max: Int

    public init(min: Int, max: Int) {
        self.min = min
        self.max = max
    }
}

/// One provider row for the Intera browse grid (`GET /api/v1/barbers`).
public struct OnCutsBrowseProviderRow: Sendable, Hashable, Identifiable {
    public let id: String
    public let userId: String
    public let businessName: String
    public let bio: String?
    public let profileImageUrl: String?
    public let rating: Double?
    public let reviewCount: Int?
    public let completedBookings: Int?
    public let isAvailableNow: Bool?
    public let distanceMiles: Double?
    public let services: [OnCutsBrowseServiceRow]?
    public let priceRange: OnCutsBrowsePriceRange?
    public let instagramHandle: String?

    public init(
        id: String,
        userId: String,
        businessName: String,
        bio: String?,
        profileImageUrl: String?,
        rating: Double?,
        reviewCount: Int?,
        completedBookings: Int?,
        isAvailableNow: Bool?,
        distanceMiles: Double?,
        services: [OnCutsBrowseServiceRow]? = nil,
        priceRange: OnCutsBrowsePriceRange? = nil,
        instagramHandle: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.businessName = businessName
        self.bio = bio
        self.profileImageUrl = profileImageUrl
        self.rating = rating
        self.reviewCount = reviewCount
        self.completedBookings = completedBookings
        self.isAvailableNow = isAvailableNow
        self.distanceMiles = distanceMiles
        self.services = services
        self.priceRange = priceRange
        self.instagramHandle = instagramHandle
    }
}

extension OnCutsClient {
    /// Loads the consumer browse list from the module networking stack (auth + envelope decode).
    public func fetchBrowseProviders(
        campusId: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        maxDistanceKm: Double? = nil
    ) async throws -> [OnCutsBrowseProviderRow] {
        let api = OnCutsAPIService(session: session, environment: environment)
        let rows = try await api.fetchBarberListRows(
            campusId: campusId,
            latitude: latitude,
            longitude: longitude,
            maxDistanceKm: maxDistanceKm
        )
        return rows.map { $0.asBrowseProviderRow() }
    }
}

private extension BarberListRowDTO {
    func asBrowseProviderRow() -> OnCutsBrowseProviderRow {
        let business = trimmedNonEmpty(name)
            ?? trimmedNonEmpty(displayName)
            ?? joinedName(first: firstName, last: lastName)
            ?? "Provider"
        let image = trimmedNonEmpty(profilePictureUrl) ?? trimmedNonEmpty(profileImageUrl)
        let services = mappedBrowseServices()
        let priceRange = browsePriceRange(from: services)
        return OnCutsBrowseProviderRow(
            id: id.value,
            userId: userId?.value ?? id.value,
            businessName: business,
            bio: trimmedNonEmpty(bio),
            profileImageUrl: image,
            rating: averageRating,
            reviewCount: reviewCount,
            completedBookings: totalBookings,
            isAvailableNow: isActive,
            distanceMiles: distanceMiles,
            services: services,
            priceRange: priceRange,
            instagramHandle: trimmedNonEmpty(instagramHandle)
        )
    }

    func mappedBrowseServices() -> [OnCutsBrowseServiceRow]? {
        guard let pricing, !pricing.isEmpty else { return nil }
        let mapped = pricing.enumerated().map { index, row in
            OnCutsBrowseServiceRow(
                id: row.id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "svc-\(index)",
                name: row.name,
                price: Int(row.price.value.rounded()),
                durationMinutes: row.durationMinutes?.value
            )
        }
        return mapped.isEmpty ? nil : mapped
    }

    func browsePriceRange(from services: [OnCutsBrowseServiceRow]?) -> OnCutsBrowsePriceRange? {
        guard let services, !services.isEmpty else { return nil }
        let prices = services.map(\.price)
        guard let min = prices.min(), let max = prices.max() else { return nil }
        return OnCutsBrowsePriceRange(min: min, max: max)
    }

    func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func joinedName(first: String?, last: String?) -> String? {
        let parts = [first, last].compactMap { trimmedNonEmpty($0) }
        let combined = parts.joined(separator: " ")
        return combined.isEmpty ? nil : combined
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
