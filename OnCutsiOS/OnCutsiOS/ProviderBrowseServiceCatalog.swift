//
//  ProviderBrowseServiceCatalog.swift
//  OnCuts
//
//  Catalog of offerable services per `provider_type` (matches provider_types × services join).
//

import OnCutsModule
import Foundation

/// Service names under each Home Tags provider type (Barber / Beauty).
enum ProviderBrowseServiceCatalog {
    /// Ordered service chips for a selected provider type (includes services with zero providers).
    static func serviceNames(for type: ServiceType) -> [String] {
        switch type {
        case .all:
            return []
        case .barber:
            return [
                "Afro Textures",
                "Beard Trim",
                "Buzz Cut",
                "Color Treatment",
                "Design/Art",
                "Fade",
                "Haircut",
                "Hot Shave",
                "Kids Cut",
                "Line Up",
                "Mullet",
                "Perm",
                "Taper",
            ]
        case .beauty:
            return [
                "Braids",
                "Lashes",
                "Makeup",
                "Nails",
                "Tanning",
            ]
        }
    }
}

extension ServiceProvider {
    /// Whether this provider’s menu includes `serviceName` (case-insensitive).
    func offersBrowseService(_ serviceName: String) -> Bool {
        let needle = serviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        guard let services, !services.isEmpty else { return false }
        return services.contains { row in
            row.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle
        }
    }
}
