//
//  MyBarbersDiscoverController.swift
//  OnCuts
//
//  Client-side My Barbers hydration + reverse-geocode label fill for Discover areas.
//

import Foundation
import Observation

@MainActor
@Observable
final class MyBarbersDiscoverController {
    private(set) var myBarbersSections: [MyBarbersSection] = []
    private(set) var myBarbersTiles: [MyBarbersTile] = []
    private(set) var isLoadingMyBarbers = false
    /// Barber id → coarsened public label from reverse geocode.
    private(set) var labelOverrides: [String: String] = [:]

    private var lastBookingSignature: String = ""
    private var geocodeTask: Task<Void, Never>?

    func resetForSignOut() {
        geocodeTask?.cancel()
        myBarbersSections = []
        myBarbersTiles = []
        labelOverrides = [:]
        lastBookingSignature = ""
        isLoadingMyBarbers = false
    }

    /// Rebuild My Barbers from bookings + browse cache; fetch missing operator details.
    func refreshMyBarbers(
        bookingRows: [ConsumerBookingSimpleRow],
        browseProviders: [ServiceProvider],
        bearerToken: String?
    ) async {
        let seeds = MyBarbersDiscover.bookingSeeds(from: bookingRows)
        let signature = seeds.map { "\($0.barberId):\($0.bookingCount)" }.joined(separator: "|")
        isLoadingMyBarbers = true
        defer { isLoadingMyBarbers = false }

        var byId = Self.indexProviders(browseProviders)
        let bookingByBarberId = Self.latestBookingRowByBarberId(bookingRows)

        for seed in seeds {
            if byId[Self.normalizedId(seed.barberId)] != nil { continue }
            // Prefer a full operator profile; fall back to booking stub so the tile still appears.
            if let provider = try? await OnCutsBarberDetailAPI.fetchServiceProvider(
                barberId: seed.barberId,
                bearerToken: bearerToken
            ) {
                byId[Self.normalizedId(provider.id)] = provider
                byId[Self.normalizedId(provider.userId)] = provider
            } else if let row = bookingByBarberId[Self.normalizedId(seed.barberId)] {
                let stub = Self.stubProvider(from: row, barberId: seed.barberId)
                byId[Self.normalizedId(stub.id)] = stub
            }
        }

        // If browse already had a thin row, prefer detail enrichment when available.
        for seed in seeds {
            let key = Self.normalizedId(seed.barberId)
            guard let existing = byId[key], existing.services == nil || existing.availability == nil else {
                continue
            }
            if let enriched = try? await OnCutsBarberDetailAPI.fetchServiceProvider(
                barberId: seed.barberId,
                bearerToken: bearerToken
            ) {
                byId[Self.normalizedId(enriched.id)] = enriched
                byId[Self.normalizedId(enriched.userId)] = enriched
            }
        }

        let tiles = MyBarbersDiscover.buildMyBarbersTiles(
            seeds: seeds,
            providersById: byId,
            labelOverrides: labelOverrides
        )
        myBarbersTiles = tiles
        myBarbersSections = MyBarbersDiscover.groupMyBarbersSections(tiles: tiles)
        lastBookingSignature = signature

        scheduleReverseGeocodeFill(providers: Array(Set(byId.values.map(\.id))).compactMap { id in
            byId[Self.normalizedId(id)]
        })
    }

    func discoverAreas(from providers: [ServiceProvider]) -> [DiscoverServiceArea] {
        MyBarbersDiscover.buildDiscoverServiceAreas(from: providers, labelOverrides: labelOverrides)
    }

    func applyLabelOverride(_ label: String, forBarberId id: String, bookingRows: [ConsumerBookingSimpleRow], browseProviders: [ServiceProvider]) {
        guard let coarsened = MyBarbersDiscover.coarsenPublicLocationLabel(label) else { return }
        if labelOverrides[id] == coarsened { return }
        labelOverrides[id] = coarsened
        let seeds = MyBarbersDiscover.bookingSeeds(from: bookingRows)
        var byId = Self.indexProviders(browseProviders)
        for tile in myBarbersTiles {
            byId[Self.normalizedId(tile.provider.id)] = tile.provider
            byId[Self.normalizedId(tile.provider.userId)] = tile.provider
        }
        let tiles = MyBarbersDiscover.buildMyBarbersTiles(
            seeds: seeds,
            providersById: byId,
            labelOverrides: labelOverrides
        )
        myBarbersTiles = tiles
        myBarbersSections = MyBarbersDiscover.groupMyBarbersSections(tiles: tiles)
    }

    private static func normalizedId(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func indexProviders(_ providers: [ServiceProvider]) -> [String: ServiceProvider] {
        var byId: [String: ServiceProvider] = [:]
        for provider in providers {
            byId[normalizedId(provider.id)] = provider
            let uid = normalizedId(provider.userId)
            if !uid.isEmpty {
                byId[uid] = provider
            }
        }
        return byId
    }

    private static func latestBookingRowByBarberId(_ rows: [ConsumerBookingSimpleRow]) -> [String: ConsumerBookingSimpleRow] {
        var map: [String: ConsumerBookingSimpleRow] = [:]
        for row in rows {
            guard let raw = row.barberId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                continue
            }
            let key = normalizedId(raw)
            if let existing = map[key],
               let existingDate = MyBarbersDiscover.parseISODate(existing.scheduledTime),
               let nextDate = MyBarbersDiscover.parseISODate(row.scheduledTime),
               existingDate >= nextDate {
                continue
            }
            map[key] = row
        }
        return map
    }

    /// Minimal operator card from bookings-simple when browse/detail hydration is unavailable.
    private static func stubProvider(from row: ConsumerBookingSimpleRow, barberId: String) -> ServiceProvider {
        let name = row.barberName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyStub ?? "Operator"
        let priceDollars: Int? = {
            guard let cents = row.priceUsdCents, cents > 0 else { return nil }
            return max(1, Int((Double(cents) / 100.0).rounded()))
        }()
        let location = row.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyStub
        return ServiceProvider(
            id: barberId,
            userId: barberId,
            businessName: name,
            bio: nil,
            instagramHandle: nil,
            profileImageUrl: ProfileImageURLResolver.normalizedStorageString(from: row.barberAvatar),
            rating: nil,
            reviewCount: nil,
            completedBookings: nil,
            isAvailableNow: nil,
            priceRange: priceDollars.map { ServiceProvider.PriceRange(min: $0, max: $0) },
            category: .haircuts,
            specialty: "Operator",
            providerType: nil,
            services: priceDollars.map {
                [
                    ServiceProvider.Service(
                        id: "booking-svc",
                        name: row.serviceName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyStub
                            ?? row.serviceType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyStub
                            ?? "Service",
                        price: $0,
                        duration: nil,
                        description: nil
                    ),
                ]
            },
            availability: nil,
            locations: location.map { [$0] },
            distanceMilesFromUser: nil,
            serviceLatitude: nil,
            serviceLongitude: nil,
            serviceLocationLabel: location,
            customerReviews: nil
        )
    }

    private func scheduleReverseGeocodeFill(providers: [ServiceProvider]) {
        geocodeTask?.cancel()
        let needing = providers.filter { provider in
            guard provider.hasFiniteServiceCoordinate else { return false }
            if labelOverrides[provider.id] != nil { return false }
            return MyBarbersDiscover.publicBroadLocationLabel(for: provider) == nil
        }
        guard !needing.isEmpty else { return }

        geocodeTask = Task { [weak self] in
            for provider in needing {
                if Task.isCancelled { return }
                guard let lat = provider.serviceLatitude, let lng = provider.serviceLongitude else { continue }
                if let label = await ConsumerPublicGeocode.reverseCoarseLabel(latitude: lat, longitude: lng) {
                    await MainActor.run {
                        guard let self else { return }
                        self.labelOverrides[provider.id] = label
                        let updated = self.myBarbersTiles.map { tile -> MyBarbersTile in
                            if tile.provider.id == provider.id {
                                return MyBarbersTile(
                                    provider: tile.provider,
                                    bookingCount: tile.bookingCount,
                                    latestScheduledTime: tile.latestScheduledTime,
                                    isMain: tile.isMain,
                                    publicLocationLabel: label
                                )
                            }
                            let overridden = self.labelOverrides[tile.provider.id]
                            return MyBarbersTile(
                                provider: tile.provider,
                                bookingCount: tile.bookingCount,
                                latestScheduledTime: tile.latestScheduledTime,
                                isMain: tile.isMain,
                                publicLocationLabel: MyBarbersDiscover.coarsenPublicLocationLabel(overridden)
                                    ?? tile.publicLocationLabel
                                    ?? MyBarbersDiscover.publicBroadLocationLabel(for: tile.provider)
                            )
                        }
                        self.myBarbersTiles = updated
                        self.myBarbersSections = MyBarbersDiscover.groupMyBarbersSections(tiles: updated)
                    }
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }
}

private extension String {
    var nilIfEmptyStub: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
