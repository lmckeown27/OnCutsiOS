//
//  LiquidGlassCompat.swift
//  OnCuts
//
//  Wraps Apple’s Liquid Glass APIs (iOS 26+) with material / solid fallbacks so the
//  project keeps a single deployment target below 26 where needed.
//
//  System surfaces (navigation bars, tab bars, sheets presented with `.sheet`) pick up
//  Liquid Glass automatically when you build with the iOS 26 SDK; this file is for
//  custom components (overlays, tab strips, search fields).
//

import SwiftUI

#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Persistent list blur (under glass detail)

/// UIKit-driven blur so the backdrop does not revert to a sharp list when SwiftUI re-rasterizes after
/// `AsyncImage` loads, `LazyVStack` updates, etc.
#if os(iOS) || os(tvOS)
struct ServiceProviderListPersistentBlurBackdrop: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        view.isUserInteractionEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
#elseif os(macOS)
struct ServiceProviderListPersistentBlurBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#else
/// Fallback for platforms without the above (e.g. visionOS): best-effort material.
struct ServiceProviderListPersistentBlurBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
    }
}
#endif

/// Full-screen frosted dim **between** the browse stack and the glass detail panel.
///
/// Combines layers so it works both **inside** `GlassEffectContainer` (for `glassEffectID` morph with cards)
/// and as a standalone overlay:
/// - **SwiftUI** `Material` composites reliably with the Liquid Glass pipeline.
/// - **UIKit / AppKit** `UIVisualEffectView` keeps sampling stable when the list re-rasterizes (`AsyncImage`, etc.).
struct ServiceProviderLiquidGlassListBlurStack: View {
    var body: some View {
        ZStack {
            ServiceProviderListPersistentBlurBackdrop()
            Rectangle()
                .fill(Material.ultraThick)
            Color.black.opacity(0.46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .allowsHitTesting(true)
    }
}

// MARK: - Motion (Liquid Glass transitions)

enum LiquidGlassMotion {
    /// Tuned to feel close to system fluid sheet transitions.
    static let fluidSpring = Animation.spring(response: 0.55, dampingFraction: 0.82)
}

// MARK: - Colorful backdrop (glass reads “flat” without refractive content behind it)

/// Saturated mesh behind `GlassEffectContainer` on iOS 26+; **time-aware** when a today booking highlight exists.
struct ServiceProviderBrowseMeshBackdrop: View {
    /// When set, shifts palette (teal / amber) and speeds up subtle mesh motion near the appointment.
    var homeBookingHighlight: HomeTodayBookingHighlight? = nil

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Group {
            if #available(iOS 18.0, macOS 15.0, *) {
                TimelineView(.animation(
                    minimumInterval: timelineTickInterval,
                    paused: false
                )) { timeline in
                    meshGradient(phaseDate: timeline.date)
                }
            } else {
                fallbackLinearGradient()
            }
        }
    }

    /// Faster ticks when a booking highlight exists so urgent / mesh motion can react without a fixed schedule type.
    private var timelineTickInterval: TimeInterval {
        if accessibilityReduceMotion { return 1.2 }
        return homeBookingHighlight != nil ? 0.1 : 2.5
    }

    @available(iOS 18.0, macOS 15.0, *)
    private func meshGradient(phaseDate: Date) -> some View {
        let accent = homeBookingHighlight.map { $0.meshAccent(at: phaseDate) } ?? .calm
        let t = Float(phaseDate.timeIntervalSinceReferenceDate)
        let speed: Float = accent == .urgent ? 2.4 : (accent == .today ? 0.9 : 0.35)
        let w = accessibilityReduceMotion ? 0 : sin(t * speed) * (accent == .urgent ? 0.045 : 0.022)

        let points: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.48 + w), SIMD2(0.55 + w * 0.6, 0.42 - w * 0.3), SIMD2(1, 0.52 - w),
            SIMD2(0, 1), SIMD2(0.45 + w * 0.2, 1), SIMD2(1, 1),
        ]

        return MeshGradient(width: 3, height: 3, points: points, colors: meshColors(accent: accent))
    }

    private func meshColors(accent: HomeBookingMeshAccent) -> [Color] {
        switch accent {
        case .calm:
            return [
                Color(red: 0.12, green: 0.18, blue: 0.42),
                Color(red: 0.22, green: 0.28, blue: 0.58),
                Color(red: 0.18, green: 0.22, blue: 0.48),
                Color(red: 0.28, green: 0.32, blue: 0.62),
                Color(red: 0.35, green: 0.28, blue: 0.72),
                Color(red: 0.2, green: 0.36, blue: 0.55),
                Color(red: 0.25, green: 0.3, blue: 0.58),
                Color(red: 0.32, green: 0.26, blue: 0.68),
                Color(red: 0.2, green: 0.34, blue: 0.52),
            ]
        case .today:
            return [
                Color(red: 0.14, green: 0.22, blue: 0.46),
                Color(red: 0.95, green: 0.62, blue: 0.22),
                Color(red: 0.18, green: 0.42, blue: 0.52),
                Color(red: 0.92, green: 0.55, blue: 0.28),
                Color(red: 0.22, green: 0.36, blue: 0.58),
                Color(red: 0.2, green: 0.72, blue: 0.68),
                Color(red: 0.88, green: 0.5, blue: 0.24),
                Color(red: 0.28, green: 0.32, blue: 0.62),
                Color(red: 0.18, green: 0.5, blue: 0.55),
            ]
        case .urgent:
            return [
                Color(red: 0.18, green: 0.26, blue: 0.5),
                Color(red: 0.98, green: 0.58, blue: 0.18),
                Color(red: 0.16, green: 0.48, blue: 0.55),
                Color(red: 0.95, green: 0.48, blue: 0.2),
                Color(red: 0.12, green: 0.62, blue: 0.58),
                Color(red: 0.9, green: 0.42, blue: 0.22),
                Color(red: 0.22, green: 0.38, blue: 0.55),
                Color(red: 0.85, green: 0.38, blue: 0.2),
                Color(red: 0.2, green: 0.55, blue: 0.52),
            ]
        }
    }

    private func fallbackLinearGradient() -> some View {
        let accent = homeBookingHighlight.map { $0.meshAccent(at: Date()) } ?? .calm
        let colors: [Color] = accent == .calm
            ? [Color(red: 0.15, green: 0.22, blue: 0.5), Color(red: 0.25, green: 0.2, blue: 0.45)]
            : [Color(red: 0.18, green: 0.35, blue: 0.52), Color(red: 0.9, green: 0.5, blue: 0.25), Color(red: 0.2, green: 0.58, blue: 0.55)]
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    /// Large rounded panel (e.g. provider detail overlay). iOS 26+: `glassEffect`; earlier: thin material.
    @ViewBuilder
    func liquidGlassSheetChrome(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            // `.interactive()` is required so embedded controls (e.g. provider detail Book) receive touches; plain `.regular` can read as inert.
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
    
    /// Segmented tab strip (`TabPicker`). iOS 26+: interactive glass; earlier: white bar.
    @ViewBuilder
    func liquidGlassTabPickerChrome(cornerRadius: CGFloat = 14) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(Color.white)
        }
    }
    
    /// Search field capsule. iOS 26+: glass; earlier: system gray / neutral fill.
    /// iPad: `glassEffect` on embedded `TextField` often composites as a flat bright slab; use material so the field reads frosted, not white.
    @ViewBuilder
    func liquidGlassSearchFieldChrome(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            #if canImport(UIKit) && !os(watchOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                self
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
            #else
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            #endif
        } else {
            self.background {
                #if canImport(UIKit)
                Color(uiColor: .systemGray6)
                #else
                Color.neutral100
                #endif
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
    
    /// Second frosted layer on the provider footer; redundant once the sheet uses Liquid Glass.
    @ViewBuilder
    func liquidGlassProviderFooterBackdrop() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
        } else {
            self.background(.ultraThinMaterial)
        }
    }
}
