//
//  BookingOpenDaysLoader.swift
//  OnCuts
//
//  Prefetches which calendar days have at least one open booking slot.
//

import Foundation
import OnCutsModule

enum BookingOpenDaysLoader {
    /// Returns `Calendar.current` start-of-day instants that have ≥1 available slot.
    static func loadOpenDayStarts(
        days: [Date],
        barberId: String,
        onCutsBarberId: String,
        bearerToken: String?,
        onCutsClient: OnCutsClient,
        durationMinutes: Int
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
                        onCutsBarberId: onCutsBarberId,
                        bearerToken: bearerToken,
                        onCutsClient: onCutsClient,
                        durationMinutes: durationMinutes
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
        onCutsBarberId: String,
        bearerToken: String?,
        onCutsClient: OnCutsClient,
        durationMinutes: Int
    ) async -> Bool {
        let dayStr = BookingPacificSchedule.apiDateString(from: day)
        let trimmedPackageId = onCutsBarberId.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryDuration = BookingAvailabilityQuery.clampedDurationMinutes(durationMinutes)

        if !trimmedPackageId.isEmpty {
            do {
                let slots = try await onCutsClient.fetchBarberDayAvailability(
                    barberId: trimmedPackageId,
                    dateYYYYMMDD: dayStr,
                    durationMinutes: queryDuration
                )
                if slots.contains(where: { $0.isAvailable }) {
                    return true
                }
            } catch {
                if OnCutsRefreshCancellation.isBenignCancellation(error) { return false }
            }
        }

        do {
            let rows = try await BarberAvailabilityAPI.fetchDaySlots(
                barberId: barberId,
                dateYYYYMMDD: dayStr,
                durationMinutes: queryDuration,
                bearerToken: bearerToken
            )
            return rows.contains(where: \.available)
        } catch {
            if OnCutsRefreshCancellation.isBenignCancellation(error) { return false }
            return false
        }
    }
}
