//
//  OnCutsOliveGreenTextStyle.swift
//  OnCuts
//
//  Appearance-aware primary text helpers (legacy name retained for call-site stability).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum OnCutsOliveGreenTextStyle {
    #if canImport(UIKit)
    static func plainAttributedString(_ text: String, font: UIFont, opacity: CGFloat = 1) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.label.withAlphaComponent(opacity),
        ])
    }
    #endif
}

#if canImport(UIKit)
/// UIKit label for multi-line shell copy using the system label color.
struct OnCutsOutlinedOliveGreenLabel: UIViewRepresentable {
    let text: String
    let font: UIFont
    var opacity: CGFloat = 1

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.backgroundColor = .clear
        label.isUserInteractionEnabled = false
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.font = font
        label.textColor = UIColor.label.withAlphaComponent(opacity)
        label.text = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        uiView.preferredMaxLayoutWidth = width
        return uiView.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
    }
}
#endif

extension View {
    /// Legacy hook — outline styling removed; returns content unchanged.
    @ViewBuilder
    func onCutsOliveGreenTextOutline(
        when isEnabled: Bool = true,
        width: CGFloat = 0
    ) -> some View {
        self
    }

    /// Primary foreground that follows the user's light/dark appearance.
    /// Use on **text** only — SF Symbols should use ``foregroundStyleOnCutsShellIcon()`` instead.
    func foregroundStyleOliveGreen(opacity: Double = 1) -> some View {
        foregroundStyle(Color.primary.opacity(opacity))
    }

    /// Appearance-aware icon tint (no olive outline). Prefer over ``foregroundStyleOliveGreen()`` on SF Symbols.
    func foregroundStyleOnCutsShellIcon() -> some View {
        foregroundStyle(Color.onCutsShellForeground)
    }

    /// De-emphasized shell icon tint for secondary glyphs (chevrons, pins, toolbar icons).
    func foregroundStyleOnCutsShellIconSecondary() -> some View {
        foregroundStyle(Color.onCutsShellForegroundSecondary)
    }
}
