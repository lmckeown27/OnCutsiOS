//
//  BookButtonPressStyle.swift
//  OnCuts
//
//  Shared press scale + timing for provider **Book** CTA, live booking controls, and `PrimaryButton`.
//

import SwiftUI

/// Fixed press depth (0.95); **easeInOut** so taps and holds look the same (no spring overshoot).
struct BookButtonPressAppearance: ViewModifier {
    var isPressed: Bool
    var isEnabled: Bool = true

    private static let pressAnimation = Animation.easeInOut(duration: 0.14)

    func body(content: Content) -> some View {
        content
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(Self.pressAnimation, value: isPressed)
    }
}

/// Standard `ButtonStyle` matching the provider detail Book control (see `BookButtonPressAppearance`).
struct BookButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(BookButtonPressAppearance(isPressed: configuration.isPressed, isEnabled: isEnabled))
    }
}

#if DEBUG
#Preview("BookButtonStyle") {
    Button("Book") { }
        .buttonStyle(BookButtonStyle())
        .padding()
}
#endif
