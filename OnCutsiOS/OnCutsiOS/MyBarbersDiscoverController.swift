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

        var byId = Dictionary(uniqueKeysWithValues: browseProviders.map { ($0.id, $0) })
        for seed in seeds where byId[seed.barberId] == nil {
            do {
                let provider = try await OnCutsBarberDetailAPI.fetchServiceProvider(
                    barberId: seed.barberId,
                    bearerToken: bearerToken
                )
                byId[provider.id] = provider
            } catch {
                continue
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

        scheduleReverseGeocodeFill(providers: Array(byId.values) + tiles.map(\.provider))
    }

    func discoverAreas(from providers: [ServiceProvider]) -> [DiscoverServiceArea] {
        MyBarbersDiscover.buildDiscoverServiceAreas(from: providers, labelOverrides: labelOverrides)
    }

    func applyLabelOverride(_ label: String, forBarberId id: String, bookingRows: [ConsumerBookingSimpleRow], browseProviders: [ServiceProvider]) {
        guard let coarsened = MyBarbersDiscover.coarsenPublicLocationLabel(label) else { return }
        if labelOverrides[id] == coarsened { return }
        labelOverrides[id] = coarsened
        // Rebuild sections with new labels without re-fetching.
        let seeds = MyBarbersDiscover.bookingSeeds(from: bookingRows)
        var byId = Dictionary(uniqueKeysWithValues: browseProviders.map { ($0.id, $0) })
        for tile in myBarbersTiles {
            byId[tile.provider.id] = tile.provider
        }
        let tiles = MyBarbersDiscover.buildMyBarbersTiles(
            seeds: seeds,
            providersById: byId,
            labelOverrides: labelOverrides
        )
        myBarbersTiles = tiles
        myBarbersSections = MyBarbersDiscover.groupMyBarbersSections(tiles: tiles)
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
                        // Lightweight section rebuild from existing tiles.
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
