//
//  TimelineSectionHeader.swift
//  OnCuts
//
//  Pinned section chrome: no solid grey fills; optional translucent blur when content
//  scrolls underneath; Past / Today / Upcoming typography; short left-fading divider.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Scroll geometry (collected by `UnifiedTimelineView`)

enum TimelineScrollGeometry {
    /// Top edge of `LazyVStack` in `timelineScroll` — goes negative as the user scrolls down.
    struct ContentTopPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    /// Each header reports its minY in `timelineScroll` (pinned headers stay near 0).
    struct HeaderMinYPreferenceKey: PreferenceKey {
        static var defaultValue: [String: CGFloat] = [:]
        static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }
}

// MARK: - Header

struct TimelineSectionHeader: View {
    let position: TimelinePosition
    let headerID: String
    /// When true, draws `ultraThinMaterial` behind the title (content has scrolled under this pinned header).
    let showBackdropBlur: Bool

    private static var screenWidthForDivider: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.bounds.width
        #elseif os(macOS)
        NSScreen.main?.frame.width ?? 800
        #else
        400
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleView
            TimelineHeaderDividerLine(referenceWidth: Self.screenWidthForDivider)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, position == .today ? 6 : 4)
        .padding(.bottom, 12)
        .id(headerID)
        .background {
            Group {
                if showBackdropBlur {
                    Rectangle()
                        .fill(.clear)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TimelineScrollGeometry.HeaderMinYPreferenceKey.self,
                    value: [headerID: geo.frame(in: .named("timelineScroll")).minY]
                )
            }
        )
    }

    @ViewBuilder
    private var titleView: some View {
        switch position {
        case .past:
            Text("Past")
                .font(OnCutsFont.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(Color.lavaShellCreamSecondary)
                .textCase(.uppercase)
                .kerning(2.2)
        case .today:
            Text("Today")
                .font(OnCutsFont.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(Color.lavaShellCream)
        case .upcoming:
            Text("Upcoming")
                .font(OnCutsFont.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(Color.lavaShellCream)
        }
    }
}

// MARK: - Divider (~40% of screen width from leading edge, 1pt, fades to transparent)

private struct TimelineHeaderDividerLine: View {
    let referenceWidth: CGFloat

    var body: some View {
        let w = max(referenceWidth * 0.4, 1)
        LinearGradient(
            colors: [
                Color.lavaShellCream.opacity(0.5),
                Color.lavaShellCream.opacity(0.18),
                Color.clear,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: w, height: 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
