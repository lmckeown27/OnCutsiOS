//
//  InteraLiquidGlass.swift
//  Intera
//
//  Shared “Intera Liquid Glass”: animated mesh backdrop + frosted surfaces.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Haptics

enum InteraLiquidGlassHaptics {
    #if os(iOS)
    private static let selectionGen = UISelectionFeedbackGenerator()
    static func selectionChanged() {
        selectionGen.prepare()
        selectionGen.selectionChanged()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    #else
    static func selectionChanged() {}
    static func notification(_ type: Int) {}
    #endif
}

// MARK: - Typography (Clarendon / Superclarendon)

enum InteraLiquidGlassTypography {
    static func title(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        InteraFont.font(size: size, weight: weight)
    }

    static var navigationTitle: Font { title(17, weight: .semibold) }

    static var body: Font { InteraFont.body }
}

// MARK: - Mesh backdrop (Midnight → Deep Indigo)

private enum InteraMeshPalette {
    static let midnight = Color(red: 0.04, green: 0.05, blue: 0.12)
    static let deep = Color(red: 0.07, green: 0.09, blue: 0.22)
    static let indigo = Color(red: 0.12, green: 0.14, blue: 0.38)
}

private enum InteraCreateAccountMeshPalette {
    static let abyss = Color(red: 0.02, green: 0.08, blue: 0.14)
    static let teal = Color(red: 0.05, green: 0.35, blue: 0.38)
    static let blue = Color(red: 0.08, green: 0.22, blue: 0.48)
}

/// Sign-in vs create-account ambient mesh (animated on iOS 18+).
enum InteraAuthFlowMeshVariant: Equatable {
    case signIn
    case createAccount
}

struct InteraLiquidMeshBackground: View {
    var body: some View {
        InteraAuthFlowMeshBackground(variant: .signIn)
    }
}

struct InteraAuthFlowMeshBackground: View {
    var variant: InteraAuthFlowMeshVariant

    var body: some View {
        Group {
            if #available(iOS 18.0, macOS 15.0, *) {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { ctx in
                    InteraMeshGradientAnimatedPhase(date: ctx.date, variant: variant)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                switch variant {
                case .signIn:
                    LinearGradient(
                        colors: [
                            InteraMeshPalette.midnight,
                            InteraMeshPalette.indigo,
                            InteraMeshPalette.deep,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                case .createAccount:
                    LinearGradient(
                        colors: [
                            InteraCreateAccountMeshPalette.abyss,
                            InteraCreateAccountMeshPalette.blue,
                            InteraCreateAccountMeshPalette.teal,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.55), value: variant)
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct InteraMeshGradientAnimatedPhase: View {
    let date: Date
    var variant: InteraAuthFlowMeshVariant

    var body: some View {
        let t = Float(date.timeIntervalSinceReferenceDate)
        let mesh = InteraMeshGradientBuilder.mesh(at: t, variant: variant)
        MeshGradient(width: 3, height: 3, points: mesh.locations, colors: mesh.colors)
    }
}

@available(iOS 18.0, macOS 15.0, *)
private enum InteraMeshGradientBuilder {
    static func mesh(at t: Float, variant: InteraAuthFlowMeshVariant) -> (locations: [SIMD2<Float>], colors: [Color]) {
        func w(_ x: Float, _ y: Float) -> Float {
            0.02 * sin(t * 0.7 + x * 4) + 0.015 * cos(t * 0.5 + y * 3)
        }
        let locs: [SIMD2<Float>] = [
            SIMD2(0 + w(0, 0), 0 + w(0.2, 0.1)),
            SIMD2(0.5 + w(0.5, 0), 0 + w(0.3, 0.2)),
            SIMD2(1 + w(0.8, 0), 0 + w(0.1, 0.3)),
            SIMD2(0 + w(0.1, 0.5), 0.5 + w(0.4, 0.4)),
            SIMD2(0.5 + w(0.5, 0.5), 0.5 + w(0.5, 0.5)),
            SIMD2(1 + w(0.9, 0.5), 0.5 + w(0.6, 0.4)),
            SIMD2(0 + w(0.2, 1), 1 + w(0.3, 0.8)),
            SIMD2(0.5 + w(0.5, 1), 1 + w(0.5, 0.9)),
            SIMD2(1 + w(0.8, 1), 1 + w(0.7, 0.7)),
        ]
        let cols: [Color]
        switch variant {
        case .signIn:
            cols = [
                InteraMeshPalette.midnight,
                InteraMeshPalette.deep,
                InteraMeshPalette.indigo,
                InteraMeshPalette.deep,
                InteraMeshPalette.midnight,
                InteraMeshPalette.deep,
                InteraMeshPalette.indigo,
                InteraMeshPalette.deep,
                InteraMeshPalette.midnight,
            ]
        case .createAccount:
            cols = [
                InteraCreateAccountMeshPalette.abyss,
                InteraCreateAccountMeshPalette.teal,
                InteraCreateAccountMeshPalette.blue,
                InteraCreateAccountMeshPalette.teal,
                InteraCreateAccountMeshPalette.abyss,
                InteraCreateAccountMeshPalette.blue,
                InteraCreateAccountMeshPalette.teal,
                InteraCreateAccountMeshPalette.blue,
                InteraCreateAccountMeshPalette.abyss,
            ]
        }
        return (locs, cols)
    }
}

// MARK: - Glass surface (20pt radius, 1px white @ 20%)

struct InteraGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.lavaShellGlassStroke, lineWidth: 1)
            }
    }
}

extension View {
    func interaGlassSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(InteraGlassSurface(cornerRadius: cornerRadius))
    }
}
