//
//  GlassErrorToastOverlay.swift
//  Intera
//
//  Bottom glass-style toast driven by `AlertManager`.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private var toastErrorColor: Color {
    #if canImport(UIKit)
    Color(UIColor.systemRed)
    #else
    Color.red
    #endif
}

struct GlassErrorToastOverlay: View {
    @Bindable private var alertManager = AlertManager.shared

    private var errorGlow: Bool { alertManager.toastUsesErrorGlow }

    var body: some View {
        ZStack {
            Color.clear
                .allowsHitTesting(false)
            if let text = alertManager.toastMessage {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .shadow(color: errorGlow ? toastErrorColor.opacity(0.55) : .clear, radius: 8, x: 0, y: 0)
                        .shadow(color: errorGlow ? toastErrorColor.opacity(0.35) : .clear, radius: 16, x: 0, y: 0)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(
                                            errorGlow ? toastErrorColor.opacity(0.65) : Color.white.opacity(0.25),
                                            lineWidth: errorGlow ? 1.25 : 1
                                        )
                                }
                                .shadow(color: errorGlow ? toastErrorColor.opacity(0.45) : .black.opacity(0.12), radius: errorGlow ? 14 : 12, y: 4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(true)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: alertManager.toastMessage)
    }
}
