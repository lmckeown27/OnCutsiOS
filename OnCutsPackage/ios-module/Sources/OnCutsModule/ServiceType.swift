//
//  ServiceType.swift
//  OnCutsModule
//
//  Browse Tags chips — All / Barber / Beauty. Untyped operators stay Operator until they choose.
//

import Foundation

/// Provider kind for toolbar Tags and list filtering (`all` shows everyone).
/// Raw values match `provider_types.provider_type` in Postgres.
public enum ServiceType: String, CaseIterable, Identifiable, Sendable, Hashable {
    case all
    case barber
    case beauty

    public var id: String { rawValue }

    /// Chip / card label — matches `provider_types.label`.
    public var toolbarTitle: String {
        switch self {
        case .all: return "All"
        case .barber: return "Barber"
        case .beauty: return "Beauty"
        }
    }

    public var systemImageName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .barber: return "scissors"
        case .beauty: return "sparkles"
        }
    }

    /// Parses API / DB `provider_type` (case-insensitive).
    public static func fromProviderType(_ raw: String?) -> ServiceType? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !t.isEmpty, t != "all" else { return nil }
        return ServiceType(rawValue: t)
    }

    /// Tag chips shown in the Home Tags strip (includes `all`).
    public static var browseTagCases: [ServiceType] { Array(allCases) }

    /// Next value when cycling (e.g. programmatic tools); UI browse uses the tag strip instead.
    public var next: ServiceType {
        let order = Self.allCases
        guard let i = order.firstIndex(of: self) else { return .all }
        return order[(i + 1) % order.count]
    }
}
