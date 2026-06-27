//
//  CampusCutsClient+ShellProfile.swift
//  CampusCutsModule
//
//  Public profile/booking APIs for host apps (Intera profile, appointments, barber portfolio).
//

import Foundation

// MARK: - Public DTOs

/// One booking row for profile “Upcoming” / “History” lists (`GET /bookings`).
public struct CampusCutsProfileBooking: Sendable, Identifiable, Hashable {
    public let id: String
    public let serviceName: String
    public let providerName: String
    public let scheduledAt: Date
    public let statusRaw: String

    public init(id: String, serviceName: String, providerName: String, scheduledAt: Date, statusRaw: String) {
        self.id = id
        self.serviceName = serviceName
        self.providerName = providerName
        self.scheduledAt = scheduledAt
        self.statusRaw = statusRaw
    }
}

/// Review line for barber profile (`GET /barbers/:id/reviews`).
public struct CampusCutsBarberReviewSnippet: Sendable, Identifiable, Hashable {
    public let id: String
    public let authorName: String
    public let rating: Int
    public let body: String
    public let createdAt: Date

    public init(id: String, authorName: String, rating: Int, body: String, createdAt: Date) {
        self.id = id
        self.authorName = authorName
        self.rating = rating
        self.body = body
        self.createdAt = createdAt
    }
}

// MARK: - CampusCutsClient

extension CampusCutsClient {

    /// All bookings for the authenticated user (consumer or barber, per backend scope).
    public func fetchMyBookings() async throws -> [CampusCutsProfileBooking] {
        let api = CampusCutsAPIService(session: session, environment: environment)
        let rows = try await api.fetchBookings()
        return rows.compactMap { Self.mapBookingToProfile($0) }
    }

    /// Best-effort barber row `id` for the signed-in barber (from any booking they own).
    public func inferCurrentBarberId() async throws -> String? {
        let api = CampusCutsAPIService(session: session, environment: environment)
        let statuses = ["PENDING", "ACCEPTED", "COMPLETED", "REJECTED", "CANCELLED"]
        for st in statuses {
            let rows = try await api.fetchBookings(status: st)
            if let id = rows.first?.barberId.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                return id
            }
        }
        let all = try await api.fetchBookings()
        return all.first?.barberId.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// Portfolio image URLs from `GET /barbers/:id` (`portfolioImages` keys/paths via HTTPS/S3).
    public func fetchBarberPortfolioURLs(barberId: String) async throws -> [URL] {
        let trimmedId = barberId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return [] }
        let api = CampusCutsAPIService(session: session, environment: environment)
        let profile = try await api.fetchBarberProfile(barberId: trimmedId)
        let paths = profile.portfolioImages ?? []
        return paths.compactMap { CampusCutsS3ImageURL.url(forStoredPath: $0) }
    }

    /// Public bio from barber profile (optional).
    public func fetchBarberBio(barberId: String) async throws -> String? {
        let trimmedId = barberId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return nil }
        let api = CampusCutsAPIService(session: session, environment: environment)
        let profile = try await api.fetchBarberProfile(barberId: trimmedId)
        let b = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (b?.isEmpty == false) ? b : nil
    }

    /// Reviews for the barber’s public profile.
    public func fetchBarberReviewSnippets(barberId: String) async throws -> [CampusCutsBarberReviewSnippet] {
        let trimmedId = barberId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return [] }
        let api = CampusCutsAPIService(session: session, environment: environment)
        let rows = try await api.fetchBarberReviews(barberId: trimmedId)
        return rows.map { Self.mapReview($0) }
    }

    // MARK: - Mappers

    private static func mapBookingToProfile(_ b: Booking) -> CampusCutsProfileBooking? {
        guard let at = scheduledDate(bookingDate: b.bookingDate, startTime: b.startTime) else { return nil }
        let service = trimmedNonEmpty(b.serviceName) ?? "Service"
        let provider = trimmedNonEmpty(b.barberBusinessName) ?? trimmedNonEmpty(b.barberName) ?? "Provider"
        return CampusCutsProfileBooking(
            id: b.id,
            serviceName: service,
            providerName: provider,
            scheduledAt: at,
            statusRaw: b.status.rawValue
        )
    }

    private static func mapReview(_ r: Review) -> CampusCutsBarberReviewSnippet {
        let author = trimmedNonEmpty(r.consumerName) ?? "Customer"
        let body = trimmedNonEmpty(r.comment) ?? ""
        let created = parseISO8601(r.createdAt) ?? Date.distantPast
        return CampusCutsBarberReviewSnippet(
            id: r.id,
            authorName: author,
            rating: r.rating,
            body: body,
            createdAt: created
        )
    }

    private static func scheduledDate(bookingDate: String, startTime: String) -> Date? {
        let combined = "\(bookingDate)T\(startTime)"
        return parseISO8601(combined) ?? parseISO8601("\(combined):00")
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let flexible = ISO8601DateFormatter()
        flexible.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = flexible.date(from: trimmed) { return date }
        flexible.formatOptions = [.withInternetDateTime]
        if let date = flexible.date(from: trimmed) { return date }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: trimmed)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
