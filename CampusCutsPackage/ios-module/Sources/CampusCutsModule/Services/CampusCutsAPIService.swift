//
//  CampusCutsAPIService.swift
//  CampusCutsModule
//
//  Internal networking layer for CampusCuts API calls.
//

import Foundation

/// Internal API service for CampusCuts backend communication
internal class CampusCutsAPIService {
    private let session: UserSessionProtocol
    private let baseURL: URL
    private let jsonDecoder: JSONDecoder
    private let authInterceptor: AuthInterceptor

    init(session: UserSessionProtocol, environment: CampusCutsEnvironment) {
        self.session = session
        self.baseURL = environment.apiBaseURL
        self.authInterceptor = AuthInterceptor(session: session)
        self.jsonDecoder = CampusCutsAPIDecoding.makeDecoder()
    }

    // MARK: - Generic Request Method

    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        isRetryAfterRefresh: Bool = false
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(endpoint)
        var urlRequest = authInterceptor.apply(to: url, method: method, body: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CampusCutsAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            return try CampusCutsAPIDecoding.decodePayload(T.self, from: data, decoder: jsonDecoder)
        case 401:
            guard !isRetryAfterRefresh else {
                throw CampusCutsAPIError.unauthorized
            }
            _ = try await session.refreshAccessToken()
            urlRequest = authInterceptor.apply(to: url, method: method, body: body)
            let (retryData, retryResponse) = try await URLSession.shared.data(for: urlRequest)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw CampusCutsAPIError.invalidResponse
            }
            switch retryHTTP.statusCode {
            case 200 ... 299:
                return try CampusCutsAPIDecoding.decodePayload(T.self, from: retryData, decoder: jsonDecoder)
            case 401:
                throw CampusCutsAPIError.unauthorized
            case 403:
                throw CampusCutsAPIError.forbidden
            case 404:
                throw CampusCutsAPIError.notFound
            default:
                throw CampusCutsAPIError.serverError(statusCode: retryHTTP.statusCode)
            }
        case 403:
            throw CampusCutsAPIError.forbidden
        case 404:
            throw CampusCutsAPIError.notFound
        default:
            throw CampusCutsAPIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Barber Endpoints

    func fetchBarbers(campusId: String? = nil) async throws -> [Barber] {
        var endpoint = "barbers"
        if let campusId = campusId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            let encoded = campusId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? campusId
            endpoint += "?campusId=\(encoded)"
        }
        let rows: [BarberListRowDTO] = try await request(endpoint: endpoint)
        return rows.map { $0.asBarber() }
    }

    func fetchBarberAvailability(barberId: String, date: String) async throws -> [AvailabilitySlotDTO] {
        let encoded = barberId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? barberId
        let endpoint = "barbers/\(encoded)/availability?date=\(date)"
        let payload: AvailabilityDayDTO = try await request(endpoint: endpoint)
        return payload.slots ?? []
    }

    func fetchBarberProfile(barberId: String) async throws -> BarberProfile {
        let encoded = barberId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? barberId
        let dto: BarberDetailDTO = try await request(endpoint: "barbers/\(encoded)")
        return dto.asProfile(fallbackBarberId: barberId)
    }

    // MARK: - Booking Endpoints

    func fetchBookings(status: String? = nil) async throws -> [Booking] {
        var endpoint = "bookings"
        if let status = status?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            let encoded = status.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? status
            endpoint += "?status=\(encoded)"
        }
        return try await request(endpoint: endpoint)
    }

    func createBooking(_ bookingRequest: CreateBookingRequest) async throws -> Booking {
        let body = try JSONEncoder().encode(bookingRequest)
        return try await request(endpoint: "bookings", method: "POST", body: body)
    }

    func updateBookingStatus(bookingId: String, status: String) async throws -> Booking {
        let payload = UpdateBookingStatusRequest(status: status)
        let body = try JSONEncoder().encode(payload)
        let encoded = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        return try await request(endpoint: "bookings/\(encoded)/status", method: "PATCH", body: body)
    }

    func cancelBooking(bookingId: String, reason: String?) async throws -> Booking {
        let payload = CancelBookingRequest(status: "CANCELLED", cancellationReason: reason)
        let body = try JSONEncoder().encode(payload)
        let encoded = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        return try await request(endpoint: "bookings/\(encoded)/cancel", method: "POST", body: body)
    }

    // MARK: - Messages Endpoints

    func fetchMessages(bookingId: String) async throws -> [Message] {
        let encoded = bookingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookingId
        return try await request(endpoint: "messages/booking/\(encoded)")
    }

    func sendMessage(bookingId: String, content: String) async throws -> Message {
        let payload = SendMessageRequest(bookingId: bookingId, content: content)
        let body = try JSONEncoder().encode(payload)
        return try await request(endpoint: "messages", method: "POST", body: body)
    }

    // MARK: - Campus Endpoints

    /// Uses path `campus` relative to `apiBaseURL` (e.g. `/api/v1/campus`).
    func fetchCampuses() async throws -> [Campus] {
        return try await request(endpoint: "campus")
    }

    // MARK: - Services Endpoints

    func fetchBarberServices(barberId: String) async throws -> [BarberService] {
        let profile = try await fetchBarberProfile(barberId: barberId)
        return profile.services ?? []
    }

    // MARK: - Review Endpoints

    func submitReview(bookingId: String, rating: Int, comment: String?) async throws -> Review {
        let payload = SubmitReviewRequest(bookingId: bookingId, rating: rating, comment: comment)
        let body = try JSONEncoder().encode(payload)
        return try await request(endpoint: "reviews", method: "POST", body: body)
    }

    func fetchBarberReviews(barberId: String) async throws -> [Review] {
        let profile = try await fetchBarberProfile(barberId: barberId)
        return profile.reviews ?? []
    }
}

// MARK: - API Errors

internal enum CampusCutsAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case serverError(statusCode: Int, message: String? = nil)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Session expired or unauthorized"
        case .forbidden:
            return "You don't have permission to access this resource"
        case .notFound:
            return "Resource not found"
        case .serverError(let statusCode, let message):
            if let message, !message.isEmpty {
                return statusCode > 0 ? "Server error (code: \(statusCode)): \(message)" : message
            }
            return "Server error (code: \(statusCode))"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

// MARK: - API Request Payloads

internal struct UpdateBookingStatusRequest: Encodable {
    let status: String
}

internal struct CancelBookingRequest: Encodable {
    let status: String
    let cancellationReason: String?

    enum CodingKeys: String, CodingKey {
        case status
        case cancellationReason = "cancellation_reason"
    }
}

internal struct SendMessageRequest: Encodable {
    let bookingId: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case bookingId = "booking_id"
        case content
    }
}

internal struct SubmitReviewRequest: Encodable {
    let bookingId: String
    let rating: Int
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case bookingId = "booking_id"
        case rating
        case comment
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
