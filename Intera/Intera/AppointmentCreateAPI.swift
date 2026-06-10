//
//  AppointmentCreateAPI.swift
//  Intera
//
//  Consumer booking submission: POST `AppConfiguration.urlBookingsSimpleCreate` (`POST /api/v1/bookings-simple`).
//

import Foundation

enum AppointmentCreateError: LocalizedError {
    case unauthorized
    case invalidResponse
    case rejected(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .invalidResponse:
            return "Could not reach the booking server."
        case .rejected(let status, let message):
            if let message, !message.isEmpty { return message }
            return "Booking failed (HTTP \(status))."
        }
    }
}

enum AppointmentCreateAPI {
    static func isUnauthorizedError(_ error: Error) -> Bool {
        if case AppointmentCreateError.unauthorized = error { return true }
        return false
    }

    /// Creates a pending booking for the signed-in consumer.
    static func createAppointment(booking: BookingState, bearerToken: String?) async throws {
        var request = URLRequest(url: AppConfiguration.urlBookingsSimpleCreate)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = bearerToken, !t.isEmpty {
            request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }

        let body = CreateAppointmentRequestBody(from: booking)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        request.httpBody = try encoder.encode(body)

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await URLSession.shared.data(for: request)
            guard let h = response as? HTTPURLResponse else {
                throw AppointmentCreateError.invalidResponse
            }
            data = d
            http = h
        } catch let err as AppointmentCreateError {
            throw err
        } catch {
            ProductionLogging.recordNonFatal(error, context: ["area": "appointment_create"])
            throw error
        }

        if http.statusCode == 401 {
            throw AppointmentCreateError.unauthorized
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let msg = serverMessage(from: data)
            ProductionLogging.recordNonFatal(
                NSError(domain: "AppointmentCreate", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg ?? "HTTP \(http.statusCode)"]),
                context: ["area": "appointment_create"]
            )
            throw AppointmentCreateError.rejected(status: http.statusCode, message: msg)
        }
    }

    private static func serverMessage(from data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = obj["error"] as? String {
                return s.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            if let block = obj["error"] as? [String: Any],
               let msg = block["message"] as? String {
                return msg.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

// MARK: - Request body (matches `POST /api/v1/bookings-simple` in `booking-simple.routes.ts`)

private struct CreateAppointmentRequestBody: Encodable {
    let barberId: String
    let serviceType: String
    let priceUsdCents: Int
    let scheduledTime: String
    let location: String?
    let notes: String?

    init(from booking: BookingState) {
        barberId = booking.barberId
        serviceType = booking.serviceName
        let dollars = booking.finalServicePriceUsd
        priceUsdCents = max(0, dollars) * 100
        scheduledTime = booking.scheduledAtPacificISO
        let loc = booking.location.trimmingCharacters(in: .whitespacesAndNewlines)
        location = loc.isEmpty ? nil : loc
        notes = nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
