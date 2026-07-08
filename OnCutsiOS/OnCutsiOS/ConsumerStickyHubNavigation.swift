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
    /// Expanded rail height (reference for layout).
    static let chromeHeight: CGFloat = 54
    /// Collapsed rail height when the user scrolls down.
    static let minimizedChromeHeight: CGFloat = 38
    /// Vertical scroll (points) to fully collapse the overlay bar.
    static let collapseScrollDistance: CGFloat = 72
    /// Extra scroll content padding so the last row clears the floating bar.
    static let overlayContentBottomPadding: CGFloat = 76

    static func overlayContentBottomInset(collapseProgress: CGFloat) -> CGFloat {
        let expanded = overlayContentBottomPadding
        let collapsed = minimizedChromeHeight + 16
        return expanded - (expanded - collapsed) * min(1, max(0, collapseProgress))
    }
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

/// Tracks vertical scroll from hub tab content to collapse the floating navigation rail.
struct InteraHubBarScrollOffsetHandler {
    /// `pageIndex` matches hub `TabView` tags: 0 Home, 1 Messages, 2 Bookings, 3 Profile.
    var onOffsetChange: ((Int, CGFloat) -> Void)? = nil
    /// UIKit resync after hub tab switches — only realigns the delta baseline (see ``InteraHubBarCollapseController/resyncLastOffsetY``).
    var onResyncLastSample: ((Int, CGFloat) -> Void)? = nil
}

private struct InteraHubBarScrollOffsetHandlerKey: EnvironmentKey {
    static let defaultValue = InteraHubBarScrollOffsetHandler()
}

extension EnvironmentValues {
    var interaHubBarScrollOffsetHandler: InteraHubBarScrollOffsetHandler {
        get { self[InteraHubBarScrollOffsetHandlerKey.self] }
        set { self[InteraHubBarScrollOffsetHandlerKey.self] = newValue }
    }
}

private struct InteraHubBarOverlayBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Bottom padding for scroll content so rows clear the floating hub selector.
    var interaHubBarOverlayBottomInset: CGFloat {
        get { self[InteraHubBarOverlayBottomInsetKey.self] }
        set { self[InteraHubBarOverlayBottomInsetKey.self] = newValue }
    }
}

extension View {
    /// Reports vertical scroll offset to the hub bar collapse logic (iOS 18+).
    func interaHubBarScrollOffsetReporting(pageIndex: Int) -> some View {
        modifier(InteraHubBarScrollOffsetReporter(pageIndex: pageIndex))
    }

    /// Reads ``EnvironmentValues/interaHubBarOverlayBottomInset`` when wired from the hub shell.
    func interaHubBarScrollContentBottomInset() -> some View {
        modifier(InteraHubBarScrollContentBottomInsetModifier())
    }
}

private struct InteraHubBarScrollOffsetReporter: ViewModifier {
    let pageIndex: Int
    @Environment(\.interaHubBarScrollOffsetHandler) private var hubBarScrollHandler

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

private struct InteraHubBarScrollContentBottomInsetModifier: ViewModifier {
    @Environment(\.interaHubBarOverlayBottomInset) private var hubBarOverlayBottomInset

    func body(content: Content) -> some View {
        content.padding(.bottom, hubBarOverlayBottomInset)
    }
}

// MARK: - Collapse controller

enum InteraHubBarCollapseController {
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

    /// UIKit scroll bridge + cream bubble driver (no SwiftUI layout during page swipes).
    #if os(iOS)
    var pagingCoordinator: HubPagingCoordinator
    #endif

    let unreadMessageCount: Int
    let upcomingBookingCount: Int

    /// `animated` selects instant vs animated hub change in the parent (`navigateHubPage`).
    let onNavigateToPage: (Int, Bool) -> Void

    /// During a programmatic snap, bubble tracks selection instead of a stale paging offset.
    var bubbleAnchoredToPageIndex: Bool = false
    /// 0 = fully expanded overlay; 1 = minimized while scrolling down page content.
    var collapseProgress: CGFloat = 0
    /// When `true`, hub scroll observation is suppressed in the parent to avoid `TabView` flicker during bubble drag.
    @Binding var isHubBubbleDragging: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    @State private var isDraggingHubBubble = false
    /// Visual “caught” state — squeeze + cream shadow while finger is on the rail drag.
    @State private var isDragging = false
    @State private var lastHapticTabDuringDrag: Int = -1
    @State private var tapFlightWidthScale: CGFloat = 1
    /// Throttled from UIKit scroll KVO — drives icon active tint only (not bubble layout).
    @State private var iconScrollProgress: CGFloat = 0

    private static let hubNavigateSpring = Animation.spring(response: 0.4, dampingFraction: 0.7)

    private static let centerAlignmentSlop: CGFloat = 0.22
    /// Minimum movement before a drag competes with taps (keeps icon buttons reliable).
    private static let dragMinimumDistance: CGFloat = 12

    private func bubbleMetrics(w: CGFloat, h: CGFloat) -> (segmentW: CGFloat, baseW: CGFloat) {
        let segmentW = w / 4
        let baseW = max(40, segmentW * 0.82)
        return (segmentW, baseW)
    }

    private func bubbleCenterX(segmentW: CGFloat) -> CGFloat {
        #if os(iOS)
        if pagingCoordinator.isUserScrolling {
            let p = CGFloat(hubPageIndex)
            return p * segmentW + segmentW / 2
        }
        if isDraggingHubBubble {
            let clamped = min(3, max(0, iconScrollProgress))
            return clamped * segmentW + segmentW / 2
        }
        #endif
        let p = CGFloat(hubPageIndex)
        return p * segmentW + segmentW / 2
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
        #if os(iOS)
        let metrics = HubBubbleLayout.metrics(
            railWidth: segmentW * 4,
            railHeight: 44,
            progress: clamped,
            widthScale: tapFlightWidthScale
        )
        let bubbleW = metrics.frame.width
        let bubbleCenterX = metrics.centerX
        let bubbleLeading = metrics.frame.minX
        #else
        let bubbleW = baseW * tapFlightWidthScale
        let bubbleCenterX = clamped * segmentW + segmentW / 2
        let bubbleLeading = bubbleCenterX - bubbleW / 2
        #endif
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
        hubBarChrome
            .scaleEffect(1.0 - 0.12 * collapseProgress, anchor: .center)
            .offset(y: 22 * collapseProgress)
            .opacity(1.0 - 0.22 * collapseProgress)
            .shadow(color: .black.opacity(0.18 * (1.0 - collapseProgress * 0.35)), radius: 14, y: 4)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: collapseProgress)
        #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            isDraggingHubBubble = false
            isDragging = false
            isHubBubbleDragging = false
            lastHapticTabDuringDrag = -1
            tapFlightWidthScale = 1
            pagingCoordinator.tapFlightWidthScale = 1
            pagingCoordinator.manualDragProgress = nil
        }
        .onChange(of: hubPageIndex) { _, new in
            iconScrollProgress = CGFloat(new)
            #if os(iOS)
            pagingCoordinator.animateBubbleToPage(new, animated: false)
            #endif
        }
        .onChange(of: bubbleAnchoredToPageIndex) { _, anchored in
            pagingCoordinator.bubbleAnchoredToPageIndex = anchored
        }
        .onChange(of: tapFlightWidthScale) { _, scale in
            pagingCoordinator.tapFlightWidthScale = scale
            pagingCoordinator.refreshBubbleLayout(animated: false)
        }
        #endif
    }

    /// Glass pill + icons + selection bubble — collapsed as one unit (background must not outlive icon scale).
    private var hubBarChrome: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let metrics = bubbleMetrics(w: w, h: h)
            let segmentW = metrics.segmentW
            let centerX = bubbleCenterX(segmentW: segmentW)

            ZStack(alignment: .topLeading) {
                #if os(iOS)
                HubBubbleUIKitHost(
                    coordinator: pagingCoordinator,
                    railWidth: w,
                    railHeight: h,
                    visualScale: isDragging ? 0.9 : 1,
                    dragGlow: isDragging
                )
                #else
                let macBubble = HubBubbleLayout.metrics(
                    railWidth: w,
                    railHeight: h,
                    progress: CGFloat(hubPageIndex)
                )
                RoundedRectangle(cornerRadius: macBubble.cornerRadius, style: .continuous)
                    .fill(Color.interaNavigationHubCream)
                    .frame(width: macBubble.frame.width, height: macBubble.frame.height)
                    .offset(x: macBubble.frame.minX, y: macBubble.frame.minY)
                    .allowsHitTesting(false)
                #endif

                HStack(spacing: 0) {
                    hubSegment(
                        index: 0,
                        systemName: "house.fill",
                        label: "Home",
                        segmentW: segmentW,
                        bubbleCenterX: centerX,
                        badgeCount: 0,
                        badgeKind: .none
                    )
                    hubSegment(
                        index: 1,
                        systemName: "bubble.left.and.bubble.right.fill",
                        label: "Messages",
                        segmentW: segmentW,
                        bubbleCenterX: centerX,
                        badgeCount: unreadMessageCount,
                        badgeKind: .messages
                    )
                    hubSegment(
                        index: 2,
                        systemName: "calendar.badge.clock",
                        label: "Bookings",
                        segmentW: segmentW,
                        bubbleCenterX: centerX,
                        badgeCount: upcomingBookingCount,
                        badgeKind: .bookings
                    )
                    hubSegment(
                        index: 3,
                        systemName: "person.fill",
                        label: "Profile",
                        segmentW: segmentW,
                        bubbleCenterX: centerX,
                        badgeCount: 0,
                        badgeKind: .none
                    )
                }
                .frame(width: w, height: h)
            }
            .frame(width: w, height: h)
            .coordinateSpace(name: ConsumerStickyHubRailSpace.rail)
            .contentShape(Rectangle())
            .onAppear {
                #if os(iOS)
                iconScrollProgress = CGFloat(hubPageIndex)
                pagingCoordinator.hubPageIndex = hubPageIndex
                pagingCoordinator.bubbleAnchoredToPageIndex = bubbleAnchoredToPageIndex
                pagingCoordinator.tapFlightWidthScale = tapFlightWidthScale
                pagingCoordinator.bubbleVisualScale = isDragging ? 0.9 : 1
                pagingCoordinator.bubbleDragGlow = isDragging
                pagingCoordinator.onScrollSettled = { progress in
                    iconScrollProgress = progress
                }
                pagingCoordinator.onIconScrollProgress = { progress in
                    iconScrollProgress = progress
                }
                pagingCoordinator.syncBubbleAfterHubBarMount(page: hubPageIndex)
                #endif
            }
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
                            lastHapticTabDuringDrag = tabIndexForBubbleOverlap(
                                clampedProgress: iconScrollProgress,
                                segmentW: segmentW,
                                baseW: metrics.baseW
                            )
                            isDraggingHubBubble = true
                        }
                        let railProgress = progressFromRailLocationX(value.location.x, railWidth: w)
                        #if os(iOS)
                        pagingCoordinator.manualDragProgress = railProgress
                        pagingCoordinator.bubbleVisualScale = 0.9
                        pagingCoordinator.bubbleDragGlow = true
                        pagingCoordinator.refreshBubbleLayout(animated: false)
                        #endif
                        iconScrollProgress = railProgress
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
                            #if os(iOS)
                            pagingCoordinator.manualDragProgress = nil
                            pagingCoordinator.bubbleVisualScale = 1
                            pagingCoordinator.bubbleDragGlow = false
                            #endif
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
        .frame(height: 44 - 8 * collapseProgress)
        .padding(.horizontal, 10 - 3 * collapseProgress)
        .padding(.vertical, 5 - 2 * collapseProgress)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: collapseProgress)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.interaShellGlassStroke, lineWidth: 1)
        }
    }

    private func iconIsDeepCharcoal(index: Int, bubbleCenterX: CGFloat, segmentW: CGFloat) -> Bool {
        #if os(iOS)
        // Only crossfade from bubble overlap while swiping pages or dragging the rail; otherwise pin to selection
        // so utility-pill search / layout passes cannot snap `iconScrollProgress` and invert icon colors.
        if !isDraggingHubBubble && !pagingCoordinator.isUserScrolling {
            return index == hubPageIndex
        }
        #endif
        guard segmentW > 8 else { return index == hubPageIndex }
        let segmentCenterX = CGFloat(index) * segmentW + segmentW / 2
        return abs(bubbleCenterX - segmentCenterX) <= segmentW * Self.centerAlignmentSlop
    }

    private enum HubSegmentBadgeKind {
        case none
        case messages
        case bookings
    }

    @ViewBuilder
    private func hubSegment(
        index: Int,
        systemName: String,
        label: String,
        segmentW: CGFloat,
        bubbleCenterX: CGFloat,
        badgeCount: Int,
        badgeKind: HubSegmentBadgeKind
    ) -> some View {
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
        .frame(width: segmentW)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel(for: label, badgeCount: badgeCount, badgeKind: badgeKind))
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

#if os(iOS)
// HubBubbleUIKitHost + HubPagingCoordinator live in HubPagingCoordinator.swift
#endif
