//
//  ConsumerBrowseLocationController.swift
//  OnCuts
//
//  Browse center: device GPS (tracking On) vs manually entered place (tracking Off).
//

import Foundation
import Observation
#if os(iOS)
import CoreLocation
import MapKit
#endif

struct ConsumerBrowsePlaceSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    /// Present when already resolved (local search). Completer rows resolve on selection.
    let latitude: Double?
    let longitude: Double?

    var displayLabel: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return s.isEmpty ? "Selected place" : s }
        if s.isEmpty { return t }
        return "\(t), \(s)"
    }
}

@Observable
@MainActor
final class ConsumerBrowseLocationController {
    static let shared = ConsumerBrowseLocationController()

    /// Mirrors `ConsumerBrowseDistancePreference.deviceTrackingEnabled` for SwiftUI bindings.
    private(set) var deviceTrackingEnabled: Bool = ConsumerBrowseDistancePreference.deviceTrackingEnabled

    /// Read-only label when tracking is On; also used for empty-state copy.
    private(set) var locationLabel: String = "Location from device"

    /// Free-text query shown when tracking is Off.
    var placeQuery: String = ""

    private(set) var placeSuggestions: [ConsumerBrowsePlaceSuggestion] = []
    private(set) var isSearchingPlaces = false

    /// True while the manual place `TextField` is focused — hides utility pill + bottom hub (parity with search).
    private(set) var isPlaceFieldEditing = false
    /// Bumped to ask the location chrome to resign first-responder (list tap / scroll dismiss).
    private(set) var placeFieldResignGeneration = 0

    private var placeSearchTask: Task<Void, Never>?
#if os(iOS)
    private let geocoder = CLGeocoder()
    private let searchCompleter = MKLocalSearchCompleter()
    private var completerDelegate: PlaceSearchCompleterDelegate?
    private var pendingCompleterContinuation: CheckedContinuation<[MKLocalSearchCompletion], Never>?
    private var completerWaitGeneration = 0
    /// Completer rows keyed by suggestion id — resolved to coordinates on select.
    private var completionBySuggestionID: [String: MKLocalSearchCompletion] = [:]
#endif

    private init() {
#if os(iOS)
        let delegate = PlaceSearchCompleterDelegate()
        completerDelegate = delegate
        searchCompleter.delegate = delegate
        searchCompleter.resultTypes = [.address]
        // Wide region so “Miami” can surface FL, OH, OK, AZ, etc. — not only nearby hits.
        searchCompleter.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
            span: MKCoordinateSpan(latitudeDelta: 55, longitudeDelta: 70)
        )
        delegate.onUpdate = { [weak self] completions in
            self?.finishCompleterWait(completions)
        }
        delegate.onFail = { [weak self] in
            self?.finishCompleterWait([])
        }
#endif
        if let place = ConsumerBrowseDistancePreference.manualPlace {
            placeQuery = place.trimmedLabel
            if !deviceTrackingEnabled {
                locationLabel = place.trimmedLabel.isEmpty ? locationLabel : place.trimmedLabel
            }
        }
    }

    /// Coordinate for `GET /barbers` when distance limiting is on.
    func resolveBrowseCenter() async -> (latitude: Double, longitude: Double)? {
#if os(iOS)
        if deviceTrackingEnabled {
            switch await ConsumerLocationFetcher.shared.resolveForNearbyProviders() {
            case let .coordinate(coord):
                await refreshDeviceLabel(for: coord)
                return (coord.latitude, coord.longitude)
            case .permissionDenied:
                ConsumerLocationFetcher.shared.presentPermissionDeniedGuidanceIfNeeded()
                if let place = ConsumerBrowseDistancePreference.manualPlace {
                    locationLabel = place.trimmedLabel.isEmpty ? "Location from device" : place.trimmedLabel
                    return (place.latitude, place.longitude)
                }
                locationLabel = "Enter a city or town"
                return nil
            case .unavailable:
                if let place = ConsumerBrowseDistancePreference.manualPlace {
                    locationLabel = place.trimmedLabel.isEmpty ? "Location from device" : place.trimmedLabel
                    return (place.latitude, place.longitude)
                }
                locationLabel = "Location from device"
                return nil
            }
        }
#endif
        if let place = ConsumerBrowseDistancePreference.manualPlace {
            locationLabel = place.trimmedLabel.isEmpty ? locationLabel : place.trimmedLabel
            return (place.latitude, place.longitude)
        }
        locationLabel = placeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Enter a city or town"
            : placeQuery
        return nil
    }

    /// Call when Home appears so Off mode restores the saved place label.
    /// Device-tracking label refresh happens inside ``resolveBrowseCenter`` during `loadProviders`
    /// (avoid a parallel resolve that can race the first browse fetch).
    func prepareForBrowseAppearance() {
        guard !deviceTrackingEnabled else { return }
        if let place = ConsumerBrowseDistancePreference.manualPlace {
            locationLabel = place.trimmedLabel
            if placeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                placeQuery = place.trimmedLabel
            }
        }
    }

    func setDeviceTracking(_ enabled: Bool) {
        guard deviceTrackingEnabled != enabled else { return }
        deviceTrackingEnabled = enabled
        ConsumerBrowseDistancePreference.deviceTrackingEnabled = enabled
        if enabled {
            if !ConsumerBrowseDistancePreference.constrainBrowseListByDistance {
                ConsumerBrowseDistancePreference.constrainBrowseListByDistance = true
            }
            placeSuggestions = []
            placeSearchTask?.cancel()
            setPlaceFieldEditing(false)
            placeFieldResignGeneration &+= 1
#if os(iOS)
            completionBySuggestionID.removeAll()
#endif
            Task { _ = await resolveBrowseCenter() }
        } else {
            if let place = ConsumerBrowseDistancePreference.manualPlace {
                placeQuery = place.trimmedLabel
                locationLabel = place.trimmedLabel
            } else {
                locationLabel = "Enter a city or town"
            }
        }
    }

    func setPlaceFieldEditing(_ editing: Bool) {
        guard isPlaceFieldEditing != editing else { return }
        isPlaceFieldEditing = editing
    }

    /// Resign the manual place field (keyboard + chrome) — used when the list is tapped/scrolled.
    func resignPlaceFieldFocus() {
        setPlaceFieldEditing(false)
        placeFieldResignGeneration &+= 1
    }

    func updatePlaceQuery(_ query: String) {
        let previous = placeQuery
        guard !deviceTrackingEnabled else {
            placeQuery = query
            placeSuggestions = []
            return
        }
        // Committed place acts like a token: one backspace (or any shorten) clears the whole location.
        if matchesCommittedManualPlace(previous), query.count < previous.count {
            clearManualPlace()
            return
        }
        placeQuery = query
        if matchesCommittedManualPlace(query) {
            placeSearchTask?.cancel()
            placeSuggestions = []
            isSearchingPlaces = false
#if os(iOS)
            completionBySuggestionID.removeAll()
#endif
            return
        }
        schedulePlaceSearch(query: query)
    }

    /// Clears the saved manual browse place and the text field.
    func clearManualPlace() {
        placeSearchTask?.cancel()
        placeSuggestions = []
        isSearchingPlaces = false
        placeQuery = ""
        locationLabel = "Enter a city or town"
#if os(iOS)
        completionBySuggestionID.removeAll()
#endif
        if ConsumerBrowseDistancePreference.manualPlace != nil {
            ConsumerBrowseDistancePreference.manualPlace = nil
        }
    }

    /// Dropdown only while actively searching for a place different from the saved manual location.
    var shouldShowPlaceSuggestions: Bool {
        guard !deviceTrackingEnabled, !placeSuggestions.isEmpty else { return false }
        return !matchesCommittedManualPlace(placeQuery)
    }

    func selectPlace(_ suggestion: ConsumerBrowsePlaceSuggestion) async {
#if os(iOS)
        if let lat = suggestion.latitude, let lng = suggestion.longitude,
           CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
            commitManualPlace(label: suggestion.displayLabel, latitude: lat, longitude: lng)
            return
        }
        if let completion = completionBySuggestionID[suggestion.id] {
            do {
                let request = MKLocalSearch.Request(completion: completion)
                let response = try await MKLocalSearch(request: request).start()
                if let item = response.mapItems.first {
                    let coord = item.placemark.coordinate
                    guard CLLocationCoordinate2DIsValid(coord) else { return }
                    let label = Self.displayLabel(for: item, fallbackTitle: suggestion.title, fallbackSubtitle: suggestion.subtitle)
                    commitManualPlace(label: label, latitude: coord.latitude, longitude: coord.longitude)
                    return
                }
            } catch {
                return
            }
        }
#else
        if let lat = suggestion.latitude, let lng = suggestion.longitude {
            commitManualPlace(label: suggestion.displayLabel, latitude: lat, longitude: lng)
        }
#endif
    }

    /// Keyboard Enter/Go: take the first search hit for the typed query (if any).
    func commitTypedPlaceIfPossible() async {
        guard !deviceTrackingEnabled else { return }
        let trimmed = placeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        if matchesCommittedManualPlace(trimmed) {
            placeSuggestions = []
            return
        }
        if let first = placeSuggestions.first {
            await selectPlace(first)
            return
        }
        await performPlaceSearch(query: trimmed)
        if let first = placeSuggestions.first {
            await selectPlace(first)
        }
    }

    // MARK: - Private

    private func commitManualPlace(label: String, latitude: Double, longitude: Double) {
        let place = ConsumerBrowsePlace(label: label, latitude: latitude, longitude: longitude)
        ConsumerBrowseDistancePreference.manualPlace = place
        if deviceTrackingEnabled {
            deviceTrackingEnabled = false
            ConsumerBrowseDistancePreference.deviceTrackingEnabled = false
        }
        if !ConsumerBrowseDistancePreference.constrainBrowseListByDistance {
            ConsumerBrowseDistancePreference.constrainBrowseListByDistance = true
        }
        placeQuery = label
        locationLabel = label
        placeSuggestions = []
        placeSearchTask?.cancel()
        isSearchingPlaces = false
        setPlaceFieldEditing(false)
        placeFieldResignGeneration &+= 1
#if os(iOS)
        completionBySuggestionID.removeAll()
#endif
    }

    private func matchesCommittedManualPlace(_ query: String) -> Bool {
        guard let place = ConsumerBrowseDistancePreference.manualPlace else { return false }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = place.trimmedLabel
        guard !q.isEmpty, !saved.isEmpty else { return false }
        return q.caseInsensitiveCompare(saved) == .orderedSame
    }

#if os(iOS)
    private func refreshDeviceLabel(for coord: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if Task.isCancelled { return }
            if let mark = placemarks.first {
                let city = (mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !city.isEmpty {
                    locationLabel = city
                    return
                }
            }
        } catch {
            // Fall through to saved place / default.
        }
        if let place = ConsumerBrowseDistancePreference.manualPlace, !place.trimmedLabel.isEmpty {
            locationLabel = place.trimmedLabel
        } else {
            locationLabel = "Location from device"
        }
    }

    private func schedulePlaceSearch(query: String) {
        placeSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            placeSuggestions = []
            isSearchingPlaces = false
            completionBySuggestionID.removeAll()
            return
        }
        isSearchingPlaces = true
        placeSearchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await performPlaceSearch(query: trimmed)
        }
    }

    private func performPlaceSearch(query: String) async {
        // Prefer completer — returns many same-name places (Miami FL / OH / OK…) with distinct subtitles.
        let completions = await waitForCompleterResults(query: query)
        guard !Task.isCancelled else { return }

        if !completions.isEmpty {
            var seen = Set<String>()
            var mapped: [ConsumerBrowsePlaceSuggestion] = []
            var byID: [String: MKLocalSearchCompletion] = [:]
            for (index, completion) in completions.prefix(15).enumerated() {
                let title = completion.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let subtitle = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let dedupeKey = "\(title.lowercased())|\(subtitle.lowercased())"
                guard seen.insert(dedupeKey).inserted else { continue }
                let id = "c-\(index)-\(dedupeKey)"
                mapped.append(
                    ConsumerBrowsePlaceSuggestion(
                        id: id,
                        title: title,
                        subtitle: subtitle,
                        latitude: nil,
                        longitude: nil
                    )
                )
                byID[id] = completion
            }
            completionBySuggestionID = byID
            placeSuggestions = mapped
            isSearchingPlaces = false
            return
        }

        // Fallback: full text search (still surface multiple map items when available).
        completionBySuggestionID.removeAll()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address]
        request.region = searchCompleter.region
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard !Task.isCancelled else { return }
            var seen = Set<String>()
            placeSuggestions = response.mapItems.prefix(15).compactMap { item in
                Self.suggestion(from: item).flatMap { suggestion in
                    let key = "\(suggestion.title.lowercased())|\(suggestion.subtitle.lowercased())"
                    guard seen.insert(key).inserted else { return nil }
                    return suggestion
                }
            }
        } catch {
            if !Task.isCancelled {
                placeSuggestions = []
            }
        }
        isSearchingPlaces = false
    }

    private func waitForCompleterResults(query: String) async -> [MKLocalSearchCompletion] {
        if let pending = pendingCompleterContinuation {
            pendingCompleterContinuation = nil
            pending.resume(returning: [])
        }
        completerWaitGeneration += 1
        let generation = completerWaitGeneration
        return await withCheckedContinuation { continuation in
            pendingCompleterContinuation = continuation
            // Clear first so identical re-queries still fire `completerDidUpdateResults`.
            searchCompleter.queryFragment = ""
            searchCompleter.queryFragment = query
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(2200))
                guard generation == self.completerWaitGeneration else { return }
                self.finishCompleterWait([])
            }
        }
    }

    private func finishCompleterWait(_ completions: [MKLocalSearchCompletion]) {
        guard let pending = pendingCompleterContinuation else { return }
        pendingCompleterContinuation = nil
        pending.resume(returning: completions)
    }

    private static func suggestion(from item: MKMapItem) -> ConsumerBrowsePlaceSuggestion? {
        let placemark = item.placemark
        let coord = placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coord) else { return nil }
        let title = primaryTitle(for: item)
        let subtitle = secondarySubtitle(for: placemark, excludingTitle: title)
        guard !title.isEmpty || !subtitle.isEmpty else { return nil }
        let resolvedTitle = title.isEmpty ? subtitle : title
        let resolvedSubtitle = title.isEmpty ? "" : subtitle
        return ConsumerBrowsePlaceSuggestion(
            id: "\(coord.latitude),\(coord.longitude)-\(resolvedTitle)-\(resolvedSubtitle)",
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
            latitude: coord.latitude,
            longitude: coord.longitude
        )
    }

    private static func displayLabel(for item: MKMapItem, fallbackTitle: String, fallbackSubtitle: String) -> String {
        if let suggestion = suggestion(from: item) {
            return suggestion.displayLabel
        }
        let t = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = fallbackSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return s.isEmpty ? "Selected place" : s }
        if s.isEmpty { return t }
        return "\(t), \(s)"
    }

    private static func primaryTitle(for item: MKMapItem) -> String {
        let placemark = item.placemark
        let candidates = [
            placemark.locality,
            item.name,
            placemark.name,
            placemark.subAdministrativeArea,
        ]
        for raw in candidates {
            let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return t }
        }
        return ""
    }

    /// County / state / country so “Miami” rows stay distinct.
    private static func secondarySubtitle(for placemark: MKPlacemark, excludingTitle title: String) -> String {
        var parts: [String] = []
        let titleLower = title.lowercased()
        if let county = placemark.subAdministrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines),
           !county.isEmpty,
           county.lowercased() != titleLower {
            parts.append(county)
        }
        if let state = placemark.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines),
           !state.isEmpty,
           state.lowercased() != titleLower {
            parts.append(state)
        }
        if let country = placemark.country?.trimmingCharacters(in: .whitespacesAndNewlines),
           !country.isEmpty,
           country.lowercased() != titleLower,
           country.caseInsensitiveCompare("United States") != .orderedSame {
            // Keep US implied for domestic rows; include country for international disambiguation.
            parts.append(country)
        } else if let country = placemark.country?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !country.isEmpty,
                  country.caseInsensitiveCompare("United States") == .orderedSame,
                  parts.isEmpty {
            parts.append(country)
        }
        // If locality differs from title (e.g. title is a neighborhood), include city.
        if let locality = placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines),
           !locality.isEmpty,
           locality.lowercased() != titleLower,
           !parts.contains(where: { $0.caseInsensitiveCompare(locality) == .orderedSame }) {
            parts.insert(locality, at: 0)
        }
        return parts.joined(separator: ", ")
    }
#else
    private func schedulePlaceSearch(query: String) {
        placeSuggestions = []
        isSearchingPlaces = false
    }

    private func performPlaceSearch(query: String) async {
        placeSuggestions = []
        isSearchingPlaces = false
    }
#endif
}

#if os(iOS)
/// Bridges `MKLocalSearchCompleter` callbacks into the browse location controller.
private final class PlaceSearchCompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    var onUpdate: (([MKLocalSearchCompletion]) -> Void)?
    var onFail: (() -> Void)?

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        onUpdate?(completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        onFail?()
    }
}
#endif
