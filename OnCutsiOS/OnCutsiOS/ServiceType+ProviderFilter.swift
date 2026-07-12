//
//  ServiceType+ProviderFilter.swift
//  OnCuts
//
//  Filters browse list by DB `provider_type` (Barber / Beauty Tags).
//

import OnCutsModule
import Foundation

extension ServiceType {
    /// Filters the live / mock provider list for the browse grid by **provider_type**.
    func filteredProviders(from providers: [ServiceProvider]) -> [ServiceProvider] {
        guard self != .all else { return providers }
        return providers.filter { $0.browseServiceType == self }
    }

    /// Resolved provider kind for filtering and card copy from API `provider_type`, then specialty / category fallbacks.
    static func inferred(from provider: ServiceProvider) -> ServiceType {
        if let fromAPI = fromProviderType(provider.providerType) {
            return fromAPI
        }

        let primary = provider.specialty?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if let fromSpecialty = fromProviderType(primary) {
            return fromSpecialty
        }
        if primary == "barber" || primary.contains("barber") { return .barber }
        if primary == "beauty" || primary.contains("beauty") { return .beauty }

        let blob = "\(primary) \(provider.bio ?? "") \(provider.businessName)".lowercased()
        if blob.contains("barber") { return .barber }
        if blob.contains("beauty") || blob.contains("makeup") || blob.contains("nail")
            || blob.contains("lash") || blob.contains("braid") || blob.contains("tan")
        {
            return .beauty
        }

        switch provider.category {
        case .haircuts:
            return .barber
        case .beauty:
            return .beauty
        case .wellness, .fitness, .none:
            return .barber
        }
    }
}

extension ServiceProvider {
    /// Kind used for toolbar Tags, filtering, and the card pill.
    var browseServiceType: ServiceType {
        ServiceType.inferred(from: self)
    }

    /// Human-readable provider kind (e.g. “Barber”, “Beauty”) for the front card.
    var providerKindDisplayName: String {
        browseServiceType.toolbarTitle
    }
}
