//
//  BookingOpenDaysLoader.swift
//  Intera
//
//  Prefetches which calendar days have at least one open booking slot.
//

import Foundation
import CampusCutsModule

enum BookingOpenDaysLoader {
    /// Returns `Calendar.current` start-of-day instants that have ≥1 available slot.
    static func loadOpenDayStarts(
        days: [Date],
        barberId: String,
        campusCutsBarberIntId: Int?,
        bearerToken: String?,
        campusCutsClient: CampusCutsClient
    ) async -> Set<Date> {
        guard !days.isEmpty else { return [] }
        let cal = Calendar.current

        return await withTaskGroup(of: (Date, Bool).self) { group in
            for day in days {
                group.addTask {
                    let start = cal.startOfDay(for: day)
                    let hasOpen = await dayHasOpenSlot(
                        day: day,
                        barberId: barberId,
                        campusCutsBarberIntId: campusCutsBarberIntId,
                        bearerToken: bearerToken,
                        campusCutsClient: campusCutsClient
                    )
                    return (start, hasOpen)
                }
            }

            var open = Set<Date>()
            for await (start, hasOpen) in group where hasOpen {
                open.insert(start)
            }
            return open
        }
    }

    private static func dayHasOpenSlot(
        day: Date,
        barberId: String,
        campusCutsBarberIntId: Int?,
        bearerToken: String?,
        campusCutsClient: CampusCutsClient
    ) async -> Bool {
        let dayStr = BookingPacificSchedule.apiDateString(from: day)

        if let bid = campusCutsBarberIntId {
            do {
                let slots = try await campusCutsClient.fetchBarberDayAvailability(
                    barberId: bid,
                    dateYYYYMMDD: dayStr
                )
                if slots.contains(where: { $0.isAvailable }) {
                    return true
                }
            } catch {
                if InteraRefreshCancellation.isBenignCancellation(error) { return false }
            }
        }

        do {
            let rows = try await BarberAvailabilityAPI.fetchDaySlots(
                barberId: barberId,
                dateYYYYMMDD: dayStr,
                bearerToken: bearerToken
            )
            return rows.contains(where: \.available)
        } catch {
            if InteraRefreshCancellation.isBenignCancellation(error) { return false }
            return false
        }
    }
}
