//
//  CampusCutsIntegration.swift
//  Intera
//
//  Single bridge between the Intera shell and CampusCutsModule (API root, session, client factory).
//

import Foundation
import CampusCutsModule

@MainActor
enum CampusCutsIntegration {
    /// Shared session bridge — register from `RootView.onAppear` via `CampusCutsSessionSync`.
    static weak var sessionManager: AppSessionManager?

    /// Package API root — always matches `AppConfiguration` so shell + module hit the same deployment.
    static var moduleEnvironment: CampusCutsEnvironment {
        .custom(baseURL: AppConfiguration.apiBaseURL)
    }

    /// Trimmed `/api/v1` root for auth/sign-up APIs that take `apiV1BaseTrimmed`.
    static var apiV1BaseTrimmed: String {
        AppConfiguration.messagingAPIRootTrimmed
    }

    static func sessionAdapter(for manager: AppSessionManager) -> CampusCutsUserSessionAdapter {
        CampusCutsUserSessionAdapter(manager: manager)
    }

    static func makeClient(sessionManager: AppSessionManager) -> CampusCutsClient {
        CampusCutsClient(
            session: sessionAdapter(for: sessionManager),
            environment: moduleEnvironment,
            isProduction: AppConfiguration.campusCutsProductionLiveDataMode
        )
    }

    static func makeClientIfAvailable() -> CampusCutsClient? {
        guard let sessionManager else { return nil }
        return makeClient(sessionManager: sessionManager)
    }
}

extension CampusCutsBrowseProviderRow {
    /// Maps module browse rows into the shell `ServiceProvider` model for existing UI.
    func asServiceProvider() -> ServiceProvider {
        let mappedServices: [ServiceProvider.Service]? = {
            guard let services, !services.isEmpty else { return nil }
            let rows = services.map { row in
                ServiceProvider.Service(
                    id: row.id,
                    name: row.name,
                    price: row.price,
                    duration: row.durationMinutes,
                    description: nil
                )
            }
            return ServiceProvider.orderServicesForDisplay(rows)
        }()

        let mappedPriceRange: ServiceProvider.PriceRange? = priceRange.map {
            ServiceProvider.PriceRange(min: $0.min, max: $0.max)
        }

        let mappedInstagram: String? = instagramHandle.flatMap { handle in
            let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return ServiceProvider(
            id: id,
            userId: userId,
            businessName: businessName,
            bio: bio,
            instagramHandle: mappedInstagram,
            profileImageUrl: ProfileImageURLResolver.normalizedStorageString(from: profileImageUrl),
            rating: rating,
            reviewCount: reviewCount,
            completedBookings: completedBookings,
            isAvailableNow: isAvailableNow,
            priceRange: mappedPriceRange,
            category: .haircuts,
            specialty: "Barber",
            services: mappedServices,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: distanceMiles,
            customerReviews: nil
        )
    }
}
