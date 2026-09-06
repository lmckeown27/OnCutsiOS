//
//  ConsumerLocationFetcher.swift
//  OnCuts
//
//  One-shot device coordinate for `GET /barbers?lat=&lng=` (iOS). Best-effort; returns nil if denied or unavailable.
//

#if os(iOS)
import CoreLocation
import Foundation

/// Outcome of a nearby-providers location attempt.
enum ConsumerNearbyLocationResult: Sendable {
    case coordinate(CLLocationCoordinate2D)
    /// User denied or restricted Location Services for this app.
    case permissionDenied
    /// Authorized but no usable fix (timeout / hardware error).
    case unavailable
}

@MainActor
final class ConsumerLocationFetcher: NSObject, CLLocationManagerDelegate {
    static let shared = ConsumerLocationFetcher()

    private let manager: CLLocationManager
    private var authContinuation: CheckedContinuation<Bool, Never>?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var locationRoundComplete = false
    private var inflightFetch: Task<ConsumerNearbyLocationResult, Never>?

    /// Avoid toast spam when browse reloads repeatedly after a denial.
    private var lastPermissionDeniedNoticeAt: Date?
    private let permissionDeniedNoticeCooldown: TimeInterval = 90

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Current authorization without prompting.
    var isLocationPermissionDenied: Bool {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    /// Synchronous last-known fix when fresh enough — used to seed Discover before async resolve.
    var cachedCoordinateIfAvailable: CLLocationCoordinate2D? {
        guard let cached = manager.location,
              cached.horizontalAccuracy >= 0,
              cached.timestamp.timeIntervalSinceNow > -180,
              CLLocationCoordinate2DIsValid(cached.coordinate)
        else { return nil }
        return cached.coordinate
    }

    /// Serialized so concurrent `loadProviders` calls share one fix and don’t corrupt continuations.
    func resolveForNearbyProviders(timeoutSeconds: TimeInterval = 12) async -> ConsumerNearbyLocationResult {
        if let inflightFetch {
            return await inflightFetch.value
        }
        let task = Task<ConsumerNearbyLocationResult, Never> { @MainActor in
            await self.performResolve(timeoutSeconds: timeoutSeconds)
        }
        inflightFetch = task
        let value = await task.value
        inflightFetch = nil
        return value
    }

    /// Convenience for callers that only need a coordinate.
    func coordinateForNearbyProviders(timeoutSeconds: TimeInterval = 12) async -> CLLocationCoordinate2D? {
        if case let .coordinate(coord) = await resolveForNearbyProviders(timeoutSeconds: timeoutSeconds) {
            return coord
        }
        return nil
    }

    /// Informational toast: nearby browse works best with location. Coalesced so reloads don’t spam.
    func presentPermissionDeniedGuidanceIfNeeded(force: Bool = false) {
        let now = Date()
        if !force,
           let last = lastPermissionDeniedNoticeAt,
           now.timeIntervalSince(last) < permissionDeniedNoticeCooldown {
            return
        }
        lastPermissionDeniedNoticeAt = now
        AlertManager.shared.present(
            "\(AppBranding.displayName) works best when it can find the closest service providers to your location. Enable Location for \(AppBranding.displayName) in Settings to use nearby search.",
            duration: .seconds(6)
        )
    }

    private func performResolve(timeoutSeconds: TimeInterval) async -> ConsumerNearbyLocationResult {
        let authorized = await ensureAuthorized()
        guard authorized else { return .permissionDenied }
        // Prefer a fresh enough cached fix so cold launch does not sit in `.loading` for the full timeout.
        if let cached = manager.location,
           cached.horizontalAccuracy >= 0,
           cached.timestamp.timeIntervalSinceNow > -180,
           CLLocationCoordinate2DIsValid(cached.coordinate) {
            return .coordinate(cached.coordinate)
        }
        if let coord = await waitForFirstFix(timeoutSeconds: timeoutSeconds) {
            return .coordinate(coord)
        }
        return .unavailable
    }

    private func ensureAuthorized() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                authContinuation = cont
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return false
        }
    }

    private func waitForFirstFix(timeoutSeconds: TimeInterval) async -> CLLocationCoordinate2D? {
        locationRoundComplete = false
        return await withCheckedContinuation { cont in
            locationContinuation = cont
            manager.startUpdatingLocation()
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                finishLocationRound(nil)
            }
        }
    }

    private func finishLocationRound(_ coord: CLLocationCoordinate2D?) {
        guard !locationRoundComplete else { return }
        locationRoundComplete = true
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()
        if let cont = locationContinuation {
            locationContinuation = nil
            cont.resume(returning: coord)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if let cont = authContinuation {
            authContinuation = nil
            let ok = manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
            cont.resume(returning: ok)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        let coord = loc.coordinate
        guard CLLocationCoordinate2DIsValid(coord) else { return }
        finishLocationRound(coord)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishLocationRound(nil)
    }
}
#endif
