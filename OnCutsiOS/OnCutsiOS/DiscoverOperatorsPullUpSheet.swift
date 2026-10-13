//
//  DiscoverOperatorsPullUpSheet.swift
//  OnCuts
//
//  Map-first Discover sheet. Three stops: peek (map), split (default), and full list.
//  The map stays mounted underneath; dragging or tapping the handle moves the sheet.
//

import SwiftUI

enum DiscoverNearbySheetDetent: Equatable {
    case peek
    case split
    case full
}

struct DiscoverOperatorsPullUpSheet: View {
    let providers: [ServiceProvider]
    var isLoading: Bool = false
    var bottomInset: CGFloat = 0
    /// Full screen height so the expanded list can reach the top chrome.
    var containerHeight: CGFloat = 800
    /// Space reserved for the floating search so the full list does not cover it.
    var topChromeInset: CGFloat = 120
    var reopenToken: Int = 0
    /// Increment to return from the full list to the split stop.
    var collapseToSplitToken: Int = 0
    /// Increment to open the full list (e.g. when search gains focus).
    var expandToFullToken: Int = 0
    /// Search and tags, shown under the title. Kept out of the drag area so the tag strip can scroll sideways.
    var controls: AnyView? = nil
    /// Browse location control; replaces the title row. Outside the drag area so its field and toggle stay interactive.
    var location: AnyView? = nil
    var preferredIsOpen: Bool? = nil
    var onOpened: (() -> Void)? = nil
    var onDetentChange: (DiscoverNearbySheetDetent) -> Void = { _ in }
    let onProviderTap: (ServiceProvider) -> Void

    @State private var detent: DiscoverNearbySheetDetent = .split
    @State private var sheetHeight: CGFloat = 0
    @State private var dragStartHeight: CGFloat = 0
    @State private var isDragging: Bool = false

    private var peekHeight: CGFloat { Self.peekHeight(bottomInset: bottomInset) }
    private var splitHeight: CGFloat {
        Self.splitHeight(bottomInset: bottomInset, containerHeight: containerHeight, topChromeInset: topChromeInset)
    }
    private var fullHeight: CGFloat {
        Self.fullHeight(bottomInset: bottomInset, containerHeight: containerHeight, topChromeInset: topChromeInset)
    }

    static func peekHeight(bottomInset: CGFloat) -> CGFloat { 58 + bottomInset }

    static func splitHeight(bottomInset: CGFloat, containerHeight: CGFloat, topChromeInset: CGFloat) -> CGFloat {
        let proposed = 420 + bottomInset
        let full = fullHeight(bottomInset: bottomInset, containerHeight: containerHeight, topChromeInset: topChromeInset)
        return min(max(peekHeight(bottomInset: bottomInset) + 120, proposed), full)
    }

    static func fullHeight(bottomInset: CGFloat, containerHeight: CGFloat, topChromeInset: CGFloat) -> CGFloat {
        max(peekHeight(bottomInset: bottomInset) + 160, containerHeight - topChromeInset)
    }

    private var renderedSheetHeight: CGFloat {
        if sheetHeight > 1 { return sheetHeight }
        return height(for: detent)
    }

    private var listProgress: CGFloat {
        let span = max(1, splitHeight - peekHeight)
        return min(1, max(0, (renderedSheetHeight - peekHeight) / span))
    }

    private var sheetSpring: Animation {
        .interactiveSpring(response: 0.28, dampingFraction: 0.9, blendDuration: 0.1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .highPriorityGesture(sheetDragGesture)

            if let location {
                HStack(spacing: 10) {
                    location
                    operatorCount
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .opacity(Double(listProgress))
                .allowsHitTesting(listProgress > 0.55 && !isDragging)
                // Place suggestions drop down over the controls and list below.
                .zIndex(2)
            }

            if let controls {
                controls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .opacity(Double(listProgress))
                    .allowsHitTesting(listProgress > 0.55 && !isDragging)
            }

            Group {
                if isLoading && providers.isEmpty {
                    ProgressView()
                        .tint(Color.oliveGreen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if providers.isEmpty {
                    Text("No operators here yet")
                        .font(OnCutsFont.bodyMedium)
                        .foregroundStyle(Color.neutral500)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                                DiscoverNearbyOperatorRow(provider: provider) {
                                    onProviderTap(provider)
                                }
                                if index < providers.count - 1 {
                                    Divider()
                                        .overlay(Color.primary.opacity(0.08))
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .padding(.bottom, bottomInset + 12)
                    }
                    .scrollDisabled(isDragging)
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(Double(listProgress))
            .allowsHitTesting(listProgress > 0.55 && !isDragging)
        }
        .frame(maxWidth: .infinity)
        .frame(height: renderedSheetHeight, alignment: .top)
        .clipped()
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 20, bottomLeading: 0, bottomTrailing: 0, topTrailing: 20),
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay {
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 20, bottomLeading: 0, bottomTrailing: 0, topTrailing: 20),
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.35), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: -4)
        }
        .overlay(alignment: .top) {
            if detent == .full {
                mapPill
                    .offset(y: -52)
            }
        }
        .onAppear {
            let initial: DiscoverNearbySheetDetent = preferredIsOpen == false ? .peek : .split
            settle(initial, animated: false)
        }
        .onChange(of: bottomInset) { _, _ in
            settle(detent, animated: false)
        }
        .onChange(of: containerHeight) { _, _ in
            settle(detent, animated: false)
        }
        .onChange(of: reopenToken) { _, _ in
            settle(.split)
        }
        .onChange(of: collapseToSplitToken) { _, _ in
            settle(.split)
        }
        .onChange(of: expandToFullToken) { _, _ in
            settle(.full)
        }
        .onChange(of: preferredIsOpen) { _, preferred in
            guard let preferred else { return }
            settle(preferred ? .split : .peek)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.28))
                .frame(width: 36, height: 5)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { toggleDetent() }

            if location == nil {
                HStack(alignment: .firstTextBaseline) {
                    Text("Nearby · closest first")
                        .font(OnCutsFont.headlineSmall.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    operatorCount
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .opacity(Double(listProgress))
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(location == nil ? "Nearby, closest first" : "Nearby operators")
        .accessibilityHint("Swipe to resize the list")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var operatorCount: some View {
        if !providers.isEmpty {
            Text("\(providers.count)")
                .font(OnCutsFont.caption.weight(.semibold))
                .foregroundStyle(Color.neutral500)
                .monospacedDigit()
        }
    }

    private var mapPill: some View {
        Button {
            settle(.split)
        } label: {
            Text("Map")
                .font(OnCutsFont.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground), in: Capsule())
                .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map")
        .accessibilityHint("Returns to the split map and list")
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let dx = abs(value.translation.width)
                let dy = abs(value.translation.height)
                if !isDragging {
                    guard dy >= 10, dy > dx * 1.15 else { return }
                    isDragging = true
                    dragStartHeight = sheetHeight > 1 ? sheetHeight : height(for: detent)
                }
                let proposed = dragStartHeight - value.translation.height
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    sheetHeight = rubberBand(proposed)
                }
            }
            .onEnded { value in
                let locked = isDragging
                let movedSheet = abs(renderedSheetHeight - height(for: detent)) > 4
                isDragging = false
                guard locked || movedSheet else { return }
                settle(
                    resolvedDetent(
                        translationY: value.translation.height,
                        velocityY: value.velocity.height
                    )
                )
            }
    }

    private func height(for detent: DiscoverNearbySheetDetent) -> CGFloat {
        switch detent {
        case .peek: return peekHeight
        case .split: return splitHeight
        case .full: return fullHeight
        }
    }

    private func rubberBand(_ proposed: CGFloat) -> CGFloat {
        let minH = peekHeight
        let maxH = fullHeight
        if proposed < minH {
            return minH - (minH - proposed) * 0.16
        }
        if proposed > maxH {
            return maxH + (proposed - maxH) * 0.12
        }
        return proposed
    }

    private func resolvedDetent(translationY: CGFloat, velocityY: CGFloat) -> DiscoverNearbySheetDetent {
        let height = renderedSheetHeight
        if translationY < -48 || velocityY < -700 {
            return step(from: nearest(to: height), direction: -1)
        }
        if translationY > 48 || velocityY > 700 {
            return step(from: nearest(to: height), direction: 1)
        }
        return nearest(to: height)
    }

    private func nearest(to height: CGFloat) -> DiscoverNearbySheetDetent {
        let stops: [(DiscoverNearbySheetDetent, CGFloat)] = [
            (.peek, peekHeight),
            (.split, splitHeight),
            (.full, fullHeight),
        ]
        return stops.min { abs($0.1 - height) < abs($1.1 - height) }?.0 ?? .split
    }

    /// Negative direction moves toward the full list.
    private func step(from detent: DiscoverNearbySheetDetent, direction: Int) -> DiscoverNearbySheetDetent {
        switch (detent, direction) {
        case (.peek, -1): return .split
        case (.split, -1): return .full
        case (.full, 1): return .split
        case (.split, 1): return .peek
        default: return detent
        }
    }

    private func toggleDetent() {
        switch detent {
        case .peek: settle(.split)
        case .split: settle(.full)
        case .full: settle(.split)
        }
    }

    private func settle(_ next: DiscoverNearbySheetDetent, animated: Bool = true) {
        let target = height(for: next)
        let apply = {
            detent = next
            sheetHeight = target
        }
        if animated {
            withAnimation(sheetSpring, apply)
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, apply)
        }
        onDetentChange(next)
        if next != .peek {
            onOpened?()
        }
    }
}

// MARK: - Nearby row

private struct DiscoverNearbyOperatorRow: View {
    let provider: ServiceProvider
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    AvatarView(
                        imageUrl: provider.profileImageUrl,
                        name: provider.businessName,
                        size: 32
                    )
                    Text(provider.businessName)
                        .font(OnCutsFont.bodyMedium.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(provider.providerKindDisplayName)
                        .font(OnCutsFont.bodyMedium)
                        .foregroundStyle(Color.neutral500)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            DiscoverNearbyWorkStrip(barberId: provider.id, onTap: onTap)

            Button(action: onTap) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(DiscoverNearbyCopy.convenienceLine(for: provider))
                        .font(OnCutsFont.bodyMedium.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let price = DiscoverNearbyCopy.priceRangeLabel(for: provider) {
                        Text(price)
                            .font(OnCutsFont.bodyMedium.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(DiscoverNearbyCopy.accessibilityLabel(for: provider))
        .accessibilityAction { onTap() }
    }
}

private struct DiscoverNearbyWorkStrip: View {
    let barberId: String
    let onTap: () -> Void

    @State private var items: [OperatorPortfolioItem] = []
    @State private var didLoad = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if items.isEmpty {
                    DiscoverNearbyEmptyWorkTile()
                        .opacity(didLoad ? 1 : 0.45)
                } else {
                    ForEach(items) { item in
                        Button(action: onTap) {
                            DiscoverNearbyWorkTile(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.trailing, 36)
        }
        .scrollClipDisabled()
        .padding(.trailing, -16)
        .frame(height: Self.tileHeight)
        .task(id: barberId) {
            await loadLatest()
        }
    }

    private static let tileWidth: CGFloat = 96
    private static let tileHeight: CGFloat = 96 * 16 / 9

    private func loadLatest() async {
        do {
            guard case .available(let preview) = try await OperatorPortfolioPreviewAPI.fetch(barberId: barberId) else {
                items = []
                didLoad = true
                return
            }
            let withMedia = preview.items.filter { $0.tileURL != nil }
            items = Array(withMedia.sorted { lhs, rhs in
                let left = lhs.createdAt ?? .distantPast
                let right = rhs.createdAt ?? .distantPast
                if left != right { return left > right }
                return lhs.sortOrder > rhs.sortOrder
            }.prefix(4))
            didLoad = true
        } catch {
            items = []
            didLoad = true
        }
    }
}

private struct DiscoverNearbyEmptyWorkTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
            .background(Color.clear)
            .overlay {
                Text("No Work Attached")
                    .font(OnCutsFont.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
            .frame(width: 96, height: 96 * 16 / 9)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("No Work Attached")
    }
}

private struct DiscoverNearbyWorkTile: View {
    let item: OperatorPortfolioItem

    var body: some View {
        ZStack {
            AsyncImage(url: item.tileURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.primary.opacity(0.06)
                }
            }
            if item.isVideo {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.45), in: Circle())
            }
        }
        .frame(width: 96, height: 96 * 16 / 9)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

enum DiscoverNearbyCopy {
    static func distanceLabel(for provider: ServiceProvider) -> String? {
        guard let miles = provider.distanceMilesFromUser, miles >= 0, miles.isFinite else { return nil }
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return String(format: "%.0f mi", miles)
    }

    static func priceRangeLabel(for provider: ServiceProvider) -> String? {
        guard let range = provider.priceRange, range.max > 0 || range.min > 0 else { return nil }
        return range.displayLabel
    }

    static func convenienceLine(for provider: ServiceProvider) -> String {
        let time = MyBarbersDiscover.nextOpenDisplayString(for: provider)
        if let distance = distanceLabel(for: provider) {
            return "\(distance) · \(time)"
        }
        return time
    }

    static func pinCaption(for provider: ServiceProvider) -> String {
        let time = compactPinTime(MyBarbersDiscover.nextOpenDisplayString(for: provider))
        if let price = priceRangeLabel(for: provider) {
            return "\(time) · \(price)"
        }
        return time
    }

    static func accessibilityLabel(for provider: ServiceProvider) -> String {
        var parts = [provider.businessName, provider.providerKindDisplayName, convenienceLine(for: provider)]
        if let price = priceRangeLabel(for: provider) {
            parts.append(price)
        }
        return parts.joined(separator: ", ")
    }

    /// Pin leads with the clock ("5:00pm · $30"), not the weekday.
    static func compactPinTime(_ display: String) -> String {
        let lower = display.lowercased()
        if lower.hasPrefix("open now") { return "Now" }
        let parts = display.split(separator: " ")
        if let last = parts.last {
            let token = String(last)
            let clock = token.lowercased()
            if clock.contains(":") || clock.hasSuffix("am") || clock.hasSuffix("pm") {
                return token
            }
        }
        return display
    }
}
