//
//  ProviderViewModel.swift
//  Intera
//
//  Loads providers: AvilaPlatforms `GET /api/v1/barbers` first, then legacy `/providers/list`.
//

import AvilaPlatformsModule
import Foundation
import Observation
#if os(iOS)
import CoreLocation
#endif

enum ProviderLoadingState {
    case idle
    case loading
    case success([ServiceProvider])
    case failed(String)
}

private enum ProviderFetchSource {
    case avilaPlatformsBarbers
    case legacyProvidersList
}

@Observable
@MainActor
final class ProviderViewModel {
    private(set) var state: ProviderLoadingState = .idle

    /// Last good payload so a failed refresh doesn’t wipe the list.
    private(set) var lastSuccessfulProviders: [ServiceProvider] = []

    /// Glass toolbar: cycles through `ServiceType` (AvilaPlatforms package); filters the barber list in the shell.
    var selectedServiceType: ServiceType = .all

    var providersForDisplay: [ServiceProvider] {
        switch state {
        case .success(let list):
            return list
        case .failed, .loading, .idle:
            return lastSuccessfulProviders
        }
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    func providersFilteredByServiceType(_ providers: [ServiceProvider]) -> [ServiceProvider] {
        selectedServiceType.filteredProviders(from: providers)
    }

    /// Tries `GET …/barbers` (with device `lat`/`lng` on iOS when permitted), then legacy `/providers/list`.
    func loadProviders(bearerToken: String?) async {
        state = .loading

        #if os(iOS)
        let coord: CLLocationCoordinate2D?
        if ConsumerBrowseDistancePreference.constrainBrowseListByDistance {
            coord = await ConsumerLocationFetcher.shared.coordinateForNearbyProviders()
        } else {
            coord = nil
        }
        let barbersURL = AppConfiguration.urlAvilaPlatformsBarbers(
            latitude: coord?.latitude,
            longitude: coord?.longitude,
            maxDistanceKm: coord != nil ? ConsumerBrowseDistancePreference.maxDistanceKmForLocationQuery() : nil
        )
        #else
        let barbersURL = AppConfiguration.urlAvilaPlatformsBarbers
        #endif

        let candidates: [(url: URL, source: ProviderFetchSource, label: String)] = [
            (barbersURL, .avilaPlatformsBarbers, "AvilaPlatforms /barbers"),
            (AppConfiguration.urlProvidersList, .legacyProvidersList, "legacy /providers/list")
        ]

        var lastError: Error?

        for candidate in candidates {
            var request = URLRequest(url: candidate.url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token = bearerToken, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    #if DEBUG
                    let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
                    print("❌ \(candidate.label) HTTP \(http.statusCode) \(candidate.url.absoluteString) prefix: \(snippet)")
                    #endif
                    throw NSError(
                        domain: "ProviderAPI",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Server returned status \(http.statusCode)."]
                    )
                }

                let providers = try decodeProviders(data: data, source: candidate.source, url: candidate.url, label: candidate.label)

                #if DEBUG
                print("✅ Providers: \(providers.count) via \(candidate.label) — \(candidate.url.absoluteString)")
                if providers.isEmpty {
                    let snippet = String(data: data.prefix(400), encoding: .utf8) ?? ""
                    print("⚠️ Empty decoded list; body prefix: \(snippet)")
                }
                #endif

                lastSuccessfulProviders = providers
                state = .success(providers)
                prefetchProviderProfileImages(providers)
                return
            } catch {
                if InteraRefreshCancellation.isBenignCancellation(error) {
                    if !lastSuccessfulProviders.isEmpty {
                        state = .success(lastSuccessfulProviders)
                    } else {
                        state = .idle
                    }
                    return
                }
                lastError = error
                #if DEBUG
                print("⏭️ Skipping \(candidate.label): \(error.localizedDescription)")
                #endif
            }
        }

        let err = lastError ?? URLError(.cannotConnectToHost)
        if InteraRefreshCancellation.isBenignCancellation(err) {
            if !lastSuccessfulProviders.isEmpty {
                state = .success(lastSuccessfulProviders)
            } else {
                state = .idle
            }
            return
        }
        #if DEBUG
        print("❌ All provider sources failed: \(err.localizedDescription)")
        #endif
        AlertManager.shared.presentUserFriendlyMessage(for: err)
        ProductionLogging.recordNonFatal(err, context: ["area": "providers_list"])
        if lastSuccessfulProviders.isEmpty {
            state = .failed(err.localizedDescription)
        } else {
            state = .success(lastSuccessfulProviders)
        }
    }

    private func decodeProviders(data: Data, source: ProviderFetchSource, url: URL, label: String) throws -> [ServiceProvider] {
        switch source {
        case .avilaPlatformsBarbers:
            if let campus = try? AvilaPlatformsBarbersDecoder.decodeServiceProviders(from: data) {
                return campus
            }
            do {
                return try ProviderListDecoder.decodeItems(from: data)
            } catch {
                #if DEBUG
                let snippet = String(data: data.prefix(500), encoding: .utf8) ?? ""
                print("❌ \(label) decode failed: \(error.localizedDescription) — \(url.absoluteString) prefix: \(snippet)")
                #endif
                throw error
            }
        case .legacyProvidersList:
            do {
                return try ProviderListDecoder.decodeItems(from: data)
            } catch {
                #if DEBUG
                let snippet = String(data: data.prefix(500), encoding: .utf8) ?? ""
                print("❌ \(label) decode failed: \(error.localizedDescription) — \(url.absoluteString) prefix: \(snippet)")
                #endif
                throw error
            }
        }
    }

    /// Warms URL cache so browse-card `AsyncImage` views resolve avatars reliably after cold launch.
    private func prefetchProviderProfileImages(_ providers: [ServiceProvider]) {
        let urls = providers.compactMap { ProfileImageURLResolver.urlForAsyncImage(from: $0.profileImageUrl) }
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in urls {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }
}
