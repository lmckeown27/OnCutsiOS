//
//  AppConfiguration.swift
//  Intera
//
//  Environment-specific API base URL, Stripe publishable key, and typed endpoint URLs.
//

import Foundation
#if os(iOS)
import Core
#endif

/// Thread-safe configuration: only immutable `Sendable` static data and pure URL helpers.
enum AppConfiguration: Sendable {
    // MARK: - API v1 root (CampusCuts Express on EC2)

    /// Single root for versioned API: **scheme + host + `/api/v1`**, no trailing slash.
    ///
    /// **Production:** matches the web app when `VITE_API_URL=/api/v1` is served from `https://campuscut.com`
    /// (browser uses a relative path; iOS must use this absolute URL).
    ///
    /// **Local backend:** set to `http://127.0.0.1:3001/api/v1` (or your port). Debug **Info.plist** needs
    /// `NSAllowsLocalNetworking` for HTTP to the simulator host.
    private static let apiV1RootURLString = "https://campuscut.com/api/v1"

    /// Shell routes (`/auth/google`, `/providers/list`, …) are joined to this same root so Debug and Release hit one deployment.
    private static let apiBaseURLString = apiV1RootURLString

    /// Barbers list uses this root + `/barbers` (see `urlCampusCutsBarbers`).
    private static let campusCutsAPIv1BaseURLString = apiV1RootURLString

    static let apiBaseURL: URL = {
        guard let url = URL(string: apiBaseURLString) else {
            fatalError("Invalid AppConfiguration.apiBaseURLString")
        }
        return url
    }()

    /// Trimmed `https://…/api/v1` (no trailing slash) for REST clients that append paths.
    static var messagingAPIRootTrimmed: String {
        apiBaseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// CampusCuts web checkout for a booking after the provider marks the service complete (`COMPLETED` → consumer pays).
    /// Matches `booking-simple` complete handler: `{FRONTEND_URL}/web/payment/:bookingId`.
    static func urlConsumerBookingPaymentWeb(bookingId: String) -> URL? {
        let trimmed = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let host = apiBaseURL.host else { return nil }
        let scheme = (apiBaseURL.scheme == "http" || apiBaseURL.scheme == "https") ? (apiBaseURL.scheme ?? "https") : "https"
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: "/")
        let enc = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        return URL(string: "\(scheme)://\(host)/web/payment/\(enc)")
    }

    /// Socket.IO connects to the **origin** (scheme + host), not `/api/v1`.
    static var messagingSocketOriginURL: URL {
        guard let api = URL(string: apiV1RootURLString), let host = api.host else {
            return URL(string: "https://campuscut.com")!
        }
        let scheme = (api.scheme == "http" || api.scheme == "https") ? (api.scheme ?? "https") : "https"
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.port = api.port
        return c.url ?? URL(string: "\(scheme)://\(host)")!
    }

    // MARK: - Stripe

    /// Populated at build time: `STRIPE_PUBLISHABLE_KEY` in `Config/StripeKeys.xcconfig` → `GoogleSignInURL.plist` → `Bundle.StripeConfig`.
    /// Optional gitignored override: `Config/StripeKeys.secret.xcconfig` (see `StripeKeys.secret.xcconfig.example`).
    #if os(iOS)
    static var stripePublishableKey: String {
        Bundle.StripeConfig.publishableKey
    }
    #else
    static var stripePublishableKey: String { "" }
    #endif

    // MARK: - CampusCuts live data safety

    /// When `true`, Intera shows the CampusCuts **Live Data Mode** banner and routes the consumer **Book** action to a Stripe test-mode explanation instead of a real booking/checkout flow.
    /// Turn on only while debugging against production data.
    static let campusCutsProductionLiveDataMode = false

    // MARK: - Barbers list

    /// Optional `campusId` query (UUID or slug) for `GET /barbers`.
    static let campusCutsDefaultCampusId: String? = nil

    /// `GET …/api/v1/barbers/:id` — production embeds `reviews` on this payload (Prisma/bookings-backed).
    static func urlCampusCutsBarber(barberId: String) -> URL? {
        let base = campusCutsAPIv1BaseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = barberId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? barberId
        return URL(string: base + "/barbers/" + encoded)
    }

    /// `GET …/api/v1/barbers/:id/reviews` — optional; not deployed on all backends (may 404).
    static func urlBarberReviews(barberId: String) -> URL? {
        let base = campusCutsAPIv1BaseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = barberId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? barberId
        let joined = base + "/barbers/" + encoded + "/reviews"
        return URL(string: joined)
    }

    /// `GET …/api/v1/reviews/barber/:id` — Express review routes (shape may use `client_first_name`).
    static func urlReviewsForBarber(barberId: String) -> URL? {
        let base = campusCutsAPIv1BaseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = barberId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? barberId
        return URL(string: base + "/reviews/barber/" + encoded)
    }

    /// `GET …/api/v1/barbers/:id/availability?date=YYYY-MM-DD` — slot list for a calendar day (public).
    static func urlBarberAvailability(barberId: String, dateYYYYMMDD: String) -> URL? {
        let base = campusCutsAPIv1BaseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = barberId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? barberId
        var components = URLComponents(string: base + "/barbers/" + encoded + "/availability")
        components?.queryItems = [URLQueryItem(name: "date", value: dateYYYYMMDD)]
        return components?.url
    }

    /// `GET …/api/v1/barbers` (public; optional Bearer).
    /// With both `latitude` and `longitude`, the backend filters and sorts by distance (see `getAllBarbers`); omit either to skip geo params.
    static func urlCampusCutsBarbers(latitude: Double?, longitude: Double?, maxDistanceKm: Double? = nil) -> URL {
        var components = URLComponents(string: campusCutsAPIv1BaseURLString + "/barbers")!
        var items: [URLQueryItem] = []
        if let cid = campusCutsDefaultCampusId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty {
            items.append(URLQueryItem(name: "campusId", value: cid))
        }
        if let latitude, let longitude {
            items.append(URLQueryItem(name: "lat", value: String(latitude)))
            items.append(URLQueryItem(name: "lng", value: String(longitude)))
            if let maxDistanceKm {
                items.append(URLQueryItem(name: "maxDistance", value: String(maxDistanceKm)))
            }
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    /// Same path as `urlCampusCutsBarbers(latitude:nil, longitude:nil)` — no geo or campus query (unless `campusCutsDefaultCampusId` is set).
    static var urlCampusCutsBarbers: URL {
        urlCampusCutsBarbers(latitude: nil, longitude: nil, maxDistanceKm: nil)
    }

    // MARK: - Paths (joined to `apiV1RootURLString`)

    private static let pathAuthGoogle = "/auth/google"
    private static let pathAuthApple = "/auth/apple"
    private static let pathAuthMe = "/auth/me"
    /// Account creation (`POST`). Joined to the same `/api/v1` root as other auth routes (full URL: `…/api/v1/auth/register`).
    private static let pathAuthRegister = "/auth/register"
    private static let pathProvidersList = "/providers/list"
    /// Consumer creates a booking: `POST …/api/v1/bookings-simple` (see `booking-simple.routes.ts`).
    private static let pathBookingsSimpleCreate = "/bookings-simple"

    /// POST Google ID token (or your BFF contract).
    static var urlAuthGoogle: URL { url(forPath: pathAuthGoogle) }

    /// POST Sign in with Apple `identityToken` (App Store Guideline 4.8).
    static var urlAuthApple: URL { url(forPath: pathAuthApple) }

    /// GET current user (Bearer) — includes `needsPlatformPassword` / `needs_platform_password` per CampusCuts contract.
    static var urlAuthMe: URL { url(forPath: pathAuthMe) }

    /// Same handler as `urlAuthApple` but under `/api/auth/…` — some production proxies only forward the legacy prefix (`index.ts` mounts both).
    static var urlAuthAppleLegacy: URL {
        let trimmed = apiV1RootURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmed.hasSuffix("/api/v1") else {
            return urlAuthApple
        }
        let origin = String(trimmed.dropLast(7))
        let joined = origin + "/api/auth/apple"
        return URL(string: joined) ?? urlAuthApple
    }

    /// POST registration metadata (email, name, terms, etc.). Contract should match email login response shape where possible.
    static var urlAuthRegister: URL { url(forPath: pathAuthRegister) }

    /// Legacy list URL; home screen tries `urlCampusCutsBarbers` first, then this.
    static var urlProvidersList: URL { url(forPath: pathProvidersList) }

    /// `POST` — same handler the CampusCuts web app uses for simple bookings.
    static var urlBookingsSimpleCreate: URL { url(forPath: pathBookingsSimpleCreate) }

    static func url(forPath path: String) -> URL {
        let trimmedBase = apiBaseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segment = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let joined = trimmedBase + "/" + segment
        guard let url = URL(string: joined) else {
            fatalError("Invalid URL joining base and path: \(joined)")
        }
        return url
    }
}
