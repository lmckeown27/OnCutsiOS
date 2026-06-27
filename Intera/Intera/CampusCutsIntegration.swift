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
        ServiceProvider(
            id: id,
            userId: userId,
            businessName: businessName,
            bio: bio,
            instagramHandle: nil,
            profileImageUrl: ProfileImageURLResolver.normalizedStorageString(from: profileImageUrl),
            rating: rating,
            reviewCount: reviewCount,
            completedBookings: completedBookings,
            isAvailableNow: isAvailableNow,
            priceRange: nil,
            category: .haircuts,
            specialty: "Barber",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: distanceMiles,
            customerReviews: nil
        )
    }
}
