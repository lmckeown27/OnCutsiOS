//
//  ServiceType+ProviderFilter.swift
//  OnCuts
//
//  Filters browse list by DB `provider_type` (Barber / Beauty Tags).
//  Untyped operators stay “Operator” until they choose Barber or Beauty.
//

import OnCutsModule
import Foundation

extension ServiceType {
    /// Filters the live / mock provider list for the browse grid by **provider_type**.
    func filteredProviders(from providers: [ServiceProvider]) -> [ServiceProvider] {
        guard self != .all else { return providers }
        return providers.filter { $0.browseServiceType == self }
    }

    /// Resolved provider kind for Tags filtering from API `provider_type`, then specialty / category.
    /// Returns `.all` when the operator has not chosen Barber or Beauty yet (still listed under All).
    static func inferred(from provider: ServiceProvider) -> ServiceType {
        if let fromAPI = fromProviderType(provider.providerType), fromAPI == .barber || fromAPI == .beauty {
            return fromAPI
        }

        let primary = provider.specialty?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if let fromSpecialty = fromProviderType(primary), fromSpecialty == .barber || fromSpecialty == .beauty {
            return fromSpecialty
        }
        if primary == "barber" || primary.contains("barber") {
            return .barber
        }
        if primary == "beauty" || primary.contains("beauty") {
            return .beauty
        }

        let blob = "\(primary) \(provider.bio ?? "")".lowercased()
        if blob.contains("beauty") || blob.contains("makeup") || blob.contains("nail")
            || blob.contains("lash") || blob.contains("braid") || blob.contains("tan")
        {
            return .beauty
        }
        // Do not infer Barber from business name / generic copy — that forced “Barber” before type choice.

        switch provider.category {
        case .beauty:
            return .beauty
        case .haircuts, .wellness, .fitness, .none:
            return .all
        }
    }
}

extension ServiceProvider {
    /// Kind used for toolbar Tags filtering (`.all` = untyped Operator).
    var browseServiceType: ServiceType {
        ServiceType.inferred(from: self)
    }

    /// Human-readable provider kind for cards: Barber / Beauty once chosen, otherwise Operator.
    var providerKindDisplayName: String {
        if let fromAPI = ServiceType.fromProviderType(providerType), fromAPI == .barber || fromAPI == .beauty {
            return fromAPI.toolbarTitle
        }
        let specialtyTrimmed = specialty?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lower = specialtyTrimmed.lowercased()
        if lower == "barber" || lower.hasPrefix("barber") { return "Barber" }
        if lower == "beauty" || lower.hasPrefix("beauty") { return "Beauty" }
        if lower == "operator" || specialtyTrimmed.isEmpty { return "Operator" }
        if lower == "all" { return "Operator" }
        // Explicit specialty label from API (already presentable).
        if !specialtyTrimmed.isEmpty { return specialtyTrimmed }
        return "Operator"
    }
}
