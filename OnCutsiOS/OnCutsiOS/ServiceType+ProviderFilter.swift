//
//  ServiceType+ProviderFilter.swift
//  Intera
//
//  Infers `ServiceType` from `ServiceProvider` and filters the browse list.
//

import OnCutsModule
import Foundation

extension ServiceType {
    /// Filters the live / mock provider list for the browse grid by **provider kind** (not broad “Beauty”).
    func filteredProviders(from providers: [ServiceProvider]) -> [ServiceProvider] {
        guard self != .all else { return providers }
        return providers.filter { $0.browseServiceType == self }
    }

    /// Resolved provider kind for filtering and card copy, using `specialty`, `bio`, and `category`.
    static func inferred(from provider: ServiceProvider) -> ServiceType {
        let primary = provider.specialty?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let blob = "\(primary) \(provider.bio ?? "") \(provider.businessName)"
            .lowercased()

        if blob.contains("barber") { return .barber }
        if blob.contains("makeup") || blob.contains("make-up") || blob.contains("mua") { return .makeup }
        if blob.contains("tanning") || blob.contains("spray tan") || blob.contains("spray-tan") { return .tanning }
        if blob.contains("nail") { return .nails }
        if blob.contains("lash") { return .lashes }
        if blob.contains("braid") { return .braids }
        if blob.contains("massage") || blob.contains("facial") || blob.contains("spa therapy") {
            return .massage
        }
        if blob.contains("train") || blob.contains("fitness") || blob.contains("coach")
            || blob.contains("gym") || blob.contains("yoga") || blob.contains("pilates")
        {
            return .fitness
        }

        // Haircuts / barbering wording without the word “barber”
        if primary.contains("fade") || primary.contains("taper") || primary.contains("buzz")
            || primary.contains("line up") || primary.contains("lineup") || primary.contains("haircut")
        {
            return .barber
        }

        // Standalone “hair” = stylist (not barber); mock data uses specialty "Hair"
        if primary == "hair" || primary.hasPrefix("hair stylist") || primary.contains("hair stylist") {
            return .hair
        }
        if primary.contains("hair") && !primary.contains("chair") && !primary.contains("haircut") {
            return .hair
        }

        switch provider.category {
        case .haircuts:
            return .barber
        case .beauty:
            if primary.contains("hair") { return .hair }
            return .makeup
        case .wellness:
            return .massage
        case .fitness:
            return .fitness
        case .none:
            return .barber
        }
    }
}

extension ServiceProvider {
    /// Kind used for toolbar tags, filtering, and the card pill.
    var browseServiceType: ServiceType {
        ServiceType.inferred(from: self)
    }

    /// Human-readable provider kind (e.g. “Barber”, “Nails”) for the front card.
    var providerKindDisplayName: String {
        browseServiceType.toolbarTitle
    }
}
