//
//  BarberPhotoTile.swift
//  OnCuts
//
//  Square photo tile for My Barbers / Discover (name overlay, MAIN badge, price range, next-open).
//

import SwiftUI

struct BarberPhotoTile: View {
    let provider: ServiceProvider
    var isMain: Bool = false
    var showsDistance: Bool = false
    var onTap: () -> Void

    private var nextOpen: String {
        MyBarbersDiscover.nextOpenDisplayString(for: provider)
    }

    private var priceLabel: String? {
        provider.priceRange?.displayLabel
    }

    private var distanceLabel: String? {
        guard showsDistance else { return nil }
        return provider.formattedDistanceFromUser
    }

    private var accessibilitySubtitle: String {
        [nextOpen, distanceLabel].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onTap) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    photo
                        .scaledToFill()
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [.black.opacity(0.72), .black.opacity(0.05), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 96)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) {
                    if let priceLabel {
                        Text(priceLabel)
                            .font(OnCutsFont.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.45), in: Capsule())
                            .padding(8)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isMain {
                        Text("MAIN")
                            .font(OnCutsFont.captionSmall.weight(.bold))
                            .tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.oliveGreen, in: Capsule())
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.businessName)
                            .font(OnCutsFont.labelMedium.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(nextOpen)
                            .font(OnCutsFont.caption)
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if showsDistance {
                            // Always reserve one line so “mi away” aligns across Discover tiles.
                            Text(distanceLabel ?? " ")
                                .font(OnCutsFont.caption)
                                .foregroundStyle(.white.opacity(distanceLabel == nil ? 0 : 0.88))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityHidden(distanceLabel == nil)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabelText: String {
        var parts = [provider.businessName, accessibilitySubtitle]
        if isMain { parts.insert("Main operator", at: 0) }
        if let priceLabel { parts.append(priceLabel) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var photo: some View {
        if let url = ProfileImageURLResolver.urlForAsyncImage(from: provider.profileImageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                case .failure:
                    placeholder
                case .empty:
                    placeholder.overlay { ProgressView().tint(.white) }
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.oliveGreen.opacity(0.35)
            Image(systemName: "person.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// Two-column photo tile grid used by My Barbers / Discover lists.
struct BarberPhotoTileGrid<Item: Identifiable>: View {
    let items: [Item]
    let provider: (Item) -> ServiceProvider
    var isMain: (Item) -> Bool = { _ in false }
    var showsDistance: Bool = false
    let onTap: (ServiceProvider) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { item in
                let p = provider(item)
                BarberPhotoTile(
                    provider: p,
                    isMain: isMain(item),
                    showsDistance: showsDistance,
                    onTap: { onTap(p) }
                )
            }
        }
    }
}
