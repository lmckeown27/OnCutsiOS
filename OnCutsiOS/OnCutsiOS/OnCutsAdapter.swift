//
//  OnCutsAdapter.swift
//  OnCuts
//
//  Adapter to convert OnCuts-specific models to unified ServiceProvider model
//

import Foundation

// MARK: - Barber → ServiceProvider Adapter
//
// NOTE: This extension will be enabled when the OnCuts package is integrated.
// The OnCuts package provides the `Barber` type that this adapter converts to `ServiceProvider`.
//
// To enable this when the package is added:
// 1. Uncomment the extension below
// 2. Import the OnCuts package at the top of this file
// 3. Verify the property names match (id, userId, fullName, bio, etc.)

/*
extension Barber {
    /// Converts a OnCuts Barber to the unified ServiceProvider model for UI display
    func toServiceProvider() -> ServiceProvider {
        ServiceProvider(
            id: self.id,
            userId: self.userId,
            businessName: self.fullName,
            bio: self.bio,
            instagramHandle: nil, // OnCuts Barber doesn't have this field
            profileImageUrl: self.profileImageUrl,
            rating: self.averageRating,
            reviewCount: nil, // Not available in Barber model
            completedBookings: self.totalBookings,
            isAvailableNow: self.instantBook, // Map instantBook to isAvailableNow
            priceRange: extractPriceRange()
        )
    }
    
    /// Extracts min/max price range from the pricing dictionary
    private func extractPriceRange() -> ServiceProvider.PriceRange? {
        guard !pricing.isEmpty else { return nil }
        
        let prices = pricing.values.sorted()
        guard let minPrice = prices.first, let maxPrice = prices.last else {
            return nil
        }
        
        return ServiceProvider.PriceRange(
            min: Int(minPrice),
            max: Int(maxPrice)
        )
    }
}
*/

// MARK: - ServiceProvider → Mock Data Helpers

extension ServiceProvider {
    /// Mock service providers from OnCuts barbers
    static var onCutsMocks: [ServiceProvider] {
        // This would convert actual Barber mocks when they exist
        // For now, return the mock barbers defined in ComponentsBarberCard.swift
        return ServiceProvider.mocks
    }
}

// MARK: - Usage Example

/*
 
 // When fetching from OnCuts API:
 let barbers = try await OnCutsAPI.fetchBarbers()
 let providers = barbers.map { $0.toServiceProvider() }
 
 // Display in UI:
 ForEach(providers) { provider in
     ServiceProviderCard(provider: provider)
 }
 
 */
