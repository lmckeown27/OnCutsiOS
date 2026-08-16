//
//  WeeklyScheduleMappingTests.swift
//  OnCutsTests
//

import Testing
@testable import OnCuts
import OnCutsModule

struct WeeklyScheduleMappingTests {
    @Test func formatsClockLikeWeb() {
        #expect(OnCutsWeeklyScheduleMapping.formatClock("09:00") == "9am")
        #expect(OnCutsWeeklyScheduleMapping.formatClock("09:30") == "9:30am")
        #expect(OnCutsWeeklyScheduleMapping.formatClock("12:00") == "12pm")
        #expect(OnCutsWeeklyScheduleMapping.formatClock("17:00") == "5pm")
        #expect(OnCutsWeeklyScheduleMapping.formatClock("00:00") == "12am")
    }

    @Test func mapsEnabledIntervalsAndSkipsClosedDays() throws {
        let json = """
        {
          "success": true,
          "data": [
            {
              "id": "b1",
              "name": "Test Barber",
              "weekly_schedule": {
                "monday": {
                  "enabled": true,
                  "intervals": [
                    { "start": "09:00", "end": "12:00" },
                    { "start": "14:00", "end": "18:00" }
                  ]
                },
                "tuesday": { "enabled": false, "intervals": [{ "start": "09:00", "end": "17:00" }] },
                "wednesday": { "enabled": true, "start": "10:00", "end": "16:00" }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let providers = try OnCutsBarbersDecoder.decodeServiceProviders(from: json)
        #expect(providers.count == 1)
        let days = try #require(providers[0].availability)
        #expect(days.map(\.dayOfWeek) == ["Mon", "Wed"])
        #expect(days[0].timeSlots == ["9am-12pm", "2pm-6pm"])
        #expect(days[1].timeSlots == ["10am-4pm"])
        #expect(providers[0].weeklyAvailabilityCardLine == "Mon, Wed")
    }
}
