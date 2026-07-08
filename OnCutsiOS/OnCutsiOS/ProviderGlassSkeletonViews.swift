//
//  ProviderGlassSkeletonViews.swift
//  Intera
//
//  Shimmering glass placeholders that mirror `ServiceProviderCard` layout during `.loading`.
//

import SwiftUI

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.05),
                        ],
                        startPoint: .init(x: phase - 0.5, y: 0.5),
                        endPoint: .init(x: phase + 0.5, y: 0.5)
                    )
                    .blendMode(.overlay)
                    .frame(width: geo.size.width * 2, height: geo.size.height)
                }
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

/// One row shaped like a provider card (avatar + text blocks).
struct ProviderGlassSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.22))
                .frame(width: 72, height: 72)
                .modifier(ShimmerModifier())

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                    .modifier(ShimmerModifier())
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 12)
                    .frame(maxWidth: 220, alignment: .leading)
                    .modifier(ShimmerModifier())
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 12)
                    .frame(maxWidth: 180, alignment: .leading)
                    .modifier(ShimmerModifier())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

struct ProviderGlassSkeletonList: View {
    var rowCount: Int = 5

    var body: some View {
        VStack(spacing: 16) {
            ForEach(0 ..< rowCount, id: \.self) { _ in
                ProviderGlassSkeletonRow()
            }
        }
        .padding(.top, .space6)
    }
}
