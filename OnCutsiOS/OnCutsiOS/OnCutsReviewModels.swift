//
//  OnCutsReviewModels.swift
//  OnCuts
//
//  Decodes OnCuts `Review` payloads (barber list embed + GET /barbers/:id/reviews).
//

import Foundation

// MARK: - API row (snake_case via JSONDecoder.convertFromSnakeCase)

struct OnCutsReviewDTO: Decodable, Sendable {
    let id: String?
    /// Parsed from `rating` and/or `reviewRating` / `review_rating` (bookings-backed rows use `rating`).
    let rating: Int?
    let reviewText: String?
    let createdAt: String?
    let firstName: String?
    let lastName: String?
    /// From `GET /reviews/barber/:id` (`client_first_name` / `client_last_name` with snake_case decoding).
    let clientFirstName: String?
    let clientLastName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case rating
        case reviewRating
        case stars
        case reviewText
        case createdAt
        case firstName
        case lastName
        case clientFirstName
        case clientLastName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Booking ids are often numeric in JSON; `String`‑only decode would throw and drop the whole row.
        id = Self.decodeFlexibleId(from: c)
        reviewText = try c.decodeIfPresent(String.self, forKey: .reviewText)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        clientFirstName = try c.decodeIfPresent(String.self, forKey: .clientFirstName)
        clientLastName = try c.decodeIfPresent(String.self, forKey: .clientLastName)
        rating = Self.decodeStarCount(from: c)
    }

    private static func decodeFlexibleId(from c: KeyedDecodingContainer<CodingKeys>) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: .id) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        if let i = try? c.decodeIfPresent(Int.self, forKey: .id) { return String(i) }
        if let d = try? c.decodeIfPresent(Double.self, forKey: .id), d.isFinite, d == d.rounded() {
            return String(Int(d))
        }
        return nil
    }

    private static func decodeStarCount(from c: KeyedDecodingContainer<CodingKeys>) -> Int? {
        for key in [CodingKeys.rating, CodingKeys.reviewRating, CodingKeys.stars] {
            if let i = try? c.decodeIfPresent(Int.self, forKey: key) {
                return clampStar(i)
            }
            if let d = try? c.decodeIfPresent(Double.self, forKey: key), d.isFinite {
                return clampStar(Int(d.rounded()))
            }
            if let s = try? c.decodeIfPresent(String.self, forKey: key),
               let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return clampStar(i)
            }
        }
        return nil
    }

    /// Customer star input is **0…5** (0 = lowest / none shown as empty glyphs, 5 = all filled).
    private static func clampStar(_ i: Int) -> Int? {
        guard i >= 0, i <= 5 else { return nil }
        return i
    }
}

// MARK: - List envelope (matches web `PaginatedResponse<Review>`)

struct OnCutsBarberReviewsListResponse: Decodable, Sendable {
    let success: Bool?
    let data: [OnCutsReviewDTO]?
}

// MARK: - Map → UI model

extension OnCutsReviewDTO {
    func asProviderReview(index: Int, barberId: String) -> ProviderReview? {
        let trimmedComment = (reviewText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String? = trimmedComment.isEmpty ? nil : trimmedComment
        let first = (firstName ?? clientFirstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (lastName ?? clientLastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        let display = name.isEmpty ? "Anonymous" : name
        let rid = id.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(barberId)-rev-\(index)"
        let when = Self.displayRelativeDate(from: createdAt)
        return ProviderReview(
            id: rid,
            authorDisplayName: display,
            rating: rating,
            relativeDate: when.isEmpty ? "—" : when,
            comment: body
        )
    }

    private static func displayRelativeDate(from iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        if d == nil {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            d = df.date(from: String(iso.prefix(10)))
        }
        guard let date = d else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

extension Array where Element == OnCutsReviewDTO {
    func asProviderReviews(barberId: String) -> [ProviderReview] {
        enumerated().compactMap { $0.element.asProviderReview(index: $0.offset, barberId: barberId) }
    }
}
