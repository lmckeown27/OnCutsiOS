//
//  CampusCutsClient+ShellBrowse.swift
//  CampusCutsModule
//
//  Public browse-list API for host apps (Intera) — same `/barbers` payload the shell decodes locally.
//

import Foundation

/// One provider row for the Intera browse grid (`GET /api/v1/barbers`).
public struct CampusCutsBrowseProviderRow: Sendable, Hashable, Identifiable {
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
        distanceMiles: Double?
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
    }
}

extension CampusCutsClient {
    /// Loads the consumer browse list from the module networking stack (auth + envelope decode).
    public func fetchBrowseProviders(
        campusId: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        maxDistanceKm: Double? = nil
    ) async throws -> [CampusCutsBrowseProviderRow] {
        let api = CampusCutsAPIService(session: session, environment: environment)
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
    func asBrowseProviderRow() -> CampusCutsBrowseProviderRow {
        let business = trimmedNonEmpty(name)
            ?? trimmedNonEmpty(displayName)
            ?? joinedName(first: firstName, last: lastName)
            ?? "Provider"
        let image = trimmedNonEmpty(profilePictureUrl) ?? trimmedNonEmpty(profileImageUrl)
        return CampusCutsBrowseProviderRow(
            id: id.value,
            userId: userId?.value ?? id.value,
            businessName: business,
            bio: trimmedNonEmpty(bio),
            profileImageUrl: image,
            rating: averageRating,
            reviewCount: reviewCount,
            completedBookings: totalBookings,
            isAvailableNow: isActive,
            distanceMiles: distanceMiles
        )
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
