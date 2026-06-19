//
//  UnifiedTimelineView.swift
//  Intera
//
//  Single data-driven scroll: Upcoming / Today / Past with pinned section headers,
//  initial scroll-to-today (or next best section), and jump-to-today FAB.
//

import SwiftUI

struct UnifiedTimelineView: View {
    let projection: ConsumerBookingsTimelineProjection
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    /// Bumps after each successful reload so the list can re-anchor.
    var scrollEpoch: Int
    var scheduleLine: (ConsumerBookingSimpleRow) -> String
    var hasActiveConsumerBooking: Bool = false
    var onShowLogin: () -> Void = {}
    /// Past bookings only: remove from this device’s list via `hide-from-list` (optional so previews stay simple).
    var onRemovePastBooking: ((ConsumerBookingSimpleRow) -> Void)? = nil
    /// One-shot scroll target (e.g. Upcoming after a new booking request). Cleared after scrolling.
    var scrollAnchorOverride: Binding<String?> = .constant(nil)
    /// Attach to the timeline `ScrollView` so pull-to-refresh actually runs (`.refreshable` on outer `NavigationStack` does not reliably).
    var onPullToRefresh: (() async -> Void)? = nil

    @State private var showJumpToTodayFAB = false
    @State private var timelineContentTop: CGFloat = 0
    /// True after the user scrolls the timeline down; layout-only reflows (disclosure expand) stay near y≈0 and must not drive chrome.
    @State private var hasTimelineUserScrolled = false
    @State private var timelineHeaderMinYs: [String: CGFloat] = [:]
    @Environment(\.interaHubBarOverlayBottomInset) private var hubBarOverlayBottomInset

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                timelineScrollView
                    #if os(iOS)
                    .scrollContentBackground(.hidden)
                    #endif
                    .coordinateSpace(name: "timelineScroll")

                if showJumpToTodayFAB, !projection.today.isEmpty {
                    jumpToTodayButton(proxy: proxy)
                        .padding(.trailing, 20)
                        .padding(.bottom, 24 + hubBarOverlayBottomInset)
                }
            }
            .onPreferenceChange(TimelineScrollGeometry.ContentTopPreferenceKey.self) { y in
                absorbTimelineContentTop(y)
            }
            .onPreferenceChange(TimelineScrollGeometry.HeaderMinYPreferenceKey.self) { dict in
                timelineHeaderMinYs = dict
                guard hasTimelineUserScrolled else { return }
                updateJumpFABFromTodayHeader(dict[ConsumerBookingsTimelineProjection.todayHeaderID])
            }
            .onAppear {
                scrollToPreferredAnchor(proxy)
            }
            .onChange(of: scrollEpoch) { _, _ in
                scrollToPreferredAnchor(proxy)
            }
        }
    }

    @ViewBuilder
    private var timelineScrollView: some View {
        // Default `.basedOnSize` disables rubber-banding when content is shorter than the screen, so pull-to-refresh
        // never activates — users only saw updates after tab switches (which post `consumerBookingsListShouldRefresh`).
        if let onPullToRefresh {
            ScrollView {
                timelineLazyStack
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .interaHubBarScrollOffsetReporting(pageIndex: 2)
            .refreshable {
                await onPullToRefresh()
            }
        } else {
            ScrollView {
                timelineLazyStack
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .interaHubBarScrollOffsetReporting(pageIndex: 2)
        }
    }

    /// Ignore near-top geometry jitter when disclosure groups expand/collapse without user scrolling.
    private func absorbTimelineContentTop(_ y: CGFloat) {
        if y < -8 {
            hasTimelineUserScrolled = true
            timelineContentTop = y
            return
        }
        if hasTimelineUserScrolled {
            timelineContentTop = y
            if y >= -4 {
                hasTimelineUserScrolled = false
            }
        }
    }

    private var timelineLazyStack: some View {
        LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
            timelineSection(
                headerID: ConsumerBookingsTimelineProjection.upcomingHeaderID,
                rows: projection.upcoming,
                position: .upcoming
            )
            timelineSection(
                headerID: ConsumerBookingsTimelineProjection.todayHeaderID,
                rows: projection.today,
                position: .today
            )
            pastTimelineSection(
                headerID: ConsumerBookingsTimelineProjection.pastHeaderID,
                items: projection.pastItems
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28 + hubBarOverlayBottomInset)
        .background(contentTopTracker)
    }

    private var contentTopTracker: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: TimelineScrollGeometry.ContentTopPreferenceKey.self,
                value: geo.frame(in: .named("timelineScroll")).minY
            )
        }
    }

    private var showsPinnedHeaderBackdropBlur: Bool {
        hasTimelineUserScrolled && timelineContentTop < -14
    }

    private func updateJumpFABFromTodayHeader(_ y: CGFloat?) {
        guard !projection.today.isEmpty else {
            showJumpToTodayFAB = false
            return
        }
        guard let y, y.isFinite else { return }
        let band: ClosedRange<CGFloat> = -80 ... 360
        showJumpToTodayFAB = !band.contains(y)
    }

    // MARK: - Sections

    @ViewBuilder
    private func pastTimelineSection(
        headerID: String,
        items: [PastBookingsListItem]
    ) -> some View {
        Section {
            if items.isEmpty {
                Text(emptyBlurb(for: .past))
                    .font(InteraFont.caption)
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(items, id: \.itemId) { item in
                    switch item {
                    case .single(let row):
                        BookingTimelineRow(
                            row: row,
                            position: .past,
                            sessionManager: sessionManager,
                            coordinator: coordinator,
                            scheduleLine: scheduleLine(row),
                            hasActiveConsumerBooking: hasActiveConsumerBooking,
                            onShowLogin: onShowLogin,
                            onRemovePastBooking: onRemovePastBooking
                        )
                        .id(item.itemId)
                    case .group(let group):
                        PastProviderBookingsGroupView(
                            group: group,
                            scheduleLine: scheduleLine,
                            onRemovePastBooking: onRemovePastBooking
                        )
                        .id(item.itemId)
                    }
                }
            }
        } header: {
            TimelineSectionHeader(
                position: .past,
                headerID: headerID,
                showBackdropBlur: showsPinnedHeaderBackdropBlur
            )
        }
    }

    @ViewBuilder
    private func timelineSection(
        headerID: String,
        rows: [ConsumerBookingSimpleRow],
        position: TimelinePosition
    ) -> some View {
        Section {
            if rows.isEmpty {
                Text(emptyBlurb(for: position))
                    .font(InteraFont.caption)
                    .foregroundStyle(Color.lavaShellCreamTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(rows) { row in
                    BookingTimelineRow(
                        row: row,
                        position: position,
                        sessionManager: sessionManager,
                        coordinator: coordinator,
                        scheduleLine: scheduleLine(row),
                        hasActiveConsumerBooking: hasActiveConsumerBooking,
                        onShowLogin: onShowLogin,
                        onRemovePastBooking: onRemovePastBooking
                    )
                    .id(row.id)
                }
            }
        } header: {
            TimelineSectionHeader(
                position: position,
                headerID: headerID,
                showBackdropBlur: showsPinnedHeaderBackdropBlur
            )
        }
    }

    private func emptyBlurb(for position: TimelinePosition) -> String {
        switch position {
        case .past: return "No past bookings"
        case .today: return "Nothing scheduled for today"
        case .upcoming: return "No upcoming bookings"
        }
    }

    // MARK: - Scroll + FAB

    private func scrollToPreferredAnchor(_ proxy: ScrollViewProxy) {
        let override = scrollAnchorOverride.wrappedValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: String = {
            if let o = override, !o.isEmpty { return o }
            return projection.preferredScrollAnchorID
        }()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(LiquidGlassMotion.fluidSpring) {
                proxy.scrollTo(id, anchor: .top)
            }
            scrollAnchorOverride.wrappedValue = nil
        }
    }

    private func jumpToTodayButton(proxy: ScrollViewProxy) -> some View {
        Button {
            #if os(iOS)
            InteraLiquidGlassHaptics.selectionChanged()
            #endif
            withAnimation(LiquidGlassMotion.fluidSpring) {
                proxy.scrollTo(ConsumerBookingsTimelineProjection.todayHeaderID, anchor: .top)
            }
        } label: {
            Image(systemName: "sun.max.fill")
                .font(InteraFont.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.oliveGreen, Color.oliveGreen.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.oliveGreen.opacity(0.45), radius: 12, y: 6)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to today")
    }
}
