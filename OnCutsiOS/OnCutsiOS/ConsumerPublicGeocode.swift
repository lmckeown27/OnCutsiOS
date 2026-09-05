//
//  ConsumerPublicGeocode.swift
//  OnCuts
//
//  Coarse public reverse-geocode for Discover / My Barbers labels (city/campus only).
//  Prefers `GET /geocode/reverse` when available; falls back to CLGeocoder.
//

import CoreLocation
import Foundation

enum ConsumerPublicGeocode {
    struct CoarseLabel: Sendable, Hashable {
        let label: String
        let latitude: Double
        let longitude: Double
    }

    private struct ReversePayload: Decodable {
        let label: String?
        let city: String?
        let locality: String?
        let campus: String?
        let name: String?
    }

    private struct ReverseEnvelope: Decodable {
        let success: Bool?
        let data: ReversePayload?
        let label: String?
        let city: String?
    }

    /// Public reverse geocode → coarsened city/campus label (never street / never `"Other"`).
    static func reverseCoarseLabel(latitude: Double, longitude: Double) async -> String? {
        if let api = await reverseViaAPI(latitude: latitude, longitude: longitude) {
            return api
        }
        return await reverseViaApple(latitude: latitude, longitude: longitude)
    }

    private static func reverseViaAPI(latitude: Double, longitude: Double) async -> String? {
        guard var components = URLComponents(url: AppConfiguration.apiBaseURL.appendingPathComponent("geocode/reverse"), resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude)),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return nil
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let envelope = try? decoder.decode(ReverseEnvelope.self, from: data) {
                let candidates = [
                    envelope.data?.label,
                    envelope.data?.campus,
                    envelope.data?.city,
                    envelope.data?.locality,
                    envelope.data?.name,
                    envelope.label,
                    envelope.city,
                ]
                for raw in candidates {
                    if let label = MyBarbersDiscover.coarsenPublicLocationLabel(raw) {
                        return label
                    }
                }
            }
            if let payload = try? decoder.decode(ReversePayload.self, from: data) {
                for raw in [payload.label, payload.campus, payload.city, payload.locality, payload.name] {
                    if let label = MyBarbersDiscover.coarsenPublicLocationLabel(raw) {
                        return label
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func reverseViaApple(latitude: Double, longitude: Double) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let marks = try await geocoder.reverseGeocodeLocation(location)
            guard let mark = marks.first else { return nil }
            let candidates = [
                mark.areasOfInterest?.first,
                mark.locality,
                mark.subLocality,
                mark.subAdministrativeArea,
                mark.administrativeArea,
            ]
            for raw in candidates {
                if let label = MyBarbersDiscover.coarsenPublicLocationLabel(raw) {
                    return label
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}
