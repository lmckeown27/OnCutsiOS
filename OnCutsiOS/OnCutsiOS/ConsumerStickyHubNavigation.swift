//
//  ConsumerStickyHubNavigation.swift
//  OnCuts
//
//  Hub tab bar: full-width bar with outlined icons that fill when selected; pages still swipe.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum ConsumerStickyHubMetrics {
    /// Tab bar height above the home indicator.
    static let chromeHeight: CGFloat = 49
    /// Space between the icon row and the home indicator.
    static let iconRowBottomLift: CGFloat = 20
    /// Vertical scroll (points) to fully collapse the guest sign-in bar.
    static let collapseScrollDistance: CGFloat = 72
    /// Scroll content padding so the last row clears the tab bar.
    static let overlayContentBottomPadding: CGFloat = chromeHeight + iconRowBottomLift
}

/// Named coordinate space for mapping finger position → tab progress on the rail.
private enum ConsumerStickyHubRailSpace {
    static let rail = "consumerStickyHubRail"
}

/// Shared bubble geometry for UIKit follower + icon overlap (platform-agnostic).
enum HubBubbleLayout {
    static let stretch: CGFloat = 1.2

    struct Metrics {
        let frame: CGRect
        let centerX: CGFloat
        let cornerRadius: CGFloat
    }

    static func metrics(
        railWidth: CGFloat,
        railHeight: CGFloat,
        progress: CGFloat,
        widthScale: CGFloat = 1
    ) -> Metrics {
        let segmentW = railWidth / 4
        let baseW = max(40, segmentW * 0.82)
        let bubbleH = min(railHeight * 0.78, railHeight - 4)
        let bubbleY = (railHeight - bubbleH) / 2
        let clamped = min(3, max(0, progress))
        let nearestPage = clamped.rounded(.toNearestOrAwayFromZero)
        let isBetweenPages = abs(clamped - nearestPage) > 0.004
        let stretchScale: CGFloat = isBetweenPages ? stretch : 1
        let bubbleW = baseW * stretchScale * widthScale
        let bubbleCenterX = clamped * segmentW + segmentW / 2
        let bubbleLeading = bubbleCenterX - bubbleW / 2
        return Metrics(
            frame: CGRect(x: bubbleLeading, y: bubbleY, width: bubbleW, height: bubbleH),
            centerX: bubbleCenterX,
            cornerRadius: bubbleH / 2
        )
    }

    static func scrollProgress(offsetX: CGFloat, pageWidth: CGFloat) -> CGFloat {
        min(3, max(0, offsetX / max(1, pageWidth)))
    }
}

extension Color {
    /// Mercury bubble fill on the hub rail (cream in dark mode, black in light mode).
    static var onCutsNavigationHubCream: Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 245 / 255, green: 245 / 255, blue: 220 / 255, alpha: 1)
                : .black
        })
        #else
        Color.primary
        #endif
    }
    /// Icon on the bubble when that segment is active (charcoal on cream in dark, white on black in light).
    static var onCutsHubDeepCharcoal: Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.14, green: 0.13, blue: 0.12, alpha: 1)
                : .white
        })
        #else
        Color.onCutsShellBackground
        #endif
    }
    /// Inactive hub icons (cream in dark mode, muted black in light mode).
    static var onCutsNavigationHubIconInactive: Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 245 / 255, green: 245 / 255, blue: 220 / 255, alpha: 1)
                : UIColor.black.withAlphaComponent(0.55)
        })
        #else
        Color.secondary
        #endif
    }
}

/// Tracks vertical scroll from hub tab content to collapse the floating navigation rail.
struct OnCutsHubBarScrollOffsetHandler {
    /// Stable box the shell keeps in `@State`. SwiftUI diffs environment values field by field (ignoring `Equatable`),
    /// so fresh closures here would re-render every hub page on each shell render.
    final class Relay {
        var onOffsetChange: ((Int, CGFloat) -> Void)?
        var onResyncLastSample: ((Int, CGFloat) -> Void)?

        func updating(
            onOffsetChange: @escaping (Int, CGFloat) -> Void,
            onResyncLastSample: @escaping (Int, CGFloat) -> Void
        ) -> OnCutsHubBarScrollOffsetHandler {
            self.onOffsetChange = onOffsetChange
            self.onResyncLastSample = onResyncLastSample
            return OnCutsHubBarScrollOffsetHandler(relay: self)
        }
    }

    private var relay: Relay?

    /// `pageIndex` matches hub `TabView` tags: 0 Home, 1 Messages, 2 Bookings, 3 Profile.
    var onOffsetChange: ((Int, CGFloat) -> Void)? { relay?.onOffsetChange }
    /// UIKit resync after hub tab switches — only realigns the delta baseline (see ``OnCutsHubBarCollapseController/resyncLastOffsetY``).
    var onResyncLastSample: ((Int, CGFloat) -> Void)? { relay?.onResyncLastSample }

    init() {}

    private init(relay: Relay) {
        self.relay = relay
    }
}

extension OnCutsHubBarScrollOffsetHandler: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.relay === rhs.relay
    }
}

private struct OnCutsHubBarScrollOffsetHandlerKey: EnvironmentKey {
    static let defaultValue = OnCutsHubBarScrollOffsetHandler()
}

extension EnvironmentValues {
    var onCutsHubBarScrollOffsetHandler: OnCutsHubBarScrollOffsetHandler {
        get { self[OnCutsHubBarScrollOffsetHandlerKey.self] }
        set { self[OnCutsHubBarScrollOffsetHandlerKey.self] = newValue }
    }
}

private struct OnCutsHubBarOverlayBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Bottom padding for scroll content so rows clear the floating hub selector.
    var onCutsHubBarOverlayBottomInset: CGFloat {
        get { self[OnCutsHubBarOverlayBottomInsetKey.self] }
        set { self[OnCutsHubBarOverlayBottomInsetKey.self] = newValue }
    }
}

extension View {
    /// Reports vertical scroll offset to the hub bar collapse logic (iOS 18+).
    func onCutsHubBarScrollOffsetReporting(pageIndex: Int) -> some View {
        modifier(OnCutsHubBarScrollOffsetReporter(pageIndex: pageIndex))
    }

    /// Reads ``EnvironmentValues/onCutsHubBarOverlayBottomInset`` when wired from the hub shell.
    func onCutsHubBarScrollContentBottomInset() -> some View {
        modifier(OnCutsHubBarScrollContentBottomInsetModifier())
    }
}

private struct OnCutsHubBarScrollOffsetReporter: ViewModifier {
    let pageIndex: Int
    @Environment(\.onCutsHubBarScrollOffsetHandler) private var hubBarScrollHandler

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, newValue in
                hubBarScrollHandler.onOffsetChange?(pageIndex, newValue)
            }
        } else {
            content
        }
    }
}

private struct OnCutsHubBarScrollContentBottomInsetModifier: ViewModifier {
    @Environment(\.onCutsHubBarOverlayBottomInset) private var hubBarOverlayBottomInset

    func body(content: Content) -> some View {
        content.padding(.bottom, hubBarOverlayBottomInset)
    }
}

// MARK: - Collapse controller

enum OnCutsHubBarCollapseController {
    @MainActor
    static func update(
        progress: inout CGFloat,
        lastOffsetY: inout CGFloat,
        offsetY: CGFloat
    ) {
        let delta = offsetY - lastOffsetY
        lastOffsetY = offsetY

        if offsetY <= 4 {
            progress = 0
            return
        }

        let step = ConsumerStickyHubMetrics.collapseScrollDistance
        if delta > 0.5 {
            progress = min(1, progress + delta / step)
        } else if delta < -0.5 {
            progress = max(0, progress + delta / step)
        }
    }

    /// After hub tab switches, SwiftUI scroll geometry can stay stale — resync the delta baseline without moving progress.
    @MainActor
    static func resyncLastOffsetY(lastOffsetY: inout CGFloat, offsetY: CGFloat) {
        lastOffsetY = offsetY
    }
}

// MARK: - Tab notification node (8pt dot, cream vs charcoal + pulse)

/// Small circular indicator for unread / pending hub items; pairs with `ConsumerStickyHubBar` Mercury bubble or glass toolbar icons.
struct OnCutsTabNotificationNode: View {
    /// When `true`, the hub segment is under the Mercury bubble (active tab) — node uses deep charcoal; otherwise solid cream.
    let isTabActive: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Circle()
            .fill(isTabActive ? Color.onCutsHubDeepCharcoal : Color.onCutsNavigationHubIconInactive)
            .frame(width: 8, height: 8)
            .modifier(OnCutsNotificationNodePulseModifier(reduceMotion: accessibilityReduceMotion))
    }
}

private struct OnCutsNotificationNodePulseModifier: ViewModifier {
    let reduceMotion: Bool
    @State private var pulseBright = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1.0 : (pulseBright ? 1.0 : 0.6))
            .onAppear {
                guard !reduceMotion else { return }
                pulseBright = false
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                    pulseBright = true
                }
            }
    }
}

// MARK: - Tab bar

/// Full-width bottom bar: outlined icons, filled when selected, profile photo on the Profile tab.
struct ConsumerStickyHubBar: View {
    /// 0 = Home, 1 = Messages, 2 = Bookings, 3 = Profile — bound to the main hub `TabView`.
    @Binding var hubPageIndex: Int

    #if os(iOS)
    var pagingCoordinator: HubPagingCoordinator
    #endif

    let unreadMessageCount: Int
    let upcomingBookingCount: Int
    var profileImageURL: URL? = nil

    /// `animated` selects instant vs animated hub change in the parent (`navigateHubPage`).
    let onNavigateToPage: (Int, Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(index: 0, label: "Home", badgeCount: 0, badgeNoun: nil) { selected in
                symbol(selected ? "house.fill" : "house", selected: selected)
            }
            tab(index: 1, label: "Messages", badgeCount: unreadMessageCount, badgeNoun: "unread") { selected in
                symbol(selected ? "message.fill" : "message", selected: selected)
            }
            tab(index: 2, label: "Bookings", badgeCount: upcomingBookingCount, badgeNoun: "upcoming") { selected in
                // No filled calendar glyph exists; the circle variant draws smaller, so weight marks selection instead.
                symbol("calendar", selected: selected)
            }
            tab(index: 3, label: "Profile", badgeCount: 0, badgeNoun: nil) { selected in
                ConsumerHubProfileTabAvatar(url: profileImageURL, isSelected: selected)
            }
        }
        .frame(height: ConsumerStickyHubMetrics.chromeHeight)
        .padding(.bottom, ConsumerStickyHubMetrics.iconRowBottomLift)
        .frame(maxWidth: .infinity)
        .background {
            Color.onCutsShellBackground
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
        }
    }

    private func symbol(_ name: String, selected: Bool) -> some View {
        Image(systemName: name)
            .font(OnCutsFont.system(size: 24, weight: selected ? .semibold : .regular))
            .foregroundStyle(Color.primary)
    }

    private func tab<Icon: View>(
        index: Int,
        label: String,
        badgeCount: Int,
        badgeNoun: String?,
        @ViewBuilder icon: (Bool) -> Icon
    ) -> some View {
        let selected = index == hubPageIndex
        return Button {
            guard index != hubPageIndex else { return }
            onNavigateToPage(index, false)
        } label: {
            icon(selected)
                .frame(width: 30, height: 30)
                .overlay(alignment: .topTrailing) {
                    if badgeCount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 3, y: -1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badgeCount > 0 && badgeNoun != nil ? "\(label), \(badgeCount) \(badgeNoun!)" : label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ConsumerHubProfileTabAvatar: View {
    let url: URL?
    let isSelected: Bool

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: isSelected ? "person.crop.circle.fill" : "person.crop.circle")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.primary)
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(Circle())
        .padding(2)
        .overlay {
            if isSelected {
                Circle().stroke(Color.primary, lineWidth: 1.5)
            }
        }
    }
}

