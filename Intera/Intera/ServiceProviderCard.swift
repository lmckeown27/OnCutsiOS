//
//  ServiceProviderCard.swift
//  Intera
//
//  Platform-agnostic card component for displaying service provider information
//  Works for any service platform: haircuts, beauty, wellness, fitness, etc.
//

import SwiftUI

private struct ServiceProviderCardButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    let glassMorphNamespace: Namespace.ID?
    let liquidGlassInteractiveWithoutMorph: Bool
    let providerID: String
    let usesLiquidGlass: Bool
    let usesOpaqueBrowseChrome: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .background {
                ServiceProviderCardChromeBackground(
                    cornerRadius: cornerRadius,
                    glassMorphNamespace: glassMorphNamespace,
                    providerID: providerID,
                    usesLiquidGlass: usesLiquidGlass,
                    usesOpaqueBrowseChrome: usesOpaqueBrowseChrome,
                    isPressed: configuration.isPressed
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct ServiceProviderCard: View {
    let provider: ServiceProvider
    var onTap: (() -> Void)? = nil
    /// When non-`nil` on iOS 26+, the card uses interactive Liquid Glass + `glassEffectID` for morph with the detail panel (`GlassEffectContainer`).
    var glassMorphNamespace: Namespace.ID? = nil
    /// When `true` on iOS 26+, use opaque adaptive browse chrome (not refractive Liquid Glass on the list).
    var liquidGlassInteractiveWithoutMorph: Bool = false
    /// When non-`nil`, pairs with a detail view using the same namespace + `provider.id` for `matchedGeometryEffect` transitions.
    var matchedGeometryNamespace: Namespace.ID? = nil
    /// When `false`, the card does not accept taps (e.g. another provider detail overlay is open).
    var allowsInteraction: Bool = true
    
    private var cardCornerRadius: CGFloat { .radiusXL }
    
    /// True when the card participates in `glassEffectID` morph (detail sheet), not the main browse list.
    private var usesLiquidGlassMorphChrome: Bool {
        glassMorphNamespace != nil
    }

    /// Opaque frosted card on iOS 26+ browse — readable over the mesh; no refractive Liquid Glass.
    private var usesOpaqueBrowseChrome: Bool {
        guard glassMorphNamespace == nil else { return false }
        return liquidGlassInteractiveWithoutMorph || matchedGeometryNamespace != nil
    }

    private var usesLiquidGlassEffect: Bool {
        usesLiquidGlassMorphChrome
    }

    private var cardPrimaryTextColor: Color {
        if usesLiquidGlassMorphChrome { return .primary }
        if usesOpaqueBrowseChrome { return .interaShellForeground }
        return .neutral800
    }

    private var cardSecondaryTextColor: Color {
        if usesLiquidGlassMorphChrome { return .secondary }
        if usesOpaqueBrowseChrome { return .interaShellForegroundSecondary }
        return .neutral600
    }

    private var cardAccentTextColor: Color {
        if usesLiquidGlassMorphChrome { return .white }
        return .oliveGreen
    }

    private var kindPillForegroundColor: Color {
        if usesLiquidGlassMorphChrome { return .white }
        return .brand
    }

    private var kindPillBackgroundColor: Color {
        if usesLiquidGlassMorphChrome { return Color.white.opacity(0.22) }
        return Color.brand.opacity(0.1)
    }

    /// Hide stars until there’s some social proof: reviews, booking count, or embedded list reviews.
    /// Important: if `completedBookings` is present but `0`, we still show stars when `reviewCount` > 0
    /// (list APIs often expose review stats separately from `total_bookings`).
    private var shouldShowStarRatingOnCard: Bool {
        guard provider.rating != nil else { return false }
        if (provider.reviewCount ?? 0) > 0 { return true }
        if (provider.completedBookings ?? 0) > 0 { return true }
        if let embedded = provider.customerReviews, !embedded.isEmpty { return true }
        return false
    }
    
    var body: some View {
        Button {
            guard allowsInteraction else { return }
            onTap?()
        } label: {
            HStack(alignment: .top, spacing: .space4) {
                // Square Profile Image
                if let imageUrl = provider.profileImageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.brand.opacity(0.2))
                            .overlay(
                                Text(provider.businessName.prefix(2).uppercased())
                                    .font(.headline)
                                    .foregroundStyle(Color.brand)
                            )
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Rectangle()
                        .fill(Color.brand.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            Text(provider.businessName.prefix(2).uppercased())
                                .font(.headline)
                                .foregroundStyle(Color.brand)
                        )
                }
                
                // Info (top-aligned so text isn’t clipped to the image height)
                VStack(alignment: .leading, spacing: .space2) {
                    // Name
                    Text(provider.businessName)
                        .font(.headlineSmall)
                        .foregroundStyle(cardPrimaryTextColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)

                    if shouldShowStarRatingOnCard, let rating = provider.rating {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(cardPrimaryTextColor)
                            if let count = provider.reviewCount, count > 0 {
                                Text("(\(count))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(cardSecondaryTextColor)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "Average rating \(String(format: "%.1f", rating)) out of five"
                                + (provider.reviewCount.map { ", \($0) reviews" } ?? "")
                        )
                    }
                    
                    // Provider kind (Barber, Makeup, Nails, …) — not individual services / haircut names
                    Text(provider.providerKindDisplayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(kindPillForegroundColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(kindPillBackgroundColor)
                        .clipShape(Capsule())
                    
                    // Instagram handle (visible only; open profile from detail sheet to visit)
                    if !provider.instagramDisplayHandle.isEmpty {
                        Text(provider.instagramDisplayHandle)
                            .font(.bodySmall)
                            .foregroundStyle(cardSecondaryTextColor)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                            .accessibilityLabel("Instagram \(provider.instagramDisplayHandle), open provider to visit")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Price range + miles from user (trailing)
                if provider.priceRange != nil || provider.formattedDistanceFromUser != nil {
                    VStack(alignment: .trailing, spacing: .space1) {
                        if let priceRange = provider.priceRange {
                            Text(priceRange.displayLabel)
                                .font(.bodyMedium)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(cardAccentTextColor)
                        }
                        if let distanceLabel = provider.formattedDistanceFromUser {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.caption.weight(.semibold))
                                    .accessibilityHidden(true)
                                Text(distanceLabel)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(cardSecondaryTextColor)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("About \(distanceLabel) from your location")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.space4)
        }
        .buttonStyle(
            ServiceProviderCardButtonStyle(
                cornerRadius: cardCornerRadius,
                glassMorphNamespace: glassMorphNamespace,
                liquidGlassInteractiveWithoutMorph: liquidGlassInteractiveWithoutMorph,
                providerID: provider.id,
                usesLiquidGlass: usesLiquidGlassEffect,
                usesOpaqueBrowseChrome: usesOpaqueBrowseChrome
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .disabled(!allowsInteraction)
        .modifier(ServiceProviderCardShadowModifier())
        .modifier(ServiceProviderCardMatchedGeometryModifier(
            namespace: matchedGeometryNamespace,
            geometryId: provider.id
        ))
    }
}

// MARK: - Card chrome (Liquid Glass vs solid)

private extension View {
    /// Frosted card treatment aligned with browse glass (avoids flat solid white, especially on iPad / wide layouts).
    func providerCardFrostedChrome(cornerRadius: CGFloat) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Opaque shell-aligned surface for browse list cards (no mesh refraction).
private struct ServiceProviderCardOpaqueBrowseChrome: View {
    let cornerRadius: CGFloat
    let isPressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color.interaShellBackground.opacity(0.96))
            .overlay {
                shape.strokeBorder(Color.interaShellGlassStroke, lineWidth: 0.5)
            }
            .overlay {
                if isPressed {
                    shape.fill(Color.interaShellForeground.opacity(0.07))
                }
            }
    }
}

/// Liquid Glass for `glassEffectID` morph only (not used on the main browse list).
@available(iOS 26.0, macOS 26.0, *)
private struct ServiceProviderCardLiquidGlassPlate: View {
    let cornerRadius: CGFloat
    let glassMorphNamespace: Namespace.ID?
    let providerID: String
    let usesMorphID: Bool
    let isPressed: Bool

    var body: some View {
        let glassShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let rect = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if isPressed {
                glassShape
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: rect)
            } else {
                glassShape
                    .fill(.clear)
                    .glassEffect(.clear, in: rect)
            }
        }
        .modifier(ServiceProviderCardGlassEffectIDModifier(
            providerID: providerID,
            namespace: usesMorphID ? glassMorphNamespace : nil
        ))
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct ServiceProviderCardGlassEffectIDModifier: ViewModifier {
    let providerID: String
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.glassEffectID(providerID, in: namespace)
        } else {
            content
        }
    }
}

private struct ServiceProviderCardChromeBackground: View {
    let cornerRadius: CGFloat
    let glassMorphNamespace: Namespace.ID?
    let providerID: String
    let usesLiquidGlass: Bool
    let usesOpaqueBrowseChrome: Bool
    let isPressed: Bool

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *), usesLiquidGlass {
            ServiceProviderCardLiquidGlassPlate(
                cornerRadius: cornerRadius,
                glassMorphNamespace: glassMorphNamespace,
                providerID: providerID,
                usesMorphID: glassMorphNamespace != nil,
                isPressed: isPressed
            )
        } else if usesOpaqueBrowseChrome {
            ServiceProviderCardOpaqueBrowseChrome(
                cornerRadius: cornerRadius,
                isPressed: isPressed
            )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                }
        }
    }
}

private struct ServiceProviderCardShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

private struct ServiceProviderCardMatchedGeometryModifier: ViewModifier {
    let namespace: Namespace.ID?
    let geometryId: String
    
    func body(content: Content) -> some View {
        if let ns = namespace {
            content.matchedGeometryEffect(id: geometryId, in: ns)
        } else {
            content
        }
    }
}

// MARK: - Customer reviews (detail sheet)

struct ProviderReview: Identifiable, Codable, Hashable {
    let id: String
    let authorDisplayName: String
    /// 0…5 stars from the customer; `nil` if the payload omitted or failed to decode a rating.
    let rating: Int?
    let relativeDate: String
    /// Written feedback; `nil` when the customer left stars only.
    let comment: String?
}

// MARK: - ServiceProvider Model

/// Platform-agnostic service provider model
/// This works for ANY type of service provider across all platforms:
/// - Haircut providers (from CampusCuts package)
/// - Beauty specialists (from Beauty platform package)
/// - Wellness providers (from Wellness platform package)
/// - Fitness trainers (from Fitness platform package)
/// - etc.
struct ServiceProvider: Identifiable, Codable {
    let id: String
    let userId: String
    let businessName: String
    let bio: String?
    let instagramHandle: String?
    let profileImageUrl: String?
    let rating: Double?
    let reviewCount: Int?
    let completedBookings: Int?
    let isAvailableNow: Bool?
    let priceRange: PriceRange?
    let category: ServiceCategory? // For filtering and organization
    let specialty: String? // Provider kind for browse/card: "Barber", "Makeup", "Nails", "Tanning", etc. (not individual services)
    let services: [Service]? // Services offered with prices
    let availability: [DayAvailability]? // Weekly availability schedule
    let locations: [String]? // Service locations
    /// Miles from the user’s device when browse `GET /barbers` was called with `lat`/`lng` (server `distance_miles`).
    let distanceMilesFromUser: Double?
    /// Populated from API (list embed or detail fetch); detail UI loads `/barbers/:id/reviews` when needed.
    let customerReviews: [ProviderReview]?

    struct PriceRange: Codable {
        let min: Int
        let max: Int
    }
    
    struct Service: Identifiable, Codable {
        let id: String
        let name: String
        let price: Int
        let duration: Int? // in minutes
        let description: String?
        
        var formattedPrice: String {
            "$\(price)"
        }
    }
    
    struct DayAvailability: Identifiable, Codable {
        let id: String
        let dayOfWeek: String // "Mon", "Tue", etc.
        let timeSlots: [String] // e.g., ["9am-12pm", "2pm-5pm"]
        
        var isAvailable: Bool {
            !timeSlots.isEmpty
        }
    }
    
    /// Service categories for organizing providers
    /// This allows the shell app to categorize providers from different platforms
    enum ServiceCategory: String, Codable, CaseIterable, Identifiable, Hashable {
        case haircuts = "Haircuts"
        case beauty = "Beauty"
        case wellness = "Wellness"
        case fitness = "Fitness"
        
        var id: String { rawValue }
        
        var displayName: String { rawValue }
        
        var icon: String {
            switch self {
            case .haircuts: return "scissors"
            case .beauty: return "sparkles"
            case .wellness: return "heart"
            case .fitness: return "figure.run"
            }
        }
    }
    
    // MARK: - Mock Data for Development
    
    /// Mock haircut providers (simulates data from CampusCuts platform)
    static let haircutMocks: [ServiceProvider] = [
        ServiceProvider(
            id: "barber-101",
            userId: "user-101",
            businessName: "Jordan Williams",
            bio: "Professional barber specializing in fades and modern styles. 7+ years cutting experience.",
            instagramHandle: "jordanwilliams.barber",
            profileImageUrl: "https://i.pravatar.cc/300?img=12",
            rating: 4.8,
            reviewCount: 42,
            completedBookings: 127,
            isAvailableNow: true,
            priceRange: PriceRange(min: 20, max: 45),
            category: .haircuts,
            specialty: "Barber",
            services: [
                Service(id: "s1", name: "Buzz Cut", price: 15, duration: 20, description: nil),
                Service(id: "s2", name: "Fade", price: 25, duration: 30, description: nil),
                Service(id: "s3", name: "Haircut", price: 20, duration: 30, description: nil),
                Service(id: "s4", name: "Haircut & Fade", price: 30, duration: 45, description: nil),
                Service(id: "s5", name: "Line Up", price: 15, duration: 15, description: nil),
                Service(id: "s6", name: "Taper", price: 25, duration: 30, description: nil)
            ],
            availability: [
                DayAvailability(id: "mon", dayOfWeek: "Mon", timeSlots: ["8pm-10pm", "9am-12pm"]),
                DayAvailability(id: "tue", dayOfWeek: "Tue", timeSlots: ["9am-3pm"]),
                DayAvailability(id: "wed", dayOfWeek: "Wed", timeSlots: ["8pm-10pm"]),
                DayAvailability(id: "thu", dayOfWeek: "Thu", timeSlots: ["9am-3pm"]),
                DayAvailability(id: "fri", dayOfWeek: "Fri", timeSlots: ["9am-10pm"]),
                DayAvailability(id: "sat", dayOfWeek: "Sat", timeSlots: ["9am-10pm"]),
                DayAvailability(id: "sun", dayOfWeek: "Sun", timeSlots: ["9am-10pm"])
            ],
            locations: ["Poly Canyon Village \"PCV\""],
            distanceMilesFromUser: nil,
            customerReviews: nil
        ),
        ServiceProvider(
            id: "barber-102",
            userId: "user-102",
            businessName: "Alex Thompson",
            bio: "Classic cuts and beard trims. Walk-ins welcome! Trained in traditional barbering techniques.",
            instagramHandle: "alexthompson.cuts",
            profileImageUrl: "https://i.pravatar.cc/300?img=13",
            rating: 4.5,
            reviewCount: 28,
            completedBookings: 85,
            isAvailableNow: false,
            priceRange: PriceRange(min: 15, max: 35),
            category: .haircuts,
            specialty: "Barber",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        ),
        ServiceProvider(
            id: "barber-103",
            userId: "user-103",
            businessName: "Marcus Johnson",
            bio: "Precision cuts and hot towel shaves. 10+ years experience in men's grooming and styling.",
            instagramHandle: "marcusjohnson.barber",
            profileImageUrl: "https://i.pravatar.cc/300?img=14",
            rating: 4.9,
            reviewCount: 67,
            completedBookings: 215,
            isAvailableNow: true,
            priceRange: PriceRange(min: 25, max: 60),
            category: .haircuts,
            specialty: "Barber",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        ),
        ServiceProvider(
            id: "barber-104",
            userId: "user-104",
            businessName: "Tyler Garcia",
            bio: "Modern barber specializing in fades, tapers, and lineup perfection. Always on trend.",
            instagramHandle: "tylergarcia.fades",
            profileImageUrl: "https://i.pravatar.cc/300?img=15",
            rating: 4.7,
            reviewCount: 53,
            completedBookings: 142,
            isAvailableNow: true,
            priceRange: PriceRange(min: 22, max: 50),
            category: .haircuts,
            specialty: "Barber",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        ),
        ServiceProvider(
            id: "barber-105",
            userId: "user-105",
            businessName: "James Anderson",
            bio: "Traditional barbering meets modern style. Serving the community since 2015 with quality cuts.",
            instagramHandle: "jamesanderson.barber",
            profileImageUrl: "https://i.pravatar.cc/300?img=16",
            rating: 4.6,
            reviewCount: 89,
            completedBookings: 267,
            isAvailableNow: false,
            priceRange: PriceRange(min: 18, max: 40),
            category: .haircuts,
            specialty: "Barber",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        )
    ]
    
    // Convenience shortcuts
    static let mock = haircutMocks[0]
    static let mock2 = haircutMocks[1]
    
    /// Mock beauty specialists (simulates data from Beauty platform)
    static let beautyMocks: [ServiceProvider] = [
        // Makeup Artist
        ServiceProvider(
            id: "beauty-201",
            userId: "user-1001",
            businessName: "Maya Chen",
            bio: "Professional makeup artist specializing in bridal, special events, and photo shoots. 5+ years experience with MAC and high-end cosmetics.",
            instagramHandle: "mayachen.mua",
            profileImageUrl: "https://i.pravatar.cc/300?img=47",
            rating: 4.9,
            reviewCount: 87,
            completedBookings: 156,
            isAvailableNow: true,
            priceRange: PriceRange(min: 50, max: 150),
            category: .beauty,
            specialty: "Makeup",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        ),
        
        // Hair Stylist (Women's)
        ServiceProvider(
            id: "beauty-202",
            userId: "user-1002",
            businessName: "Sophia Rodriguez",
            bio: "Expert in women's cuts, color, balayage, and extensions. Certified colorist with 8 years salon experience.",
            instagramHandle: "sophiahair",
            profileImageUrl: "https://i.pravatar.cc/300?img=48",
            rating: 4.8,
            reviewCount: 142,
            completedBookings: 289,
            isAvailableNow: false,
            priceRange: PriceRange(min: 65, max: 250),
            category: .beauty,
            specialty: "Hair",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        ),
        
        // Nail Technician
        ServiceProvider(
            id: "beauty-203",
            userId: "user-1003",
            businessName: "Jasmine Torres",
            bio: "Licensed nail tech offering manicures, pedicures, gel nails, and nail art. Hygiene is my priority!",
            instagramHandle: "jasmine.nails",
            profileImageUrl: "https://i.pravatar.cc/300?img=49",
            rating: 4.7,
            reviewCount: 98,
            completedBookings: 203,
            isAvailableNow: true,
            priceRange: PriceRange(min: 35, max: 85),
            category: .beauty,
            specialty: "Nails",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        ),

        // Tanning / spray tan
        ServiceProvider(
            id: "beauty-204",
            userId: "user-1004",
            businessName: "Avery Brooks",
            bio: "Certified spray tan artist — custom shades, natural finish, and mobile appointments around campus.",
            instagramHandle: "avery.glow.tan",
            profileImageUrl: "https://i.pravatar.cc/300?img=32",
            rating: 4.8,
            reviewCount: 64,
            completedBookings: 112,
            isAvailableNow: true,
            priceRange: PriceRange(min: 40, max: 95),
            category: .beauty,
            specialty: "Tanning",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        ),
        
        // Lash Specialist
        ServiceProvider(
            id: "beauty-206",
            userId: "user-1006",
            businessName: "Victoria Lee",
            bio: "Certified lash extension artist offering classic, hybrid, and volume sets. Also lash lifts and tints.",
            instagramHandle: "victorialashes",
            profileImageUrl: "https://i.pravatar.cc/300?img=27",
            rating: 4.8,
            reviewCount: 91,
            completedBookings: 187,
            isAvailableNow: true,
            priceRange: PriceRange(min: 70, max: 180),
            category: .beauty,
            specialty: "Lashes",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        ),
        
        // Hair Braiding Specialist
        ServiceProvider(
            id: "beauty-209",
            userId: "user-1009",
            businessName: "Keisha Washington",
            bio: "Expert in box braids, cornrows, knotless braids, and protective styles. Book early - I fill up fast!",
            instagramHandle: "keishabraids",
            profileImageUrl: "https://i.pravatar.cc/300?img=28",
            rating: 5.0,
            reviewCount: 143,
            completedBookings: 221,
            isAvailableNow: true,
            priceRange: PriceRange(min: 80, max: 200),
            category: .beauty,
            specialty: "Braids",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        )
    ]
    
    // MARK: - Convenience Collections
    
    /// For backward compatibility and convenience
    static let mocks: [ServiceProvider] = haircutMocks
    
    /// All mock service providers across all platforms
    static let allMocks: [ServiceProvider] = haircutMocks + beautyMocks
}

extension ServiceProvider.PriceRange {
    /// One price when min and max match (all services priced the same); otherwise a range.
    var displayLabel: String {
        if min == max {
            return "$\(min)"
        }
        return "$\(min) - $\(max)"
    }
}

// MARK: - Social links

extension ServiceProvider {
    /// Human-readable distance when the browse API included `distance_miles` (request used device `lat`/`lng`).
    var formattedDistanceFromUser: String? {
        guard let miles = distanceMilesFromUser, miles >= 0, miles.isFinite else { return nil }
        if miles < 10 {
            return String(format: "%.1f mi away", miles)
        }
        return String(format: "%.0f mi away", miles)
    }

    /// Reviews already on the model (e.g. embedded in barber list). Detail sheet may replace this with a fresh fetch.
    var reviewsForDetail: [ProviderReview] {
        customerReviews ?? []
    }

    /// Public Instagram profile URL derived from `instagramHandle` (username with or without `@`).
    var instagramProfileURL: URL? {
        guard let raw = instagramHandle?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let username = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
        guard !username.isEmpty else { return nil }
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return URL(string: "https://www.instagram.com/\(encoded)/")
    }
    
    /// Display string for the handle, always with a leading `@` when non-empty.
    var instagramDisplayHandle: String {
        guard let raw = instagramHandle?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }
        return raw.hasPrefix("@") ? raw : "@\(raw)"
    }
    
    /// First whitespace-separated word of `businessName` (consumer name search uses this only, not last name).
    var consumerSearchFirstName: String {
        let trimmed = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        return parts.first.map(String.init) ?? trimmed
    }
    
    /// Used by consumer browse/search: first name (substring), plus word-prefix matches on specialty, Instagram segments, bio words, category.
    func matchesConsumerSearch(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if consumerSearchFirstName.localizedCaseInsensitiveContains(q) { return true }
        if let specialty, Self.wordHasPrefixMatch(in: specialty, prefix: q) { return true }
        if let handle = instagramHandle, Self.instagramHandleMatches(handle: handle, query: q) { return true }
        if let bio, Self.wordHasPrefixMatch(in: bio, prefix: q) { return true }
        if let category, Self.wordHasPrefixMatch(in: category.displayName, prefix: q) { return true }
        return false
    }
    
    /// Sort order when searching: first-name prefix first, then first-name substring, then other field matches.
    func consumerSearchSortPriority(query: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return 0 }
        let ql = q.lowercased()
        let first = consumerSearchFirstName.lowercased()
        if first.hasPrefix(ql) { return 0 }
        if first.localizedCaseInsensitiveContains(q) { return 1 }
        return 2
    }
    
    /// True if any alphanumeric “word” in `text` starts with `prefix` (avoids “Ty” matching “styles”).
    private static func wordHasPrefixMatch(in text: String, prefix: String) -> Bool {
        let p = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !p.isEmpty else { return false }
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .contains { $0.hasPrefix(p) }
    }
    
    private static func instagramHandleMatches(handle: String, query: String) -> Bool {
        let q = query.replacingOccurrences(of: "@", with: "", options: .literal)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !q.isEmpty else { return false }
        let h = handle.lowercased()
        if h.hasPrefix(q) { return true }
        let segments = h.split { $0 == "." || $0 == "_" || $0 == "-" }.map(String.init)
        return segments.contains { $0.hasPrefix(q) }
    }
}

// MARK: - Preview

#Preview("Single Card") {
    ServiceProviderCard(provider: .mock)
        .padding()
        .background(Color.neutral50)
}

#Preview("List - Haircut Providers") {
    ScrollView {
        VStack(spacing: .space4) {
            ForEach(ServiceProvider.haircutMocks) { provider in
                ServiceProviderCard(provider: provider) {
                    print("Tapped \(provider.businessName)")
                }
            }
        }
        .padding()
    }
    .background(Color.neutral50)
}

#Preview("List - Beauty Specialists") {
    ScrollView {
        VStack(spacing: .space4) {
            ForEach(ServiceProvider.beautyMocks) { provider in
                ServiceProviderCard(provider: provider) {
                    print("Tapped \(provider.businessName)")
                }
            }
        }
        .padding()
    }
    .background(Color.neutral50)
}

#Preview("List - All Platforms") {
    ScrollView {
        VStack(spacing: .space4) {
            Text("HAIRCUTS")
                .font(.labelSmall)
                .foregroundStyle(Color.neutral500)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(ServiceProvider.haircutMocks) { provider in
                ServiceProviderCard(provider: provider)
            }
            
            Text("BEAUTY")
                .font(.labelSmall)
                .foregroundStyle(Color.neutral500)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, .space4)
            
            ForEach(ServiceProvider.beautyMocks) { provider in
                ServiceProviderCard(provider: provider)
            }
        }
        .padding()
    }
    .background(Color.neutral50)
}

// MARK: - Architecture Notes

/*
 This file is part of the SHELL APP layer - it's platform-agnostic.
 
 Platform-Specific Models (live in their own packages):
 - CampusCuts: Barber model (see Barber.swift)
 - Beauty Platform: BeautySpecialist model (future)
 - Wellness Platform: WellnessProvider model (future)
 
 Adapters Convert to ServiceProvider:
 - CampusCutsAdapter: Barber → ServiceProvider
 - BeautyPlatformAdapter: BeautySpecialist → ServiceProvider
 - WellnessPlatformAdapter: WellnessProvider → ServiceProvider
 
 This allows:
 - Each platform to maintain its own specific data structure
 - Shell app to display everything consistently
 - Easy addition of new platforms without UI changes
 */
