//
//  MyBarbersDiscoverTests.swift
//  OnCutsTests
//

import Foundation
import Testing
@testable import OnCuts

struct MyBarbersDiscoverTests {
    @Test func coarsensStreetToCityAndRejectsOther() {
        #expect(MyBarbersDiscover.coarsenPublicLocationLabel("123 Main St, San Luis Obispo, CA") == "San Luis Obispo")
        #expect(MyBarbersDiscover.coarsenPublicLocationLabel("Poly Canyon Village") == "Poly Canyon Village")
        #expect(MyBarbersDiscover.coarsenPublicLocationLabel("Other") == nil)
        #expect(MyBarbersDiscover.coarsenPublicLocationLabel("  ") == nil)
        #expect(MyBarbersDiscover.coarsenPublicLocationLabel(nil) == nil)
    }

    @Test func publicLabelPrefersServiceLocationThenLocations() {
        #expect(
            MyBarbersDiscover.publicBroadLocationLabel(
                serviceLocationLabel: "1 Broad St, Boston, MA",
                locations: ["Campus Rec"]
            ) == "Boston"
        )
        #expect(
            MyBarbersDiscover.publicBroadLocationLabel(
                serviceLocationLabel: nil,
                locations: ["Campus Rec", "Other"]
            ) == "Campus Rec"
        )
        #expect(
            MyBarbersDiscover.publicBroadLocationLabel(
                serviceLocationLabel: "Other",
                locations: nil
            ) == nil
        )
    }

    @Test func bookingSeedsIgnoreCancelledAndSortByCountThenRecency() {
        let rows: [ConsumerBookingSimpleRow] = [
            makeRow(id: "1", barberId: "a", status: "COMPLETED", scheduled: "2026-01-01T12:00:00Z"),
            makeRow(id: "2", barberId: "a", status: "ACCEPTED", scheduled: "2026-02-01T12:00:00Z"),
            makeRow(id: "3", barberId: "b", status: "COMPLETED", scheduled: "2026-03-01T12:00:00Z"),
            makeRow(id: "4", barberId: "c", status: "CANCELLED", scheduled: "2026-04-01T12:00:00Z"),
            makeRow(id: "5", barberId: "b", status: "REJECTED", scheduled: "2026-05-01T12:00:00Z"),
        ]
        let seeds = MyBarbersDiscover.bookingSeeds(from: rows)
        #expect(seeds.map(\.barberId) == ["a", "b"])
        #expect(seeds[0].bookingCount == 2)
        #expect(seeds[1].bookingCount == 1)
    }

    @Test func nextOpenOpenNowAndHoursNotListed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // Wednesday 2026-09-02 15:00 UTC
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 15, minute: 0))!

        let availability = [
            ServiceProvider.DayAvailability(id: "wed", dayOfWeek: "Wed", timeSlots: ["9am-5pm"]),
            ServiceProvider.DayAvailability(id: "fri", dayOfWeek: "Fri", timeSlots: ["10am-2pm"]),
        ]
        let open = MyBarbersDiscover.nextOpenInfo(availability: availability, now: now, calendar: calendar)
        #expect(open.displayString == "Open now · until 5pm")
        #expect(open.sortMinutesFromNow == 0)

        let none = MyBarbersDiscover.nextOpenInfo(availability: nil, now: now, calendar: calendar)
        #expect(none.displayString == "Hours not listed")
    }

    @Test func discoverAreasClusterByLabelAndPinFallback() {
        let a = sampleProvider(
            id: "1",
            label: "Boston",
            lat: 42.36,
            lng: -71.06
        )
        let b = sampleProvider(
            id: "2",
            label: "boston",
            lat: 42.37,
            lng: -71.07
        )
        let c = sampleProvider(
            id: "3",
            label: nil,
            lat: 34.02,
            lng: -118.49
        )
        let areas = MyBarbersDiscover.buildDiscoverServiceAreas(from: [a, b, c])
        #expect(areas.count == 2)
        let boston = try #require(areas.first(where: { !$0.isTemporaryPinBucket }))
        #expect(Set(boston.barberIds) == Set(["1", "2"]))
        let pin = try #require(areas.first(where: \.isTemporaryPinBucket))
        #expect(pin.barberIds == ["3"])
    }

    private func makeRow(
        id: String,
        barberId: String,
        status: String,
        scheduled: String
    ) -> ConsumerBookingSimpleRow {
        ConsumerBookingSimpleRow(
            id: id,
            barberId: barberId,
            serviceType: nil,
            serviceName: "Cut",
            scheduledTime: scheduled,
            status: status,
            barberName: "Barber",
            barberAvatar: nil,
            location: nil,
            notes: nil,
            priceUsdCents: 2000,
            serviceFeeCents: nil,
            chargeAmountCents: nil,
            feeBurden: nil,
            paidAt: nil,
            completedAt: nil,
            tipRequestedAt: nil,
            tipDecidedAt: nil,
            tipAmountCents: nil,
            pendingRescheduleRequest: nil
        )
    }

    private func sampleProvider(
        id: String,
        label: String?,
        lat: Double?,
        lng: Double?
    ) -> ServiceProvider {
        ServiceProvider(
            id: id,
            userId: id,
            businessName: "P\(id)",
            bio: nil,
            instagramHandle: nil,
            profileImageUrl: nil,
            rating: nil,
            reviewCount: nil,
            completedBookings: nil,
            isAvailableNow: nil,
            priceRange: nil,
            category: .haircuts,
            specialty: "Barber",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            serviceLatitude: lat,
            serviceLongitude: lng,
            serviceLocationLabel: label,
            customerReviews: nil
        )
    }
}
