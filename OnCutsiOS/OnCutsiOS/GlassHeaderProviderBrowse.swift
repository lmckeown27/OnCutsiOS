//
//  GlassHeaderProviderBrowse.swift
//  OnCuts
//
//  Scrollable provider list with mesh backdrop and a top **glass capsule toolbar**
//  (service type, search, profile). Uses `.safeAreaInset(edge: .top)` for Dynamic Island / notch.
//

import OnCutsModule
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Search field styling (utility pill)

private let utilityPillSearchInputCharcoal = Color(red: 0.12, green: 0.12, blue: 0.14)
/// Primary typing style in the expanded utility-pill search field (larger / heavier than `.bodyMedium`).
private let utilityPillSearchInputFont = OnCutsFont.system(size: 19, weight: .semibold, design: .default)

#if os(iOS)
/// iPad: SwiftUI still sometimes leaves a default `UITextField` opaque fill on glass toolbars despite `.plain`.
private struct PadUtilityBrowseSearchTextFieldBackgroundClearer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let root = uiView.superview else { return }
            var budget = 80
            guard let tf = Self.firstTextField(in: root, budget: &budget) else { return }
            tf.backgroundColor = .clear
            tf.borderStyle = .none
            tf.subviews.forEach { $0.backgroundColor = .clear }
        }
    }

    private static func firstTextField(in view: UIView, budget: inout Int) -> UITextField? {
        guard budget > 0 else { return nil }
        budget -= 1
        if let tf = view as? UITextField { return tf }
        for sub in view.subviews {
            if let tf = Self.firstTextField(in: sub, budget: &budget) { return tf }
        }
        return nil
    }
}
#endif
/// Matches `TimelineSectionHeader` “Today” (28pt bold system).
private let utilityPillSearchProviderNameFont = OnCutsFont.system(size: 28, weight: .bold, design: .default)

// MARK: - Haptics

/// Snappy 0.95 scale on utility-pill segments (radius / tags only).
private struct UtilityPillPhysicalPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

private enum GlassCapsuleToolbarHaptics {
    #if os(iOS)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()

    static func lightTap() {
        light.prepare()
        light.impactOccurred()
    }

    /// Service type chip / segmented changes (OnCuts glass toolbar).
    static func selectionChanged() {
        selection.prepare()
        selection.selectionChanged()
    }
    #else
    static func lightTap() {}
    static func selectionChanged() {}
    #endif
}

// MARK: - Chrome styling

private extension View {
    /// Liquid-style rim + subtle inner highlight (no heavy drop shadow).
    func glassToolbarCapsuleStroke(activeGlow: Bool) -> some View {
        self
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.42), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.5),
                                .clear,
                                .black.opacity(0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            }
            .overlay {
                if activeGlow {
                    Capsule()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    .white.opacity(0.4),
                                    Color.oliveGreen.opacity(0.5),
                                    .white.opacity(0.28),
                                    Color.oliveGreen.opacity(0.4),
                                    .white.opacity(0.35),
                                ],
                                center: .center
                            ),
                            lineWidth: 1
                        )
                        .blur(radius: 0.75)
                        .allowsHitTesting(false)
                }
            }
    }

    /// Split-capsule chrome: frosted pill + 1pt white rim (consumer browse header).
    func splitCapsuleMaterialChrome() -> some View {
        self
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.95), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    /// Capsules that sit on top of the **global** header material — subtle tint + rim only (no second frost layer).
    func splitCapsuleOnGlobalHeaderChrome() -> some View {
        self
            .background {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            }
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.38), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }

    func glassToolbarCircleStroke() -> some View {
        self
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.42), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.48), .clear, .black.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    func optionalGlassToolbarCircleStroke(_ apply: Bool) -> some View {
        if apply {
            self.glassToolbarCircleStroke()
        } else {
            self
        }
    }
}

// MARK: - Profile avatar (session / platform photo)

private struct GlassToolbarProfileAvatarButton: View {
    let fallbackImageURL: URL?
    let onTap: () -> Void
    /// When `true`, the parent capsule already provides `.ultraThinMaterial` — skip duplicate frosted fill on the avatar.
    var useExternalMaterial: Bool = false

    /// Uses the app session only (`profile_picture_url` from the OnCuts API / uploaded photo). No Google or email-provider avatar fallback.
    private var resolvedURL: URL? {
        fallbackImageURL
    }

    var body: some View {
        Button {
            GlassCapsuleToolbarHaptics.lightTap()
            onTap()
        } label: {
            ZStack {
                if !useExternalMaterial {
                    Circle()
                        .fill(.ultraThinMaterial)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                }
                if let url = resolvedURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .scaleEffect(0.65)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            OnCutsDefaultProfileAvatarGlyph(slotDiameter: 40)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    OnCutsDefaultProfileAvatarGlyph(slotDiameter: 40)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(useExternalMaterial ? 0.35 : 0.2), lineWidth: 1)
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.38), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .padding(0.5)
                    .allowsHitTesting(false)
            }
            .optionalGlassToolbarCircleStroke(!useExternalMaterial)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
    }
}

// MARK: - Scroll offset (collapsing header)

extension Notification.Name {
    /// Posted when the hub pager lands on Home — browse re-reads vertical scroll + pill collapse state.
    static let homeHubBrowseShouldResyncUtilityPill = Notification.Name("homeHubBrowseShouldResyncUtilityPill")
}

@available(iOS 26.0, macOS 26.0, *)
private struct GlobalHeaderMeasuredHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Scroll samples bridged from `ScrollView` geometry — content offset for chrome collapse, pull stretch for refresh affordance.
@available(iOS 26.0, macOS 26.0, *)
private struct GlassBrowseScrollSample: Equatable {
    let contentOffsetY: CGFloat
    let pullRefreshStretch: CGFloat
}

/// Bridges `ScrollView`’s true content offset into the collapsing header logic. `GeometryReader` / named
/// coordinate spaces often **do not** update during scroll, so the header never hid.
@available(iOS 26.0, macOS 26.0, *)
private struct GlassBrowseScrollOffsetBridgeModifier: ViewModifier {
    let onSampleChange: (GlassBrowseScrollSample) -> Void

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: GlassBrowseScrollSample.self) { geo in
            let adjustedTop = geo.contentOffset.y + geo.contentInsets.top
            return GlassBrowseScrollSample(
                contentOffsetY: geo.contentOffset.y,
                pullRefreshStretch: max(0, -adjustedTop)
            )
        } action: { _, sample in
            onSampleChange(sample)
        }
    }
}

#if os(iOS)
/// Reads the hosting `UIScrollView` after hub tab switches — SwiftUI geometry can stay stale while Home is off-screen.
@available(iOS 26.0, *)
private struct HomeBrowseScrollResyncBridge: UIViewRepresentable {
    var resyncGeneration: Int
    var onSample: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSample: onSample) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.scheduleSample(from: uiView, generation: resyncGeneration)
    }

    final class Coordinator {
        let onSample: (CGFloat) -> Void
        private var lastGeneration = -1
        private var attempts = 0

        init(onSample: @escaping (CGFloat) -> Void) {
            self.onSample = onSample
        }

        func scheduleSample(from anchor: UIView, generation: Int) {
            guard generation != lastGeneration else { return }
            lastGeneration = generation
            attempts = 0
            trySample(from: anchor)
        }

        private func trySample(from anchor: UIView) {
            attempts += 1
            if let scroll = anchor.onCuts_enclosingVerticalScrollView() {
                onSample(max(0, scroll.contentOffset.y))
                return
            }
            guard attempts < 8 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self, weak anchor] in
                guard let self, let anchor else { return }
                self.trySample(from: anchor)
            }
        }
    }
}

@available(iOS 26.0, *)
private extension UIView {
    func onCuts_enclosingVerticalScrollView() -> UIScrollView? {
        var current: UIView? = self
        while let view = current {
            if let scroll = view as? UIScrollView,
               scroll.contentSize.height > scroll.bounds.height + 1 {
                return scroll
            }
            current = view.superview
        }
        return nil
    }
}
#endif

// MARK: - Constants

private enum GlassHeaderConstants {
    /// Minimum scroll distance (points) over which utility chrome goes from fully shown to hidden.
    static let chromeHideScrollRangeMinimum: CGFloat = 88
    /// Gap between the utility pill bottom and the upcoming booking card — matches provider list row spacing (`.space4`).
    static let utilityPillToBookingSpacing: CGFloat = .space4
    /// Nudge the pull-to-refresh wheel slightly below center in the pill ↔ content gap.
    static let pullRefreshWheelVerticalNudge: CGFloat = 8
}

// MARK: - Radius slider (morphing utility pill)

/// Minimal cream track + thumb; mileage label centered above the track.
private struct RadiusDistanceSlider: View {
    @Binding var miles: Double
    let range: ClosedRange<Double>
    var onIntegralMileChanged: () -> Void
    var onDragEnded: () -> Void

    @State private var lastRoundedMile: Int = 0

    private var milesAwayLabel: String {
        "\(Int(miles.rounded())) miles away"
    }

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let span = range.upperBound - range.lowerBound
            let t = span > 0 ? (miles - range.lowerBound) / span : 0
            let thumbCenterX = CGFloat(max(0, min(1, t))) * w

            ZStack {
                Text(milesAwayLabel)
                    .font(OnCutsFont.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(Color.lavaShellCream)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .position(x: w * 0.5, y: 12)

                Capsule()
                    .fill(Color.lavaShellCream.opacity(0.45))
                    .frame(height: 2)
                    .position(x: w * 0.5, y: geo.size.height * 0.58)

                Circle()
                    .fill(Color.lavaShellCream)
                    .frame(width: 20, height: 20)
                    .position(x: thumbCenterX, y: geo.size.height * 0.58)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Maximum distance")
            .accessibilityValue(milesAwayLabel)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = value.location.x
                        let frac = max(0, min(1, x / w))
                        let raw = range.lowerBound + frac * span
                        let newVal = min(range.upperBound, max(range.lowerBound, raw))
                        miles = newVal
                        let r = Int(miles.rounded())
                        if r != lastRoundedMile {
                            lastRoundedMile = r
                            onIntegralMileChanged()
                        }
                    }
                    .onEnded { _ in
                        onDragEnded()
                    }
            )
        }
        .frame(height: 52)
        .onAppear {
            lastRoundedMile = Int(miles.rounded())
        }
    }
}

// MARK: - Browse container

@available(iOS 26.0, macOS 26.0, *)
struct GlassHeaderProviderBrowse<EmptyContent: View>: View {
    @Binding var searchText: String
    @Binding var selectedServiceType: ServiceType
    /// Multi-select service chips under Barber/Beauty (empty = all services for that type).
    @Binding var selectedBrowseServiceNames: Set<String>
    let displayedProviders: [ServiceProvider]
    let isLoading: Bool
    let glassNamespace: Namespace.ID
    let fallbackProfileImageURL: URL?
    /// Unread count for messages tab badge (from `GET …/messages/unread-count`).
    var unreadMessageCount: Int = 0
    /// Active upcoming/today consumer bookings (`bookings-simple` + `scheduleSegment`); shows on calendar toolbar control.
    var upcomingBookingCount: Int = 0
    var onMessagesTap: () -> Void = {}
    var onBookingsTap: () -> Void = {}
    let onProfileTap: () -> Void
    let onProviderTap: (ServiceProvider) -> Void
    let onRefresh: () async -> Void
    @ViewBuilder let emptyContent: () -> EmptyContent
    /// Today’s in-progress / upcoming appointment pill + mesh accent (consumer home).
    var todayBookingActivity: HomeTodayBookingHighlight? = nil
    /// iOS: opens maximum-distance sheet (`ConsumerBrowseDistanceSheet`). Omitted on macOS where browse geo uses no `lat`/`lng`.
    var onMaxDistanceTap: (() -> Void)? = nil
    /// Called after the inline MI radius slider commits a new preference (parent should reload providers).
    var onBrowseRadiusCommitted: (() -> Void)? = nil
    /// When `true`, hides Messages / Bookings / profile avatar from the right split capsule (replaced by `ConsumerStickyHubBar`).
    var hidesQuickNavigationIcons: Bool = false
    /// When provided, mirrors utility-pill search `FocusState` so parents can hide UI (e.g. bottom hub) while the user types.
    var utilitySearchFieldFocused: Binding<Bool>? = nil
    /// When `true`, miles slider, expanded search, or tags picker is active — parent can disable hub tab swiping.
    var utilityPillSuppressesHubPaging: Binding<Bool>? = nil
    /// Parent presents **booking detail** for this row (e.g. push on home `NavigationStack`, or Bookings tab + `pendingOpenBookingDetailId`).
    var onTodayBookingReminderTap: ((ConsumerBookingSimpleRow) -> Void)? = nil
    var sessionManager: AppSessionManager?
    var mainCoordinator: MainCoordinator?
    /// Rebook / active-booking gating inside `ConsumerBookingDetailView`.
    var hasActiveConsumerBooking: Bool = false
    /// When `true`, provider rows and search suggestions do not accept taps (detail overlay is open).
    /// When `true`, provider cards and browse chrome are non-interactive (detail overlay is capturing touches).
    var isProviderDetailCapturingTouches: Bool = false
    /// When `true`, list cards skip `matchedGeometryEffect` so they stay visible and do not leave ghost hit blockers after close.
    var isProviderDetailOverlayPresented: Bool = false
    /// Live hub page index — `@Binding` so TabView off-screen pages still see the current tab (plain `Int` went stale).
    @Binding var homeHubPageIndex: Int
    @State private var frontendConfigStore = PlatformFrontendConfigStore.shared

    @FocusState private var isSearchFieldFocused: Bool
    /// `ScrollGeometry.contentOffset.y` — **0** at rest at top; increases when scrolling down (synced every frame, no snapping).
    @State private var contentOffsetY: CGFloat = 0
    /// Rubber-band pull distance below scroll top — drives the reload wheel load-in before `.refreshable` fires.
    @State private var pullRefreshStretch: CGFloat = 0
    /// Direction-aware hide amount for the utility pill overlay (increases on scroll down, decreases on scroll up).
    @State private var utilityPillCollapseOffset: CGFloat = 0
    @State private var utilityPillScrollResyncGeneration = 0
    @State private var headerMeasuredHeight: CGFloat = 4 + Self.utilityPillMainBarHeight + GlassHeaderConstants.utilityPillToBookingSpacing
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.onCutsHubBarOverlayBottomInset) private var hubBarOverlayBottomInset
    @Environment(\.onCutsHubBarScrollOffsetHandler) private var hubBarScrollHandler
    @Environment(\.onCutsHubPagingCoordinator) private var hubPagingCoordinator

    @State private var isSearchExpanded = false
    @State private var isServiceTagsExpanded = false
    /// iOS: morphs the radius segment into an inline mile slider (`onMaxDistanceTap` non-nil).
    @State private var isAdjustingRadius = false
    @State private var radiusEditingMiles: Double = ConsumerBrowseDistancePreference.defaultMiles
    @State private var displayedMaxDistanceMiles: Double = ConsumerBrowseDistancePreference.maxDistanceMiles
    /// `globalHeaderChrome` is above the `ScrollView` in the `ZStack`, so the system refresh spinner sits underneath; show an explicit wheel while refreshing.
    @State private var showsPullRefreshProgressIndicator = false

    @Namespace private var radiusMorphNamespace
    @Namespace private var serviceTagsMorphNamespace

    /// Morph between the radius chip and the inline distance slider.
    private static var radiusMorphSpring: Animation {
        .spring(response: 0.4, dampingFraction: 0.7)
    }

    /// Inline search field width / layout in the utility pill.
    private static var utilityPillSearchSpring: Animation {
        .spring(response: 0.3, dampingFraction: 0.8)
    }

    private static var utilityPillMainBarHeight: CGFloat { 56 }
    /// Pull distance (pt) at which the reload wheel reaches full size — aligned with system refresh feel.
    private static var pullRefreshWheelRevealDistance: CGFloat { 56 }
    /// Taller than the collapsed utility pill so service chips are easier to scan and tap.
    private static var serviceTagsExpandedBarMinHeight: CGFloat { 88 }
    /// Fallback before the utility chrome preference reports — location chrome + pill row + top inset + list gap.
    private static var headerHeightFallbackUtilityOnly: CGFloat {
        #if os(iOS)
        return 4 + 72 + utilityPillMainBarHeight + GlassHeaderConstants.utilityPillToBookingSpacing
        #else
        return 4 + utilityPillMainBarHeight + GlassHeaderConstants.utilityPillToBookingSpacing
        #endif
    }

    private var shouldShowRadiusSlider: Bool {
        #if os(iOS)
        isAdjustingRadius && onMaxDistanceTap != nil
        #else
        false
        #endif
    }

    /// Measured utility chrome height, or a sane fallback before the first `GeometryReader` pass.
    private var effectiveHeaderHeight: CGFloat {
        headerMeasuredHeight > 2 ? headerMeasuredHeight : Self.headerHeightFallbackUtilityOnly
    }

    /// Resting clearance from scroll top to booking / list — full measured chrome (location + pill), not pill-only.
    private var utilityPillBookingStackOffset: CGFloat {
        let gap = GlassHeaderConstants.utilityPillToBookingSpacing
        if headerMeasuredHeight > 2 {
            return headerMeasuredHeight + gap
        }
        let topInset = CGFloat(showsHomePinnedBookingStripes ? 4 : 10)
        #if os(iOS)
        // Fallback before first measure: location label + toggle + spacing above the pill.
        let locationChromeEstimate: CGFloat = 72
        #else
        let locationChromeEstimate: CGFloat = 0
        #endif
        return topInset + locationChromeEstimate + Self.utilityPillMainBarHeight + gap
    }

    /// Vertical inset for the custom pull-to-refresh wheel — centered in the gap below the utility pill and above the upcoming booking / first provider card.
    private func pullRefreshIndicatorTopInset(safeAreaTop: CGFloat, browseTopUnderlap: CGFloat) -> CGFloat {
        if isSearchExpanded || isServiceTagsExpanded || isAdjustingRadius {
            return safeAreaTop + browseTopUnderlap + effectiveHeaderHeight * 0.5 + GlassHeaderConstants.pullRefreshWheelVerticalNudge
        }
        let chromeBottom = safeAreaTop + browseTopUnderlap + (
            headerMeasuredHeight > 2
                ? headerMeasuredHeight
                : {
                    let topInset = CGFloat(showsHomePinnedBookingStripes ? 4 : 10)
                    #if os(iOS)
                    return topInset + 72 + Self.utilityPillMainBarHeight
                    #else
                    return topInset + Self.utilityPillMainBarHeight
                    #endif
                }()
        )
        let gapBelowPill: CGFloat = showsHomePinnedBookingStripes
            ? GlassHeaderConstants.utilityPillToBookingSpacing
            : 10
        return chromeBottom + gapBelowPill * 0.5 + GlassHeaderConstants.pullRefreshWheelVerticalNudge
    }

    /// 0…1 progress for the reload wheel load-in (pull gesture or active refresh).
    private var pullRefreshWheelLoadProgress: CGFloat {
        if showsPullRefreshProgressIndicator { return 1 }
        return min(1, pullRefreshStretch / Self.pullRefreshWheelRevealDistance)
    }

    private var shouldShowPullRefreshWheel: Bool {
        showsPullRefreshProgressIndicator || pullRefreshWheelLoadProgress > 0.02
    }

    /// Clearance used for pill ↔ booking handoff (compact at rest; expands when search/tags/radius chrome is open).
    private var utilityPillHandoffClearance: CGFloat {
        if showsHomePinnedBookingStripes,
           !isSearchExpanded, !isServiceTagsExpanded, !isAdjustingRadius {
            // Include location chrome + pill so payment / booking cards sit fully below the floating header.
            return utilityPillBookingStackOffset
        }
        let gap = showsHomePinnedBookingStripes ? GlassHeaderConstants.utilityPillToBookingSpacing : 0
        return effectiveHeaderHeight + gap
    }

    /// Scroll distance over which the utility pill slides fully off-screen.
    private var chromeCollapseScrollRange: CGFloat {
        max(GlassHeaderConstants.chromeHideScrollRangeMinimum, utilityPillHandoffClearance)
    }

    private var shouldTrackUtilityPillScrollCollapse: Bool {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad { return false }
        #endif
        if isSearchExpanded || isServiceTagsExpanded || isAdjustingRadius { return false }
        if accessibilityReduceMotion { return false }
        return true
    }

    /// 1 = utility pill fully visible; 0 = slid off-screen. Direction-aware — hides on scroll down, returns on scroll up.
    private var utilityChromeProgress: CGFloat {
        guard shouldTrackUtilityPillScrollCollapse else { return 1 }
        let range = chromeCollapseScrollRange
        guard range > 0 else { return 1 }
        return min(1, max(0, 1 - utilityPillCollapseOffset / range))
    }

    private var scrollPressure: CGFloat {
        min(1, max(0, contentOffsetY / 100))
    }

    /// 0 at scroll rest; approaches 1 as the user scrolls down, for the global header frost.
    private var headerMaterialAmount: CGFloat {
        guard utilityChromeProgress > 0 else { return 0 }
        let delta = max(0, contentOffsetY)
        guard delta > 0 else { return 0 }
        return min(1, delta / 10)
    }

    private var serviceTypeControlScale: CGFloat {
        guard utilityChromeProgress > 0.01 else { return 1 }
        return 1 - 0.02 * scrollPressure
    }

    private var showsHomePinnedBookingStripes: Bool {
        sessionManager != nil
            && mainCoordinator != nil
            && todayBookingActivity != nil
    }

    /// How far the utility pill travels off-screen — matched to booking clearance for a 1:1 handoff.
    private var utilityPillHideTravel: CGFloat {
        utilityPillHandoffClearance * (1 - utilityChromeProgress)
    }

    /// Fixed top inset at rest — never tied to scroll progress (dynamic inset caused scroll feedback loops / glitches).
    private var listTopContentInset: CGFloat {
        guard !showsHomePinnedBookingStripes else { return 0 }
        return effectiveHeaderHeight
    }

    /// Pinned `Section` header — fixed layout padding plus transform-only slide (never mutates scroll metrics mid-gesture).
    @ViewBuilder
    private var homePinnedBookingStripesSectionHeader: some View {
        if showsHomePinnedBookingStripes {
            VStack(alignment: .leading, spacing: 12) {
                if let activity = todayBookingActivity {
                    HomeTodayBookingReminderGlassCard(
                        highlight: activity,
                        onTap: {
                            onTodayBookingReminderTap?(activity.sourceRow)
                        }
                    )
                }
            }
            .padding(.top, utilityPillBookingStackOffset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(y: -utilityPillHideTravel)
            .animation(nil, value: utilityPillHideTravel)
            .compositingGroup()
            .zIndex(2)
        }
    }

    @ViewBuilder
    private func providerBrowseCard(_ provider: ServiceProvider) -> some View {
        ServiceProviderCard(
            provider: provider,
            onTap: { onProviderTap(provider) },
            glassMorphNamespace: nil,
            liquidGlassInteractiveWithoutMorph: true,
            matchedGeometryNamespace: isProviderDetailOverlayPresented ? nil : glassNamespace,
            allowsInteraction: !isProviderDetailCapturingTouches,
            showsStarRating: frontendConfigStore.consumerHomeReviewsEnabled
        )
    }

    /// Label on the utility-pill Tags control: selected provider type replaces “Tags”.
    private var tagsControlTitle: String {
        selectedServiceType == .all ? "Tags" : selectedServiceType.toolbarTitle
    }

    /// Root Tags strip (All / Barber / Beauty) vs drilled-in service chips.
    private var isProviderTypeDrillIn: Bool {
        selectedServiceType != .all
    }

    private var drillInServiceNames: [String] {
        ProviderBrowseServiceCatalog.serviceNames(for: selectedServiceType)
    }

    private var isManualPlaceFieldEditing: Bool {
        #if os(iOS)
        ConsumerBrowseLocationController.shared.isPlaceFieldEditing
        #else
        false
        #endif
    }

    private var utilityPillChromeBlocksParentHubPaging: Bool {
        isSearchExpanded || isServiceTagsExpanded || isAdjustingRadius || isManualPlaceFieldEditing
    }

    /// Expanded search session (`isSearchExpanded`); drives wide pill + suggestions.
    private var isSearching: Bool { isSearchExpanded }

    private var searchQueryTrimmed: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Categories / kinds (`ServiceType` toolbar titles) matching the query.
    private var matchingSearchServiceTypes: [ServiceType] {
        let q = searchQueryTrimmed.lowercased()
        guard !q.isEmpty else { return [] }
        return ServiceType.browseTagCases.filter { type in
            guard type != .all else { return false }
            return type.toolbarTitle.lowercased().contains(q)
        }
    }

    /// Provider names (and kind/specialty) matching the query.
    private var matchingSearchProviders: [ServiceProvider] {
        let q = searchQueryTrimmed.lowercased()
        guard !q.isEmpty else { return [] }
        return displayedProviders.filter { p in
            p.businessName.lowercased().contains(q)
                || p.providerKindDisplayName.lowercased().contains(q)
                || (p.specialty?.lowercased().contains(q) ?? false)
        }
    }

    private var showsSearchSuggestionsPanel: Bool {
        isSearching
            && !searchQueryTrimmed.isEmpty
            && (!matchingSearchServiceTypes.isEmpty || !matchingSearchProviders.isEmpty)
    }

    /// Radius / Tags: hidden whenever search is expanded — same transition as the search bar (no second phase on focus).
    private var utilityPillSideSegmentsOpacity: CGFloat {
        isSearchExpanded ? 0 : 1
    }

    /// Collapse side controls to zero width whenever search is expanded so the field forms in one motion.
    private var utilityPillSideSegmentsUseLayoutWidth: Bool {
        !isSearchExpanded
    }

    private func dismissServiceTagsPanel() {
        withAnimation(Self.radiusMorphSpring) {
            isServiceTagsExpanded = false
        }
    }

    private func applyRadiusEditingToPreference() {
        let stepped = radiusEditingMiles.rounded()
        let clamped = min(
            ConsumerBrowseDistancePreference.maximumMiles,
            max(ConsumerBrowseDistancePreference.minimumMiles, stepped)
        )
        ConsumerBrowseDistancePreference.maxDistanceMiles = clamped
        displayedMaxDistanceMiles = clamped
        radiusEditingMiles = clamped
    }

    private func commitRadiusAdjustment() {
        guard isAdjustingRadius else { return }
        applyRadiusEditingToPreference()
        withAnimation(Self.radiusMorphSpring) {
            isAdjustingRadius = false
        }
        onBrowseRadiusCommitted?()
    }

    /// True when expanded search, tags, radius slider, or keyboard would steal the first list tap.
    private var shouldDismissUtilityChromeOnListTap: Bool {
        isSearchExpanded || isServiceTagsExpanded || isAdjustingRadius || isSearchFieldFocused || isManualPlaceFieldEditing
    }

    /// Collapses search, tag picker, and keyboard when the user scrolls / taps the list backdrop.
    private func dismissChromeFromScroll() {
        if isAdjustingRadius {
            applyRadiusEditingToPreference()
            onBrowseRadiusCommitted?()
        }
        #if os(iOS)
        ConsumerBrowseLocationController.shared.resignPlaceFieldFocus()
        #endif
        withAnimation(Self.utilityPillSearchSpring) {
            isSearchFieldFocused = false
            isSearchExpanded = false
            isServiceTagsExpanded = false
            isAdjustingRadius = false
        }
    }

    private var isHomeHubPageActive: Bool {
        homeHubPageIndex == 0
    }

    private func beginUtilityPillScrollResync() {
        utilityPillScrollResyncGeneration += 1
    }

    /// Scroll offset bridge — drives direction-aware utility pill hide/show, hub bar collapse, and pull refresh affordance.
    private func handleScrollContentSampleChange(_ sample: GlassBrowseScrollSample, resyncSample: Bool = false) {
        if !isHomeHubPageActive { return }

        let offsetY = sample.contentOffsetY
        let previousOffsetY = contentOffsetY
        contentOffsetY = offsetY
        pullRefreshStretch = sample.pullRefreshStretch
        if resyncSample {
            hubBarScrollHandler.onResyncLastSample?(0, offsetY)
        } else {
            hubBarScrollHandler.onOffsetChange?(0, offsetY)
        }

        guard shouldTrackUtilityPillScrollCollapse else {
            utilityPillCollapseOffset = 0
            return
        }
        if offsetY <= 0 {
            utilityPillCollapseOffset = 0
            return
        }
        let range = chromeCollapseScrollRange
        if resyncSample {
            utilityPillCollapseOffset = min(range, offsetY)
            return
        }
        let delta = offsetY - previousOffsetY
        utilityPillCollapseOffset = min(range, max(0, utilityPillCollapseOffset + delta))
    }

    @ViewBuilder
    private func pullRefreshWheelOverlay(safeAreaTop: CGFloat, browseTopUnderlap: CGFloat) -> some View {
        if shouldShowPullRefreshWheel {
            let progress = pullRefreshWheelLoadProgress
            Group {
                if showsPullRefreshProgressIndicator {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.oliveGreen)
                } else {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.oliveGreen,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))
                }
            }
            .scaleEffect(0.35 + 0.65 * progress)
            .opacity(Double(progress))
            .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.12), value: progress)
            .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.15), value: showsPullRefreshProgressIndicator)
            .padding(
                .top,
                pullRefreshIndicatorTopInset(
                    safeAreaTop: safeAreaTop,
                    browseTopUnderlap: browseTopUnderlap
                )
            )
            .frame(maxWidth: .infinity, alignment: .top)
            .allowsHitTesting(false)
        }
    }

    /// Hub `NavigationStack` + clear nav: iPad often reports a small `safeAreaInsets.top` while inline title / toolbar still consume space, clipping the browse utility row.
    private func browseTopUnderlapCompensation(safeAreaTop: CGFloat) -> CGFloat {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .pad else { return 0 }
        return max(0, 56 - safeAreaTop)
        #else
        return 0
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                #if os(iOS)
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: [.top, .leading, .trailing])
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                #else
                ServiceProviderBrowseMeshBackdrop(homeBookingHighlight: todayBookingActivity)
                    .ignoresSafeArea()
                #endif

                ScrollView {
                    LazyVStack(spacing: .space4, pinnedViews: showsHomePinnedBookingStripes ? [.sectionHeaders] : []) {
                        if isLoading && displayedProviders.isEmpty {
                            if showsHomePinnedBookingStripes {
                                Section {
                                    GlassEffectContainer(spacing: 0) {
                                        ProviderGlassSkeletonList()
                                    }
                                    .zIndex(0)
                                } header: {
                                    homePinnedBookingStripesSectionHeader
                                }
                            } else {
                                GlassEffectContainer(spacing: 0) {
                                    ProviderGlassSkeletonList()
                                        .padding(.top, .space4)
                                }
                            }
                        } else if displayedProviders.isEmpty {
                            if showsHomePinnedBookingStripes {
                                Section {
                                    GlassEffectContainer(spacing: 0) {
                                        emptyContent()
                                    }
                                    .zIndex(0)
                                } header: {
                                    homePinnedBookingStripesSectionHeader
                                }
                            } else {
                                GlassEffectContainer(spacing: 0) {
                                    emptyContent()
                                }
                            }
                        } else if showsHomePinnedBookingStripes {
                            Section {
                                GlassEffectContainer(spacing: 0) {
                                    LazyVStack(spacing: .space4) {
                                        ForEach(displayedProviders) { provider in
                                            providerBrowseCard(provider)
                                        }
                                    }
                                }
                                .zIndex(0)
                            } header: {
                                homePinnedBookingStripesSectionHeader
                            }
                        } else {
                            GlassEffectContainer(spacing: 0) {
                                LazyVStack(spacing: .space4) {
                                    ForEach(displayedProviders) { provider in
                                        providerBrowseCard(provider)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, listTopContentInset)
                    .padding(.horizontal, .space4)
                    .padding(.bottom, .space6 + hubBarOverlayBottomInset)
                }
                #if os(iOS)
                .scrollContentBackground(.hidden)
                .scrollBounceBehavior(.always, axes: .vertical)
                .scrollDismissesKeyboard(.immediately)
                #endif
                .scrollDisabled(isProviderDetailOverlayPresented)
                .zIndex(0)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        guard shouldDismissUtilityChromeOnListTap else { return }
                        dismissChromeFromScroll()
                    }
                )
                .modifier(GlassBrowseScrollOffsetBridgeModifier(onSampleChange: { handleScrollContentSampleChange($0) }))
                #if os(iOS)
                .background {
                    HomeBrowseScrollResyncBridge(resyncGeneration: utilityPillScrollResyncGeneration) { offsetY in
                        handleScrollContentSampleChange(
                            GlassBrowseScrollSample(contentOffsetY: offsetY, pullRefreshStretch: 0),
                            resyncSample: true
                        )
                    }
                }
                #endif
                .refreshable {
                    showsPullRefreshProgressIndicator = true
                    defer { showsPullRefreshProgressIndicator = false }
                    await OnCutsPullToRefresh.runMainActorAsyncIsolatedFromRefreshableCancellation {
                        await onRefresh()
                    }
                }
                .overlay {
                    if isLoading && !displayedProviders.isEmpty {
                        ZStack {
                            Color.black.opacity(0.1)
                            ProgressView()
                                .scaleEffect(1.25)
                                .tint(.white)
                        }
                        .allowsHitTesting(false)
                    }
                }

                globalHeaderChrome(browseTopUnderlapCompensation: browseTopUnderlapCompensation(safeAreaTop: geo.safeAreaInsets.top))
                    .zIndex(5)
            }
            .overlay(alignment: .top) {
                pullRefreshWheelOverlay(
                    safeAreaTop: geo.safeAreaInsets.top,
                    browseTopUnderlap: browseTopUnderlapCompensation(safeAreaTop: geo.safeAreaInsets.top)
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: isSearchFieldFocused) { _, focused in
                // Keep hub suppressed if the manual place field still owns the keyboard.
                utilitySearchFieldFocused?.wrappedValue = focused || isManualPlaceFieldEditing
            }
            .onChange(of: isManualPlaceFieldEditing) { _, editing in
                utilityPillSuppressesHubPaging?.wrappedValue = utilityPillChromeBlocksParentHubPaging
                utilitySearchFieldFocused?.wrappedValue = editing || isSearchFieldFocused
                if editing {
                    withAnimation(Self.utilityPillSearchSpring) {
                        isSearchExpanded = false
                        isServiceTagsExpanded = false
                        if isAdjustingRadius {
                            applyRadiusEditingToPreference()
                            isAdjustingRadius = false
                        }
                    }
                }
            }
            .onChange(of: utilityPillChromeBlocksParentHubPaging) { _, active in
                utilityPillSuppressesHubPaging?.wrappedValue = active
            }
            .onChange(of: homeHubPageIndex) { _, page in
                guard page == 0 else { return }
                beginUtilityPillScrollResync()
            }
            .onReceive(NotificationCenter.default.publisher(for: .homeHubBrowseShouldResyncUtilityPill)) { _ in
                beginUtilityPillScrollResync()
            }
            .onAppear {
                utilityPillSuppressesHubPaging?.wrappedValue = utilityPillChromeBlocksParentHubPaging
                if isHomeHubPageActive {
                    beginUtilityPillScrollResync()
                }
            }
        }
    }

    /// Utility pill / radius / search suggestions — opacity/scale follow `utilityChromeProgress` via the parent chrome.
    private var collapsingUtilityHeaderChrome: some View {
        Group {
            if shouldShowRadiusSlider {
                expandedRadiusSliderGlassBar
                    .matchedGeometryEffect(id: "browseRadiusGlass", in: radiusMorphNamespace)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    #if os(iOS)
                    if !isSearchExpanded && !isServiceTagsExpanded {
                        ConsumerBrowseLocationChrome(
                            locationController: ConsumerBrowseLocationController.shared,
                            usesGlassChrome: true
                        )
                        .zIndex(40)
                    }
                    #endif
                    // Hide utility pill while typing a manual place (same idea as search hiding location chrome).
                    if !isManualPlaceFieldEditing {
                        HStack(alignment: .center, spacing: 16) {
                            if isServiceTagsExpanded {
                                expandedServiceTagsGlassBar
                                    .scaleEffect(serviceTypeControlScale)
                                    .frame(maxWidth: .infinity)
                                    .matchedGeometryEffect(id: "browseServiceTagsGlass", in: serviceTagsMorphNamespace)
                            } else {
                                floatingUtilityPill
                                    .scaleEffect(serviceTypeControlScale)
                                    .frame(maxWidth: .infinity)
                            }

                            if !hidesQuickNavigationIcons && !isSearchExpanded && !isServiceTagsExpanded {
                                rightNavOnlyCapsule
                            }
                        }
                        .zIndex(1)
                        .padding(.horizontal, (isSearchExpanded || isServiceTagsExpanded) ? 20 : 0)
                        .animation(Self.utilityPillSearchSpring, value: isSearchExpanded)
                        .animation(Self.radiusMorphSpring, value: isServiceTagsExpanded)
                        .frame(
                            minHeight: isServiceTagsExpanded
                                ? Self.serviceTagsExpandedBarMinHeight
                                : Self.utilityPillMainBarHeight,
                            alignment: .center
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if showsSearchSuggestionsPanel {
                        searchLiveSuggestionsPanel
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(Self.utilityPillSearchSpring, value: showsSearchSuggestionsPanel)
                .animation(Self.utilityPillSearchSpring, value: isManualPlaceFieldEditing)
            }
        }
        .animation(Self.utilityPillSearchSpring, value: isSearchExpanded)
        .animation(Self.radiusMorphSpring, value: isServiceTagsExpanded)
        .animation(Self.radiusMorphSpring, value: isAdjustingRadius)
        .frame(maxWidth: .infinity, alignment: .top)
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(0.04 * Double(headerMaterialAmount)),
            radius: headerMaterialAmount > 0.02 ? 10 : 0,
            y: headerMaterialAmount > 0.02 ? 3 : 0
        )
    }

    /// Utility pill / radius / search — scroll-linked `opacity` + `offset` (no threshold snap). `zIndex(2)` above scroll content.
    @ViewBuilder
    private func globalHeaderChrome(browseTopUnderlapCompensation: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsingUtilityHeaderChrome
        }
        .opacity(Double(utilityChromeProgress))
        .offset(y: -utilityPillHideTravel)
        .animation(nil, value: utilityChromeProgress)
        .allowsHitTesting(utilityChromeProgress > 0.12)
        .onChange(of: isSearchExpanded) { _, expanded in
            if expanded {
                isServiceTagsExpanded = false
                if isAdjustingRadius {
                    applyRadiusEditingToPreference()
                    isAdjustingRadius = false
                }
                Task { @MainActor in
                    await Task.yield()
                    guard isSearchExpanded else { return }
                    isSearchFieldFocused = true
                }
            }
        }
        .onChange(of: isServiceTagsExpanded) { _, expanded in
            guard expanded else { return }
            if isAdjustingRadius {
                applyRadiusEditingToPreference()
                isAdjustingRadius = false
            }
        }
        .onChange(of: isAdjustingRadius) { _, adjusting in
            guard adjusting else { return }
            isSearchFieldFocused = false
            isSearchExpanded = false
            isServiceTagsExpanded = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .consumerBrowseMaxDistanceDidChange)) { _ in
            displayedMaxDistanceMiles = ConsumerBrowseDistancePreference.maxDistanceMiles
        }
        .onAppear {
            displayedMaxDistanceMiles = ConsumerBrowseDistancePreference.maxDistanceMiles
        }
        .padding(.horizontal, .space4)
        /// Tighter top inset when the booking reminder sits below — less dead space between pill and reminder.
        .padding(.top, (showsHomePinnedBookingStripes ? 4 : 10) + browseTopUnderlapCompensation)
        .padding(.bottom, showsHomePinnedBookingStripes ? 0 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: GlobalHeaderMeasuredHeightKey.self, value: geo.size.height)
            }
        }
        .onPreferenceChange(GlobalHeaderMeasuredHeightKey.self) { newHeight in
            if newHeight > 2 {
                headerMeasuredHeight = newHeight
            } else {
                headerMeasuredHeight = Self.headerHeightFallbackUtilityOnly
            }
        }
        .zIndex(2)
    }

    /// Radius · Search · Tags — single main capsule (tags picker morphs to full-width bar in `globalHeaderChrome`).
    private var floatingUtilityPill: some View {
        utilityPillMainBar
            .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Full-width provider-type or service chips + Done — morphs from the Tags control.
    @ViewBuilder
    private var expandedServiceTagsGlassBar: some View {
        #if os(iOS)
        HStack(alignment: .center, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tagsSelectionChips
                }
                .padding(.vertical, 2)
                .padding(.leading, 2)
                .padding(.trailing, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                GlassCapsuleToolbarHaptics.lightTap()
                dismissServiceTagsPanel()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(OnCutsFont.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(UtilityPillPhysicalPressStyle())
            .accessibilityLabel("Done selecting tags")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: Self.serviceTagsExpandedBarMinHeight, alignment: .center)
        .contentShape(Capsule())
        .glassEffect(.regular.interactive(), in: .capsule)
        #else
        HStack(alignment: .center, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tagsSelectionChips
                }
                .padding(.vertical, 2)
                .padding(.leading, 2)
                .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                GlassCapsuleToolbarHaptics.lightTap()
                dismissServiceTagsPanel()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(OnCutsFont.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.lavaShellCream)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done selecting tags")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: Self.serviceTagsExpandedBarMinHeight, alignment: .center)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule()
                .stroke(Color.lavaShellCream, lineWidth: 1)
                .allowsHitTesting(false)
        }
        #endif
    }

    @ViewBuilder
    private var tagsSelectionChips: some View {
        if isProviderTypeDrillIn {
            // Barber / Beauty stays selected in place of All; remaining chips are that type’s services.
            serviceTypeTagChip(selectedServiceType, isDrillInContextChip: true)
            ForEach(drillInServiceNames, id: \.self) { serviceName in
                browseServiceTagChip(serviceName)
            }
        } else {
            ForEach(ServiceType.browseTagCases, id: \.self) { type in
                serviceTypeTagChip(type, isDrillInContextChip: false)
            }
        }
    }

    /// Main frosted capsule: Radius · Search · Tags — same bar always; search formation animates on `isSearchExpanded` only.
    private var utilityPillMainBar: some View {
        HStack(spacing: 0) {
            #if os(iOS)
            Group {
                if onMaxDistanceTap != nil {
                    Button {
                        GlassCapsuleToolbarHaptics.lightTap()
                        radiusEditingMiles = ConsumerBrowseDistancePreference.maxDistanceMiles
                        withAnimation(Self.radiusMorphSpring) {
                            isSearchExpanded = false
                            isSearchFieldFocused = false
                            isServiceTagsExpanded = false
                            isAdjustingRadius = true
                        }
                    } label: {
                        Text("\(Int(displayedMaxDistanceMiles.rounded())) MI")
                            .font(OnCutsFont.system(size: 14, weight: .medium, design: .default))
                            .foregroundStyle(Color.lavaShellCream)
                            .textCase(.uppercase)
                            .kerning(2.2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(minWidth: 44, alignment: .center)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(UtilityPillPhysicalPressStyle())
                    .matchedGeometryEffect(id: "browseRadiusGlass", in: radiusMorphNamespace)
                    .accessibilityLabel("Maximum search distance, \(Int(displayedMaxDistanceMiles.rounded())) miles, adjust")

                    utilityPillVerticalDivider
                }
            }
            .opacity(utilityPillSideSegmentsOpacity)
            .frame(width: utilityPillSideSegmentsUseLayoutWidth ? nil : 0, alignment: .leading)
            .clipped()
            .allowsHitTesting(utilityPillSideSegmentsUseLayoutWidth || utilityPillSideSegmentsOpacity > 0.01)
            .animation(Self.utilityPillSearchSpring, value: isSearchExpanded)
            #endif

            utilityPillSearchSegment
                .frame(maxWidth: isSearchExpanded ? .infinity : nil, alignment: .leading)
                .layoutPriority(isSearchExpanded ? 1 : 0)
                .animation(Self.utilityPillSearchSpring, value: isSearchExpanded)

            utilityPillSearchToTagsDivider
                .opacity(utilityPillSideSegmentsOpacity)
                .frame(width: utilityPillSideSegmentsUseLayoutWidth ? nil : 0)
                .clipped()
                .allowsHitTesting(utilityPillSideSegmentsUseLayoutWidth || utilityPillSideSegmentsOpacity > 0.01)
                .animation(Self.utilityPillSearchSpring, value: isSearchExpanded)

            Group {
                Button {
                    if !isServiceTagsExpanded {
                        GlassCapsuleToolbarHaptics.lightTap()
                    }
                    if isAdjustingRadius {
                        applyRadiusEditingToPreference()
                    }
                    withAnimation(Self.radiusMorphSpring) {
                        isAdjustingRadius = false
                        isSearchFieldFocused = false
                        isSearchExpanded = false
                        isServiceTagsExpanded = true
                    }
                } label: {
                    HStack(spacing: 0) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(OnCutsFont.body(weight: .semibold))
                            .foregroundStyle(Color.lavaShellCream)
                            .frame(width: 40, height: 40)
                        Text(tagsControlTitle)
                            .font(OnCutsFont.system(size: 14, weight: .semibold, design: .default))
                            .foregroundStyle(Color.lavaShellCream)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    // Minimum width keeps the icon + label on one row during matched-geometry retraction (avoids vertical glyph stacking).
                    .frame(minWidth: 78, alignment: .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(UtilityPillPhysicalPressStyle())
                .accessibilityLabel(
                    "Tags, \(tagsAccessibilitySummary), show list"
                )
            }
            .matchedGeometryEffect(id: "browseServiceTagsGlass", in: serviceTagsMorphNamespace)
            .opacity(utilityPillSideSegmentsOpacity)
            .frame(width: utilityPillSideSegmentsUseLayoutWidth ? nil : 0, alignment: .center)
            .clipped()
            .allowsHitTesting(utilityPillSideSegmentsUseLayoutWidth || utilityPillSideSegmentsOpacity > 0.01)
            .animation(Self.utilityPillSearchSpring, value: isSearchExpanded)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minHeight: Self.utilityPillMainBarHeight, alignment: .center)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule()
                .stroke(Color.lavaShellCream, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay {
            Capsule()
                .stroke(Color.oliveGreen.opacity(isSearchExpanded ? 0.75 : 0), lineWidth: 2)
                .allowsHitTesting(false)
                .animation(Self.utilityPillSearchSpring, value: isSearchExpanded)
        }
    }

    /// Live filter suggestions: service kinds (horizontal) + providers (vertical).
    private var searchLiveSuggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !matchingSearchServiceTypes.isEmpty {
                Text("Services")
                    .font(OnCutsFont.caption(weight: .semibold))
                    .foregroundStyle(Color.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(matchingSearchServiceTypes, id: \.self) { type in
                            Button {
                                GlassCapsuleToolbarHaptics.lightTap()
                                selectedServiceType = type
                                selectedBrowseServiceNames = []
                                withAnimation(Self.utilityPillSearchSpring) {
                                    searchText = ""
                                    isSearchFieldFocused = false
                                    isSearchExpanded = false
                                }
                            } label: {
                                Text(type.toolbarTitle)
                                    .font(OnCutsFont.subheadline(weight: .medium))
                                    .foregroundStyle(utilityPillSearchInputCharcoal)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .stroke(Color.lavaShellCream, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !matchingSearchProviders.isEmpty {
                Text("Providers")
                    .font(OnCutsFont.caption(weight: .semibold))
                    .foregroundStyle(Color.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(matchingSearchProviders.enumerated()), id: \.element.id) { index, provider in
                            Button {
                                guard !isProviderDetailCapturingTouches else { return }
                                GlassCapsuleToolbarHaptics.lightTap()
                                onProviderTap(provider)
                                withAnimation(Self.utilityPillSearchSpring) {
                                    isSearchFieldFocused = false
                                    isSearchExpanded = false
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    providerSuggestionAvatar(provider)
                                    Text(provider.businessName)
                                        .font(utilityPillSearchProviderNameFont)
                                        .foregroundStyle(utilityPillSearchInputCharcoal)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.55)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isProviderDetailCapturingTouches)
                            if index < matchingSearchProviders.count - 1 {
                                Divider().opacity(0.35)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            Button {
                GlassCapsuleToolbarHaptics.lightTap()
                withAnimation(Self.utilityPillSearchSpring) {
                    isSearchFieldFocused = false
                    isSearchExpanded = false
                }
            } label: {
                Text("Done")
                    .font(OnCutsFont.subheadline(weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.lavaShellCream)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.lavaShellCream.opacity(0.9), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func providerSuggestionAvatar(_ provider: ServiceProvider) -> some View {
        ServiceProviderProfileThumbnail(
            imageUrl: provider.profileImageUrl,
            businessName: provider.businessName,
            size: 36,
            cornerRadius: 18
        )
    }

    /// Collapsed: icon only. Expanded: `TextField` (placeholder “Search operators”) + close.
    private var utilityPillSearchSegment: some View {
        Group {
            if isSearchExpanded {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(OnCutsFont.system(size: 19, weight: .semibold, design: .default))
                        .foregroundStyle(utilityPillSearchInputCharcoal)
                        .accessibilityHidden(true)

                    TextField("Search operators", text: $searchText)
                        .font(utilityPillSearchInputFont)
                        .textFieldStyle(.plain)
                        .foregroundStyle(utilityPillSearchInputCharcoal)
                        .tint(Color.lavaShellCream)
                        .focused($isSearchFieldFocused)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(iOS)
                        .background {
                            if UIDevice.current.userInterfaceIdiom == .pad {
                                PadUtilityBrowseSearchTextFieldBackgroundClearer()
                                    .allowsHitTesting(false)
                            }
                        }
                        .textInputAutocapitalization(.words)
                    #endif
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { _, _ in
                            guard isSearchExpanded, !accessibilityReduceMotion else { return }
                            GlassCapsuleToolbarHaptics.selectionChanged()
                        }

                    Button {
                        GlassCapsuleToolbarHaptics.lightTap()
                        withAnimation(Self.utilityPillSearchSpring) {
                            isSearchFieldFocused = false
                            isSearchExpanded = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(OnCutsFont.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close search")
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
            } else {
                Button {
                    GlassCapsuleToolbarHaptics.lightTap()
                    if isAdjustingRadius {
                        applyRadiusEditingToPreference()
                    }
                    withAnimation(Self.utilityPillSearchSpring) {
                        isAdjustingRadius = false
                        isServiceTagsExpanded = false
                        isSearchExpanded = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(OnCutsFont.body(weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(UtilityPillPhysicalPressStyle())
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Search operators")
            }
        }
    }

    private var utilityPillVerticalDivider: some View {
        Rectangle()
            .fill(Color.lavaShellCream.opacity(0.5))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 4)
    }

    /// Tighter when collapsed so the search icon sits flush next to Tags; expanded keeps breathing room for the field.
    private var utilityPillSearchToTagsDivider: some View {
        Rectangle()
            .fill(Color.lavaShellCream.opacity(0.5))
            .frame(width: 1, height: 22)
            .padding(.leading, isSearchExpanded ? 4 : 0)
            .padding(.trailing, isSearchExpanded ? 4 : 0)
    }

    /// Messages + bookings + profile — frosted pill (omitted when `hidesQuickNavigationIcons`); radius lives in `floatingUtilityPill`.
    private var rightNavOnlyCapsule: some View {
        HStack(spacing: 4) {
            messagesToolbarButton
            bookingsToolbarButton
            GlassToolbarProfileAvatarButton(
                fallbackImageURL: fallbackProfileImageURL,
                onTap: onProfileTap,
                useExternalMaterial: true
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .splitCapsuleOnGlobalHeaderChrome()
    }

    private var messagesToolbarButton: some View {
        Button {
            GlassCapsuleToolbarHaptics.lightTap()
            onMessagesTap()
        } label: {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(OnCutsFont.body(weight: .semibold))
                .foregroundStyle(.primary)
                .overlay(alignment: .topTrailing) {
                    if unreadMessageCount > 0 {
                        OnCutsTabNotificationNode(isTabActive: false)
                            .offset(x: 4, y: -4)
                    }
                }
                .frame(width: 40, height: 40)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            unreadMessageCount > 0
                ? "Messages, \(unreadMessageCount) unread"
                : "Messages"
        )
    }

    private var bookingsToolbarButton: some View {
        Button {
            GlassCapsuleToolbarHaptics.lightTap()
            onBookingsTap()
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(OnCutsFont.body(weight: .semibold))
                .foregroundStyle(.primary)
                .overlay(alignment: .topTrailing) {
                    if upcomingBookingCount > 0 {
                        OnCutsTabNotificationNode(isTabActive: false)
                            .offset(x: 4, y: -4)
                    }
                }
                .frame(width: 40, height: 40)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            upcomingBookingCount > 0
                ? "Bookings, \(upcomingBookingCount) upcoming"
                : "Bookings"
        )
    }

    /// Full-width inline mile slider (morphs from the collapsed radius chip). iOS + location browse only.
    @ViewBuilder
    private var expandedRadiusSliderGlassBar: some View {
        #if os(iOS)
        HStack(alignment: .center, spacing: 10) {
            RadiusDistanceSlider(
                miles: $radiusEditingMiles,
                range: ConsumerBrowseDistancePreference.minimumMiles ... ConsumerBrowseDistancePreference.maximumMiles,
                onIntegralMileChanged: {
                    GlassCapsuleToolbarHaptics.selectionChanged()
                },
                onDragEnded: {
                    commitRadiusAdjustment()
                }
            )
            .frame(maxWidth: .infinity)

            Button {
                GlassCapsuleToolbarHaptics.lightTap()
                commitRadiusAdjustment()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(OnCutsFont.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(UtilityPillPhysicalPressStyle())
            .accessibilityLabel("Done adjusting distance")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
        .contentShape(Capsule())
        .glassEffect(.regular.interactive(), in: .capsule)
        .onAppear {
            radiusEditingMiles = ConsumerBrowseDistancePreference.maxDistanceMiles
        }
        #else
        EmptyView()
        #endif
    }

    private var tagsAccessibilitySummary: String {
        if selectedBrowseServiceNames.isEmpty {
            return selectedServiceType.toolbarTitle
        }
        let services = selectedBrowseServiceNames.sorted().joined(separator: ", ")
        return "\(selectedServiceType.toolbarTitle), \(services)"
    }

    private func serviceTypeTagChip(_ type: ServiceType, isDrillInContextChip: Bool) -> some View {
        let isSelected: Bool = {
            if isDrillInContextChip { return true }
            return selectedServiceType == type
        }()
        return Button {
            if isDrillInContextChip {
                clearProviderTypeSelectionToAll()
                return
            }
            if selectedServiceType != type {
                GlassCapsuleToolbarHaptics.selectionChanged()
            }
            withAnimation(Self.radiusMorphSpring) {
                selectedServiceType = type
                selectedBrowseServiceNames = []
                // Keep panel open when drilling into Barber/Beauty so service chips appear.
                if type == .all {
                    isServiceTagsExpanded = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(type.toolbarTitle)
                    .font(OnCutsFont.subheadline(weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                if isDrillInContextChip {
                    Image(systemName: "xmark")
                        .font(OnCutsFont.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 7)
            .padding(.leading, 12)
            .padding(.trailing, isDrillInContextChip ? 10 : 12)
            .background(
                Capsule()
                    .fill(isSelected ? Color.oliveGreen : Color.primary.opacity(0.08))
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(isSelected ? 0.35 : 0.22), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isDrillInContextChip
                ? "Clear \(type.toolbarTitle) filter"
                : "\(type.toolbarTitle) filter"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(
            isDrillInContextChip
                ? "Returns to All and shows Barber and Beauty tags"
                : "Filters providers by \(type.toolbarTitle)"
        )
    }

    private func clearProviderTypeSelectionToAll() {
        GlassCapsuleToolbarHaptics.selectionChanged()
        withAnimation(Self.radiusMorphSpring) {
            selectedServiceType = .all
            selectedBrowseServiceNames = []
        }
    }

    private func browseServiceTagChip(_ serviceName: String) -> some View {
        let isSelected = selectedBrowseServiceNames.contains { selected in
            selected.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(serviceName) == .orderedSame
        }
        return Button {
            GlassCapsuleToolbarHaptics.selectionChanged()
            withAnimation(Self.radiusMorphSpring) {
                if isSelected {
                    selectedBrowseServiceNames = selectedBrowseServiceNames.filter {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            .caseInsensitiveCompare(serviceName) != .orderedSame
                    }
                } else {
                    selectedBrowseServiceNames.insert(serviceName)
                }
            }
        } label: {
            Text(serviceName)
                .font(OnCutsFont.subheadline(weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.oliveGreen : Color.primary.opacity(0.08))
                )
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(isSelected ? 0.35 : 0.22), lineWidth: 0.75)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(serviceName) service filter")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

}
