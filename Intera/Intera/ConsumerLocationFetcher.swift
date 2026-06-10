//
//  ConsumerLocationFetcher.swift
//  Intera
//
//  One-shot device coordinate for `GET /barbers?lat=&lng=` (iOS). Best-effort; returns nil if denied or unavailable.
//

#if os(iOS)
import CoreLocation
import Foundation

@MainActor
final class ConsumerLocationFetcher: NSObject, CLLocationManagerDelegate {
    static let shared = ConsumerLocationFetcher()

    private let manager: CLLocationManager
    private var authContinuation: CheckedContinuation<Bool, Never>?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var locationRoundComplete = false
    private var inflightFetch: Task<CLLocationCoordinate2D?, Never>?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Serialized so concurrent `loadProviders` calls share one fix and don’t corrupt continuations.
    func coordinateForNearbyProviders(timeoutSeconds: TimeInterval = 12) async -> CLLocationCoordinate2D? {
        if let inflightFetch {
            return await inflightFetch.value
        }
        let task = Task<CLLocationCoordinate2D?, Never> { @MainActor in
            await self.performFetch(timeoutSeconds: timeoutSeconds)
        }
        inflightFetch = task
        let value = await task.value
        inflightFetch = nil
        return value
    }

    private func performFetch(timeoutSeconds: TimeInterval) async -> CLLocationCoordinate2D? {
        let authorized = await ensureAuthorized()
        guard authorized else { return nil }
        return await waitForFirstFix(timeoutSeconds: timeoutSeconds)
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
