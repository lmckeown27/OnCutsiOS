//
//  OnCutsClient+ShellBooking.swift
//  OnCutsModule
//
//  Public API for host apps (e.g. OnCutsiOS) to load barber services and day availability
//  using the same networking stack as the module.
//

import Foundation

/// One bookable time range for a day (from `GET /barbers/:id/availability`).
public struct OnCutsDayAvailabilitySlot: Sendable, Hashable {
    public let startTime: String
    public let endTime: String
    public let isAvailable: Bool

    public init(startTime: String, endTime: String, isAvailable: Bool) {
        self.startTime = startTime
        self.endTime = endTime
        self.isAvailable = isAvailable
    }
}

/// Service + price row from `GET /barbers/:id` pricing (OnCuts backend).
public struct OnCutsBarberServiceRow: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let priceUsd: Int
    public let durationMinutes: Int

    public init(id: String, name: String, priceUsd: Int, durationMinutes: Int) {
        self.id = id
        self.name = name
        self.priceUsd = priceUsd
        self.durationMinutes = durationMinutes
    }
}

extension OnCutsClient {
    /// Fetches availability for a calendar day (`date` = `yyyy-MM-dd`).
    public func fetchBarberDayAvailability(barberId: String, dateYYYYMMDD: String) async throws -> [OnCutsDayAvailabilitySlot] {
        let trimmedId = barberId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return [] }
        let api = OnCutsAPIService(session: session, environment: environment)
        let slots = try await api.fetchBarberAvailability(barberId: trimmedId, date: dateYYYYMMDD)
        return slots.compactMap { slot in
            let start = slot.normalizedStartTime
            guard !start.isEmpty else { return nil }
            return OnCutsDayAvailabilitySlot(
                startTime: start,
                endTime: slot.normalizedEndTime,
                isAvailable: slot.isAvailableSlot
            )
        }
    }

    /// Active services with prices for chip / picker UIs.
    public func fetchBarberServiceRows(barberId: String) async throws -> [OnCutsBarberServiceRow] {
        let trimmedId = barberId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return [] }
        let api = OnCutsAPIService(session: session, environment: environment)
        let rows = try await api.fetchBarberServices(barberId: trimmedId)
        return rows
            .filter { $0.isActive != false }
            .map {
                OnCutsBarberServiceRow(
                    id: $0.id,
                    name: $0.name,
                    priceUsd: Int(round($0.price)),
                    durationMinutes: $0.durationMinutes
                )
            }
    }
}
