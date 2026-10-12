//
//  OperatorClientPortfolio.swift
//  OnCuts
//
//  Customer Client View: public portfolio preview + barber profile.
//  Owner upload/reorder routes are not used here.
//

import Foundation
import OnCutsModule

// MARK: - Catalog

nonisolated enum OperatorPortfolioCatalog {
    struct Entry: Hashable, Sendable {
        let name: String
        let slug: String
    }

    static func entries(forProviderType raw: String?) -> [Entry] {
        let type = ServiceType.fromProviderType(raw)
        let names: [String]
        switch type {
        case .barber:
            names = ProviderBrowseServiceCatalog.serviceNames(for: .barber)
        case .beauty:
            names = ProviderBrowseServiceCatalog.serviceNames(for: .beauty)
        case .all, .none:
            names = []
        }
        return names.map { Entry(name: $0, slug: slug($0)) }
    }

    static func slug(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var parts: [String] = []
        var current = ""
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                parts.append(current)
                current = ""
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts.joined(separator: "-")
    }
}

// MARK: - Models

struct OperatorPortfolioItem: Identifiable, Hashable, Sendable {
    let id: String
    let mediaType: String
    let mediaURL: URL?
    let thumbnailURL: URL?
    let caption: String?
    let sortOrder: Int
    let specialties: [String]
    let bookingId: String?
    let isCover: Bool
    let createdAt: Date?

    var isVideo: Bool {
        let raw = mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return raw == "video" || raw.hasPrefix("video/")
    }

    var isPhoto: Bool { !isVideo }

    var tileURL: URL? { thumbnailURL ?? mediaURL }
}

struct OperatorPortfolioOffer: Hashable, Sendable {
    let name: String
    let slug: String?
    let price: Decimal?
}

struct OperatorPortfolioSection: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let priceLabel: String?
    /// Cover first, then remaining items in stored `sort_order`.
    let items: [OperatorPortfolioItem]

    var hasWork: Bool { !items.isEmpty }
    var coverItem: OperatorPortfolioItem? { items.first }

    var titleLine: String {
        if let priceLabel, !priceLabel.isEmpty {
            return "\(name) \(priceLabel)"
        }
        return name
    }
}

struct OperatorPortfolioPreview: Sendable {
    let items: [OperatorPortfolioItem]
    let specialtyIds: [String]
}

enum OperatorPortfolioPreviewStatus: Sendable {
    /// Active operator. `specialtyIds` may be empty.
    case available(OperatorPortfolioPreview)
    /// Hidden or inactive — public preview is 404 and the gallery renders nothing.
    case hidden
}

// MARK: - Assembly

nonisolated enum OperatorClientPortfolioAssembly {
    static func sections(
        providerType: String?,
        offeredSpecialtyKeys: [String],
        offers: [OperatorPortfolioOffer],
        preview: OperatorPortfolioPreview
    ) -> [OperatorPortfolioSection] {
        let catalog = OperatorPortfolioCatalog.entries(forProviderType: providerType)
        let offerKeys = matchKeys(offeredSpecialtyKeys + offers.flatMap { [$0.name, $0.slug].compactMap { $0 } })
        let offeredCatalog = catalog.filter { entry in
            offerKeys.contains(OperatorPortfolioCatalog.slug(entry.name))
                || offerKeys.contains(entry.name.lowercased())
                || offerKeys.contains(entry.slug)
        }

        var sectionsByKey: [String: OperatorPortfolioSection] = [:]
        func addCatalog(_ entry: OperatorPortfolioCatalog.Entry) {
            sectionsByKey[entry.slug] = makeSection(
                id: entry.slug,
                name: entry.name,
                price: price(forName: entry.name, slug: entry.slug, offers: offers),
                items: items(in: preview.items, matching: [entry.slug, entry.name])
            )
        }
        for entry in offeredCatalog { addCatalog(entry) }

        let taggedCatalog = catalog.filter { entry in
            sectionsByKey[entry.slug] == nil
                && !items(in: preview.items, matching: [entry.slug, entry.name]).isEmpty
        }
        for entry in taggedCatalog { addCatalog(entry) }

        let catalogKeys = Set(catalog.map(\.slug))
        var extraKeys: [String] = []
        for item in preview.items {
            for tag in item.specialties {
                let key = canonicalKey(tag)
                guard !key.isEmpty, !catalogKeys.contains(key) else { continue }
                if !extraKeys.contains(key) { extraKeys.append(key) }
            }
        }
        for key in extraKeys {
            let tags = preview.items.flatMap(\.specialties).filter { canonicalKey($0) == key }
            let display = tags.first.map(displayName(for:)) ?? displayName(for: key)
            sectionsByKey[key] = makeSection(
                id: key,
                name: display,
                price: price(forName: display, slug: key, offers: offers),
                items: items(in: preview.items, matching: [key, display])
            )
        }

        let known = Set(sectionsByKey.keys)
        var ordered: [OperatorPortfolioSection] = []
        var used = Set<String>()
        for raw in preview.specialtyIds {
            let key = resolveSavedId(raw, known: known, catalog: catalog)
            guard let key, let section = sectionsByKey[key], used.insert(key).inserted else { continue }
            ordered.append(section)
        }
        for entry in offeredCatalog where used.insert(entry.slug).inserted {
            if let section = sectionsByKey[entry.slug] {
                ordered.append(section)
            }
        }
        for entry in taggedCatalog where used.insert(entry.slug).inserted {
            if let section = sectionsByKey[entry.slug] {
                ordered.append(section)
            }
        }
        for key in extraKeys where used.insert(key).inserted {
            if let section = sectionsByKey[key] {
                ordered.append(section)
            }
        }
        return ordered
    }

    static func section(matchingServiceName name: String, in sections: [OperatorPortfolioSection]) -> OperatorPortfolioSection? {
        let slug = OperatorPortfolioCatalog.slug(name)
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sections.first { section in
            section.id == slug
                || OperatorPortfolioCatalog.slug(section.name) == slug
                || section.name.lowercased() == lower
        }
    }

    static func priceLabel(_ value: Decimal?) -> String? {
        guard let value else { return nil }
        let number = NSDecimalNumber(decimal: value)
        let cents = number.multiplying(by: 100).rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        ))
        let centsInt = cents.intValue
        guard centsInt > 0 else { return nil }
        if centsInt % 100 == 0 {
            return "$\(centsInt / 100)"
        }
        return String(format: "$%.2f", number.doubleValue)
    }

    static func availabilityLines(from payload: OnCutsWeeklySchedulePayload?) -> [String] {
        let days = OnCutsWeeklyScheduleMapping.browseDays(from: payload)
        return days.map { day in
            let full = fullWeekdayName(day.dayOfWeek)
            return "\(full) \(day.timeSlots.joined(separator: ", "))"
        }
    }

    static func availabilityLines(from days: [ServiceProvider.DayAvailability]?) -> [String] {
        guard let days else { return [] }
        return days.filter(\.isAvailable).map { day in
            "\(fullWeekdayName(day.dayOfWeek)) \(day.timeSlots.joined(separator: ", "))"
        }
    }

    static func instagramURL(from handle: String?) -> URL? {
        guard var raw = handle?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("@") { raw.removeFirst() }
        raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let url = URL(string: raw), url.scheme != nil, let host = url.host?.lowercased(), host.contains("instagram") {
            let name = url.path.split(separator: "/").first.map(String.init) ?? ""
            guard !name.isEmpty else { return nil }
            return URL(string: "https://instagram.com/\(name)")
        }
        let user = raw.split(separator: "/").last.map(String.init) ?? raw
        let cleaned = user.hasPrefix("@") ? String(user.dropFirst()) : user
        guard !cleaned.isEmpty else { return nil }
        let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleaned
        return URL(string: "https://instagram.com/\(encoded)")
    }

    // MARK: Private

    private static func makeSection(
        id: String,
        name: String,
        price: Decimal?,
        items: [OperatorPortfolioItem]
    ) -> OperatorPortfolioSection {
        OperatorPortfolioSection(
            id: id,
            name: name,
            priceLabel: priceLabel(price),
            items: orderedForDisplay(items)
        )
    }

    private static func orderedForDisplay(_ items: [OperatorPortfolioItem]) -> [OperatorPortfolioItem] {
        let stored = items.sorted { $0.sortOrder < $1.sortOrder }
        guard let cover = coverPhoto(in: stored) else { return stored }
        return [cover] + stored.filter { $0.id != cover.id }
    }

    private static func coverPhoto(in items: [OperatorPortfolioItem]) -> OperatorPortfolioItem? {
        let photos = items.filter(\.isPhoto)
        if let marked = photos.first(where: \.isCover) { return marked }
        return photos.max { lhs, rhs in
            let leftDate = lhs.createdAt ?? .distantPast
            let rightDate = rhs.createdAt ?? .distantPast
            if leftDate != rightDate { return leftDate < rightDate }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private static func items(in all: [OperatorPortfolioItem], matching keys: [String]) -> [OperatorPortfolioItem] {
        let wanted = matchKeys(keys)
        guard !wanted.isEmpty else { return [] }
        return all.filter { item in
            item.specialties.contains { tag in
                let key = canonicalKey(tag)
                return wanted.contains(key) || wanted.contains(tag.lowercased())
            }
        }
    }

    private static func price(forName name: String, slug: String, offers: [OperatorPortfolioOffer]) -> Decimal? {
        let nameKey = name.lowercased()
        let slugKey = OperatorPortfolioCatalog.slug(slug)
        return offers.first { offer in
            offer.name.lowercased() == nameKey
                || OperatorPortfolioCatalog.slug(offer.name) == slugKey
                || offer.slug.map(OperatorPortfolioCatalog.slug) == slugKey
        }?.price
    }

    private static func resolveSavedId(_ raw: String, known: Set<String>, catalog: [OperatorPortfolioCatalog.Entry]) -> String? {
        let key = canonicalKey(raw)
        if known.contains(key) { return key }
        if known.contains(raw) { return raw }
        if let entry = catalog.first(where: { $0.slug == key || $0.name.lowercased() == raw.lowercased() }),
           known.contains(entry.slug) {
            return entry.slug
        }
        return nil
    }

    private static func canonicalKey(_ raw: String) -> String {
        let slug = OperatorPortfolioCatalog.slug(raw)
        return slug.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : slug
    }

    private static func matchKeys(_ values: [String]) -> Set<String> {
        Set(values.flatMap { value -> [String] in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return [trimmed.lowercased(), OperatorPortfolioCatalog.slug(trimmed)]
        })
    }

    private static func displayName(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(" ") { return trimmed }
        let words = trimmed
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
        return words.map { word in
            guard let first = word.first else { return String(word) }
            return first.uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    private static func fullWeekdayName(_ abbrev: String) -> String {
        switch abbrev.lowercased() {
        case "mon", "monday": return "Monday"
        case "tue", "tues", "tuesday": return "Tuesday"
        case "wed", "wednesday": return "Wednesday"
        case "thu", "thur", "thurs", "thursday": return "Thursday"
        case "fri", "friday": return "Friday"
        case "sat", "saturday": return "Saturday"
        case "sun", "sunday": return "Sunday"
        default: return abbrev
        }
    }
}

// MARK: - API

enum OperatorPortfolioPreviewAPI {
    static func fetch(barberId: String) async throws -> OperatorPortfolioPreviewStatus {
        let trimmed = barberId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = AppConfiguration.urlOperatorPortfolioPreview(barberId: trimmed) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return .hidden }
        guard (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(PreviewEnvelope.self, from: data)
        let payload = envelope.data
        let items = (payload?.items ?? []).map { $0.asItem() }.sorted { $0.sortOrder < $1.sortOrder }
        let specialtyIds = (payload?.specialtyIds ?? []).map(\.value).filter { !$0.isEmpty }
        return .available(OperatorPortfolioPreview(items: items, specialtyIds: specialtyIds))
    }

    /// Public barber profile fields Client View needs beyond the browse card.
    static func fetchProfile(barberId: String) async throws -> OperatorPortfolioProfile {
        let provider = try await OnCutsBarberDetailAPI.fetchServiceProvider(barberId: barberId, bearerToken: nil)
        return OperatorPortfolioProfile(
            provider: provider,
            offers: (provider.services ?? []).map { service in
                OperatorPortfolioOffer(
                    name: service.name,
                    slug: OperatorPortfolioCatalog.slug(service.name),
                    price: service.exactPrice ?? Decimal(service.price)
                )
            }
        )
    }
}

struct OperatorPortfolioProfile: Sendable {
    let provider: ServiceProvider
    let offers: [OperatorPortfolioOffer]
}

private struct PreviewEnvelope: Decodable {
    let data: PreviewPayload?
}

private struct PreviewPayload: Decodable {
    let items: [PreviewItemDTO]?
    let specialtyIds: [FlexiblePortfolioID]?
}

private struct PreviewItemDTO: Decodable {
    let id: FlexiblePortfolioID
    let mediaType: String?
    let mediaUrl: String?
    let thumbnailUrl: String?
    let thumbnail: String?
    let caption: String?
    let sortOrder: Int?
    let specialties: [PortfolioSpecialtyTag]?
    let bookingId: FlexiblePortfolioID?
    let isCover: Bool?
    let createdAt: String?

    func asItem() -> OperatorPortfolioItem {
        OperatorPortfolioItem(
            id: id.value,
            mediaType: mediaType ?? "photo",
            mediaURL: ProfileImageURLResolver.urlForAsyncImage(from: mediaUrl),
            thumbnailURL: ProfileImageURLResolver.urlForAsyncImage(from: thumbnailUrl ?? thumbnail),
            caption: caption?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            sortOrder: sortOrder ?? 0,
            specialties: (specialties ?? []).map(\.value).filter { !$0.isEmpty },
            bookingId: bookingId?.value,
            isCover: isCover ?? false,
            createdAt: OperatorPortfolioDate.parse(createdAt)
        )
    }
}

private struct PortfolioSpecialtyTag: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        if let object = try? decoder.container(keyedBy: CodingKeys.self),
           object.contains(.id) || object.contains(.slug) || object.contains(.name) {
            let id = try object.decodeIfPresent(FlexiblePortfolioID.self, forKey: .id)?.value
            let slug = try object.decodeIfPresent(String.self, forKey: .slug)
            let name = try object.decodeIfPresent(String.self, forKey: .name)
            value = [id, slug, name]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? ""
            return
        }
        let single = try decoder.singleValueContainer()
        if let text = try? single.decode(String.self), !text.isEmpty {
            value = text
            return
        }
        if let number = try? single.decode(Int.self) {
            value = String(number)
            return
        }
        value = ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name
    }
}

private struct FlexiblePortfolioID: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            value = s
        } else if let i = try? c.decode(Int.self) {
            value = String(i)
        } else if let d = try? c.decode(Double.self) {
            value = String(Int(d))
        } else {
            value = ""
        }
    }
}

private enum OperatorPortfolioDate {
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }
        fractional.formatOptions = [.withInternetDateTime]
        return fractional.date(from: trimmed)
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
