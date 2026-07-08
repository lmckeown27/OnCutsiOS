//
//  ProviderViewModel.swift
//  Intera
//
//  Loads providers: OnCuts `GET /api/v1/barbers` first, then legacy `/providers/list`.
//

import OnCutsModule
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
    case onCutsBarbers
    case legacyProvidersList
}

@Observable
@MainActor
final class ProviderViewModel {
    private(set) var state: ProviderLoadingState = .idle

    /// Last good payload so a failed refresh doesn’t wipe the list.
    private(set) var lastSuccessfulProviders: [ServiceProvider] = []

    /// Glass toolbar: cycles through `ServiceType` (OnCuts package); filters the barber list in the shell.
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

    /// Tries OnCutsModule `fetchBrowseProviders`, then raw `GET …/barbers`, then legacy `/providers/list`.
    func loadProviders(bearerToken: String?) async {
        state = .loading

        #if os(iOS)
        let coord: CLLocationCoordinate2D?
        if ConsumerBrowseDistancePreference.constrainBrowseListByDistance {
            coord = await ConsumerLocationFetcher.shared.coordinateForNearbyProviders()
        } else {
            coord = nil
        }
        #else
        let coord: CLLocationCoordinate2D? = nil
        #endif

        var lastError: Error?

        if let client = OnCutsIntegration.makeClientIfAvailable() {
            do {
                let rows = try await client.fetchBrowseProviders(
                    campusId: AppConfiguration.onCutsDefaultCampusId,
                    latitude: coord?.latitude,
                    longitude: coord?.longitude,
                    maxDistanceKm: coord != nil ? ConsumerBrowseDistancePreference.maxDistanceKmForLocationQuery() : nil
                )
                let providers = rows.map { $0.asServiceProvider() }
                #if DEBUG
                print("✅ Providers: \(providers.count) via OnCutsModule fetchBrowseProviders")
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
                print("⏭️ OnCutsModule browse fetch failed, falling back to shell HTTP: \(error.localizedDescription)")
                #endif
            }
        }

        #if os(iOS)
        let barbersURL = AppConfiguration.urlOnCutsBarbers(
            latitude: coord?.latitude,
            longitude: coord?.longitude,
            maxDistanceKm: coord != nil ? ConsumerBrowseDistancePreference.maxDistanceKmForLocationQuery() : nil
        )
        #else
        let barbersURL = AppConfiguration.urlOnCutsBarbers
        #endif

        let candidates: [(url: URL, source: ProviderFetchSource, label: String)] = [
            (barbersURL, .onCutsBarbers, "OnCuts /barbers"),
            (AppConfiguration.urlProvidersList, .legacyProvidersList, "legacy /providers/list")
        ]

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

                try HTTPJSONBodyValidation.validateJSONObjectData(data, httpResponse: response)

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
        case .onCutsBarbers:
            if let campus = try? OnCutsBarbersDecoder.decodeServiceProviders(from: data) {
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
