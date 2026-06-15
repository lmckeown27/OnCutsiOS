//
//  ConsumerStickyHubNavigation.swift
//  Intera
//
//  Hub rail: cream bubble tracks `TabView` scroll, animates on tab taps, and can be dragged horizontally
//  with haptics; icons flip to deep charcoal when the bubble centers on that segment.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum ConsumerStickyHubMetrics {
    /// Vertical size of the hub rail + outer padding (for `safeAreaInset` / layout).
    static let chromeHeight: CGFloat = 54
}

/// Named coordinate space for mapping finger position → tab progress on the rail.
private enum ConsumerStickyHubRailSpace {
    static let rail = "consumerStickyHubRail"
}

extension Color {
    /// Mercury bubble fill on the hub rail (cream in dark mode, black in light mode).
    static var interaNavigationHubCream: Color {
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
    static var interaHubDeepCharcoal: Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.14, green: 0.13, blue: 0.12, alpha: 1)
                : .white
        })
        #else
        Color.interaShellBackground
        #endif
    }
    /// Inactive hub icons (cream in dark mode, muted black in light mode).
    static var interaNavigationHubIconInactive: Color {
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

// MARK: - Tab notification node (8pt dot, cream vs charcoal + pulse)

/// Small circular indicator for unread / pending hub items; pairs with `ConsumerStickyHubBar` Mercury bubble or glass toolbar icons.
struct InteraTabNotificationNode: View {
    /// When `true`, the hub segment is under the Mercury bubble (active tab) — node uses deep charcoal; otherwise solid cream.
    let isTabActive: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Circle()
            .fill(isTabActive ? Color.interaHubDeepCharcoal : Color.interaNavigationHubIconInactive)
            .frame(width: 8, height: 8)
            .modifier(InteraNotificationNodePulseModifier(reduceMotion: accessibilityReduceMotion))
    }
}

private struct InteraNotificationNodePulseModifier: ViewModifier {
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

// MARK: - Floating glass rail

struct ConsumerStickyHubBar: View {
    /// 0 = Home, 1 = Messages, 2 = Bookings, 3 = Profile — bound to the main hub `TabView`.
    @Binding var hubPageIndex: Int

    let unreadMessageCount: Int
    let upcomingBookingCount: Int

    /// `animated` selects instant vs animated hub change in the parent (`navigateHubPage`).
    let onNavigateToPage: (Int, Bool) -> Void

    /// Horizontal `contentOffset.x` from the hub `TabView`’s paging `UIScrollView` (see `HubPagingScrollOffsetReader`).
    var tabScrollOffsetX: CGFloat = 0
    /// Width of one page in that scroll view (viewport width). When &lt; 1, falls back to `hubPageIndex`.
    var tabPageWidth: CGFloat = 0
    /// During a programmatic snap, bubble tracks selection instead of a stale paging offset.
    var bubbleAnchoredToPageIndex: Bool = false
    /// When `true`, hub scroll observation is suppressed in the parent to avoid `TabView` flicker during bubble drag.
    @Binding var isHubBubbleDragging: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    @State private var isDraggingHubBubble = false
    /// Visual “caught” state — squeeze + cream shadow while finger is on the rail drag.
    @State private var isDragging = false
    @State private var dragProgress: CGFloat = 0
    @State private var lastHapticTabDuringDrag: Int = -1
    @State private var tapFlightWidthScale: CGFloat = 1

    private static let hubNavigateSpring = Animation.spring(response: 0.4, dampingFraction: 0.7)
    /// Matches `navigateHubPage` / tab tap when scroll metrics are not live yet.
    private static let hubSnapSpring = Animation.spring(response: 0.4, dampingFraction: 0.7)

    private static let bubbleStretch: CGFloat = 1.2
    private static let centerAlignmentSlop: CGFloat = 0.22
    /// Minimum movement before a drag competes with taps (keeps icon buttons reliable).
    private static let dragMinimumDistance: CGFloat = 12

    private var usesLiveScroll: Bool { tabPageWidth > 1 }

    /// Progress 0…3 from `TabView` scroll / selection only (no drag override).
    private func baseScrollProgress() -> CGFloat {
        if bubbleAnchoredToPageIndex && !isDraggingHubBubble {
            return CGFloat(hubPageIndex)
        }
        if usesLiveScroll {
            let p = tabScrollOffsetX / tabPageWidth
            let pClamped = min(3, max(0, p))
            // After programmatic navigation (notification, deep link), the paging `UIScrollView` can
            // still report the previous page’s offset while `hubPageIndex` is already updated — the
            // bubble would sit on the wrong segment and feel inert. If offset is snapped near an
            // integer page but disagrees with `hubPageIndex`, trust selection.
            let nearest = pClamped.rounded(.toNearestOrAwayFromZero)
            // Slightly wider slop: during pager settle the scroll view can sit just off an integer
            // while `hubPageIndex` is already updated — a tight threshold made the cream bubble jitter.
            if !isDraggingHubBubble,
               Int(nearest) != hubPageIndex,
               abs(pClamped - nearest) < 0.10 {
                return CGFloat(hubPageIndex)
            }
            return pClamped
        }
        return CGFloat(hubPageIndex)
    }

    /// Bubble horizontal position: drag overrides scroll/index.
    private func effectiveBubbleProgress() -> CGFloat {
        if isDraggingHubBubble {
            return dragProgress
        }
        return baseScrollProgress()
    }

    private func bubbleMetrics(w: CGFloat, h: CGFloat) -> (segmentW: CGFloat, baseW: CGFloat, bubbleH: CGFloat, bubbleY: CGFloat) {
        let segmentW = w / 4
        let baseW = max(40, segmentW * 0.82)
        let bubbleH = min(h * 0.78, h - 4)
        let bubbleY = (h - bubbleH) / 2
        return (segmentW, baseW, bubbleH, bubbleY)
    }

    /// Maps normalized x in rail [0, width] → progress 0…3 (matches `location.x / width * 3` for four segments).
    private func progressFromRailLocationX(_ x: CGFloat, railWidth: CGFloat) -> CGFloat {
        guard railWidth > 1 else { return CGFloat(hubPageIndex) }
        let clampedX = min(railWidth, max(0, x))
        return min(3, max(0, (clampedX / railWidth) * 3))
    }

    /// Picks the tab whose segment has the largest horizontal overlap with the bubble; any positive overlap counts toward that tab.
    private func tabIndexForBubbleOverlap(clampedProgress: CGFloat, segmentW: CGFloat, baseW: CGFloat) -> Int {
        let clamped = min(3, max(0, clampedProgress))
        let nearestPage = clamped.rounded(.toNearestOrAwayFromZero)
        let isBetweenPages = abs(clamped - nearestPage) > 0.004
        let widthScale: CGFloat = isBetweenPages ? Self.bubbleStretch : 1
        let bubbleW = baseW * widthScale * tapFlightWidthScale
        let bubbleCenterX = clamped * segmentW + segmentW / 2
        let bubbleLeading = bubbleCenterX - bubbleW / 2
        let bubbleTrailing = bubbleLeading + bubbleW

        var overlaps: [CGFloat] = []
        overlaps.reserveCapacity(4)
        for i in 0 ..< 4 {
            let tabL = CGFloat(i) * segmentW
            let tabR = CGFloat(i + 1) * segmentW
            overlaps.append(max(0, min(bubbleTrailing, tabR) - max(bubbleLeading, tabL)))
        }
        guard let maxOverlap = overlaps.max(), maxOverlap > 0 else {
            return min(3, max(0, Int(round(clamped))))
        }
        let tied = (0 ..< 4).filter { overlaps[$0] >= maxOverlap - 0.001 }
        if tied.count == 1 { return tied[0] }
        return tied.min(by: { a, b in
            let ca = CGFloat(a) * segmentW + segmentW / 2
            let cb = CGFloat(b) * segmentW + segmentW / 2
            return abs(bubbleCenterX - ca) < abs(bubbleCenterX - cb)
        })!
    }

    private func handleTabTap(index: Int) {
        guard !isDraggingHubBubble else { return }
        guard index != hubPageIndex else { return }
        let from = hubPageIndex
        let multiJump = abs(index - from) > 1
        if accessibilityReduceMotion {
            tapFlightWidthScale = 1
            onNavigateToPage(index, false)
            return
        }
        // Bubble “flight” width on multi-hop taps; parent `navigateHubPage` snaps multi-hop / rapid hops.
        if multiJump {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                tapFlightWidthScale = 1.3
            }
            withAnimation(Self.hubNavigateSpring) {
                tapFlightWidthScale = 1
            }
        }
        // Icon taps always snap the pager instantly; bubble motion is handled in `navigateHubPage`.
        onNavigateToPage(index, false)
    }

    #if os(iOS)
    private static let selectionFeedback = UISelectionFeedbackGenerator()
    #endif

    private func prepareDragHaptics() {
        #if os(iOS)
        Self.selectionFeedback.prepare()
        #endif
    }

    private func fireCrossingHaptic() {
        #if os(iOS)
        Self.selectionFeedback.selectionChanged()
        Self.selectionFeedback.prepare()
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let metrics = bubbleMetrics(w: w, h: h)
            let segmentW = metrics.segmentW
            let progress = effectiveBubbleProgress()
            let nearestPage = progress.rounded(.toNearestOrAwayFromZero)
            let isBetweenPages = abs(progress - nearestPage) > 0.004
            let widthScale: CGFloat = isBetweenPages ? Self.bubbleStretch : 1
            let bubbleW = metrics.baseW * widthScale * tapFlightWidthScale
            let bubbleCenterX = progress * segmentW + segmentW / 2
            let bubbleLeading = bubbleCenterX - bubbleW / 2
            let bubbleVisualScale: CGFloat = isDragging ? 0.9 : 1

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: metrics.bubbleH / 2, style: .continuous)
                    .fill(Color.interaNavigationHubCream)
                    .frame(width: bubbleW, height: metrics.bubbleH)
                    .scaleEffect(bubbleVisualScale)
                    .shadow(
                        color: isDragging ? Color.interaNavigationHubCream.opacity(0.85) : .clear,
                        radius: isDragging ? 10 : 0,
                        y: 0
                    )
                    .offset(x: bubbleLeading, y: metrics.bubbleY)
                    .modifier(BubbleIndexAnimationModifier(
                        enabled: !usesLiveScroll && !isDraggingHubBubble,
                        spring: Self.hubSnapSpring,
                        hubPageIndex: hubPageIndex
                    ))
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    hubSegment(
                        index: 0,
                        systemName: "house.fill",
                        label: "Home",
                        bubbleCenterX: bubbleCenterX,
                        badgeCount: 0,
                        badgeKind: .none
                    )
                    hubSegment(
                        index: 1,
                        systemName: "bubble.left.and.bubble.right.fill",
                        label: "Messages",
                        bubbleCenterX: bubbleCenterX,
                        badgeCount: unreadMessageCount,
                        badgeKind: .messages
                    )
                    hubSegment(
                        index: 2,
                        systemName: "calendar.badge.clock",
                        label: "Bookings",
                        bubbleCenterX: bubbleCenterX,
                        badgeCount: upcomingBookingCount,
                        badgeKind: .bookings
                    )
                    hubSegment(
                        index: 3,
                        systemName: "person.fill",
                        label: "Profile",
                        bubbleCenterX: bubbleCenterX,
                        badgeCount: 0,
                        badgeKind: .none
                    )
                }
                .frame(width: w, height: h)
            }
            .frame(width: w, height: h)
            .coordinateSpace(name: ConsumerStickyHubRailSpace.rail)
            .contentShape(Rectangle())
            // Simultaneous (not high-priority) so icon `Button`s receive taps immediately while drags
            // still win once movement exceeds `dragMinimumDistance`.
            .simultaneousGesture(
                DragGesture(minimumDistance: Self.dragMinimumDistance, coordinateSpace: .named(ConsumerStickyHubRailSpace.rail))
                    .onChanged { value in
                        if !isHubBubbleDragging {
                            isHubBubbleDragging = true
                        }
                        if !isDragging {
                            isDragging = true
                        }
                        if !isDraggingHubBubble {
                            prepareDragHaptics()
                            let anchor = baseScrollProgress()
                            lastHapticTabDuringDrag = tabIndexForBubbleOverlap(
                                clampedProgress: anchor,
                                segmentW: segmentW,
                                baseW: metrics.baseW
                            )
                            isDraggingHubBubble = true
                        }
                        let railProgress = progressFromRailLocationX(value.location.x, railWidth: w)
                        withAnimation(.interactiveSpring()) {
                            dragProgress = railProgress
                        }
                        let dominantTab = tabIndexForBubbleOverlap(clampedProgress: railProgress, segmentW: segmentW, baseW: metrics.baseW)
                        if dominantTab != lastHapticTabDuringDrag {
                            lastHapticTabDuringDrag = dominantTab
                            fireCrossingHaptic()
                        }
                    }
                    .onEnded { value in
                        defer {
                            isHubBubbleDragging = false
                            isDragging = false
                        }
                        guard isDraggingHubBubble else { return }
                        let railProgress = progressFromRailLocationX(value.location.x, railWidth: w)
                        let snapped = tabIndexForBubbleOverlap(clampedProgress: railProgress, segmentW: segmentW, baseW: metrics.baseW)
                        isDraggingHubBubble = false
                        lastHapticTabDuringDrag = -1
                        onNavigateToPage(snapped, false)
                    }
            )
        }
        .frame(height: 44)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.interaShellGlassStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Incomplete drag gestures after backgrounding can leave local + parent drag flags set.
            isDraggingHubBubble = false
            isDragging = false
            isHubBubbleDragging = false
            lastHapticTabDuringDrag = -1
            tapFlightWidthScale = 1
        }
        #endif
    }

    private func iconIsDeepCharcoal(index: Int, bubbleCenterX: CGFloat, segmentW: CGFloat) -> Bool {
        let segmentCenterX = CGFloat(index) * segmentW + segmentW / 2
        return abs(bubbleCenterX - segmentCenterX) <= segmentW * Self.centerAlignmentSlop
    }

    private enum HubSegmentBadgeKind {
        case none
        case messages
        case bookings
    }

    private func hubSegment(
        index: Int,
        systemName: String,
        label: String,
        bubbleCenterX: CGFloat,
        badgeCount: Int,
        badgeKind: HubSegmentBadgeKind
    ) -> some View {
        GeometryReader { segGeo in
            let segmentW = segGeo.size.width
            let h = segGeo.size.height
            let tabActive = iconIsDeepCharcoal(index: index, bubbleCenterX: bubbleCenterX, segmentW: segmentW)
            let showNotificationNode = badgeCount > 0 && (badgeKind == .messages || badgeKind == .bookings)
            Button {
                handleTabTap(index: index)
            } label: {
                Image(systemName: systemName)
                    .font(InteraFont.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        tabActive
                            ? Color.interaHubDeepCharcoal
                            : Color.interaNavigationHubIconInactive
                    )
                    .overlay(alignment: .topTrailing) {
                        if showNotificationNode {
                            InteraTabNotificationNode(isTabActive: tabActive)
                                .offset(x: 5, y: -5)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel(for: label, badgeCount: badgeCount, badgeKind: badgeKind))
        }
    }

    private func accessibilityLabel(for title: String, badgeCount: Int, badgeKind: HubSegmentBadgeKind) -> String {
        guard badgeCount > 0 else { return title }
        switch badgeKind {
        case .none:
            return title
        case .messages:
            return "\(title), \(badgeCount) unread"
        case .bookings:
            return "\(title), \(badgeCount) upcoming"
        }
    }
}

private struct BubbleIndexAnimationModifier: ViewModifier {
    let enabled: Bool
    let spring: Animation
    let hubPageIndex: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.animation(spring, value: hubPageIndex)
        } else {
            content
        }
    }
}
