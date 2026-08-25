//
//  BookingAvailabilityQueryTests.swift
//  OnCutsTests
//

import Testing
@testable import OnCuts

struct BookingAvailabilityQueryTests {
    @Test func clampsDurationForAvailabilityQuery() {
        #expect(BookingAvailabilityQuery.clampedDurationMinutes(nil) == 30)
        #expect(BookingAvailabilityQuery.clampedDurationMinutes(45) == 45)
        #expect(BookingAvailabilityQuery.clampedDurationMinutes(5) == 15)
        #expect(BookingAvailabilityQuery.clampedDurationMinutes(300) == 240)
    }

    @Test func availabilityURLIncludesDurationMinutes() {
        let url = AppConfiguration.urlBarberAvailability(
            barberId: "barber-1",
            dateYYYYMMDD: "2026-08-25",
            durationMinutes: 45
        )
        let query = try #require(url?.absoluteString)
        #expect(query.contains("date=2026-08-25"))
        #expect(query.contains("durationMinutes=45"))
    }
}
