//
//  OnCutsOliveGreenTextStyle.swift
//  OnCuts
//
//  Olive-green foreground with an adaptive glyph outline (black in light mode, white in dark mode).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum OnCutsOliveGreenTextStyle {
    /// Negative stroke width draws an outline around the fill (UIKit attributed-string technique).
    static let uiKitOutlineStrokeWidth: CGFloat = -0.85
    /// Shadow offset for SwiftUI `Text` / symbol outlines.
    static let swiftUIOutlineWidth: CGFloat = 0.22
    /// Outline strength (shadow / stroke reads lighter below 1).
    static let outlineOpacity: CGFloat = 0.72
    /// Extra point size for UIKit outlined labels (`OnCutsOutlinedOliveGreenLabel`).
    static let uiKitFontSizeIncrease: CGFloat = 2

    static func outlineColor(for colorScheme: ColorScheme) -> Color {
        (colorScheme == .dark ? Color.white : Color.black)
            .opacity(Double(outlineOpacity))
    }

    /// One dynamic-type step up so olive-green copy reads slightly larger platform-wide.
    static func bumpedDynamicTypeSize(from size: DynamicTypeSize) -> DynamicTypeSize {
        switch size {
        case .xSmall: return .small
        case .small: return .medium
        case .medium: return .large
        case .large: return .xLarge
        case .xLarge: return .xxLarge
        case .xxLarge: return .xxxLarge
        case .xxxLarge: return .xxxLarge
        case .accessibility1: return .accessibility2
        case .accessibility2: return .accessibility3
        case .accessibility3: return .accessibility4
        case .accessibility4: return .accessibility5
        case .accessibility5: return .accessibility5
        @unknown default: return size
        }
    }

    static func bumpedUIFont(_ font: UIFont) -> UIFont {
        font.withSize(font.pointSize + uiKitFontSizeIncrease)
    }

    #if canImport(UIKit)
    static var fillUIColor: UIColor {
        Color.oliveGreenUIColor
    }

    static var outlineUIColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .black
        }
    }

    static func attributedString(_ text: String, font: UIFont, opacity: CGFloat = 1) -> NSAttributedString {
        let fill = fillUIColor.withAlphaComponent(opacity)
        let stroke = outlineUIColor.withAlphaComponent(outlineOpacity)
        return NSAttributedString(string: text, attributes: [
            .font: bumpedUIFont(font),
            .foregroundColor: fill,
            .strokeColor: stroke,
            .strokeWidth: uiKitOutlineStrokeWidth,
        ])
    }
    #endif
}

#if canImport(UIKit)
/// UIKit label for multi-line olive-green copy with an adaptive outline.
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
        label.attributedText = OnCutsOliveGreenTextStyle.attributedString(text, font: font, opacity: opacity)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        uiView.preferredMaxLayoutWidth = width
        return uiView.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
    }
}
#endif

private struct OnCutsOliveGreenTextOutlineModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var width: CGFloat = OnCutsOliveGreenTextStyle.swiftUIOutlineWidth
    var isEnabled: Bool = true

    private var outlineColor: Color {
        OnCutsOliveGreenTextStyle.outlineColor(for: colorScheme)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .dynamicTypeSize(OnCutsOliveGreenTextStyle.bumpedDynamicTypeSize(from: dynamicTypeSize))
                .shadow(color: outlineColor, radius: 0, x: -width, y: 0)
                .shadow(color: outlineColor, radius: 0, x: width, y: 0)
                .shadow(color: outlineColor, radius: 0, x: 0, y: -width)
                .shadow(color: outlineColor, radius: 0, x: 0, y: width)
                .shadow(color: outlineColor, radius: 0, x: -width, y: -width)
                .shadow(color: outlineColor, radius: 0, x: width, y: -width)
                .shadow(color: outlineColor, radius: 0, x: -width, y: width)
                .shadow(color: outlineColor, radius: 0, x: width, y: width)
        } else {
            content
        }
    }
}

extension View {
    /// Applies a black (light) or white (dark) glyph outline for olive-green foreground content.
    @ViewBuilder
    func onCutsOliveGreenTextOutline(
        when isEnabled: Bool = true,
        width: CGFloat = OnCutsOliveGreenTextStyle.swiftUIOutlineWidth
    ) -> some View {
        modifier(OnCutsOliveGreenTextOutlineModifier(width: width, isEnabled: isEnabled))
    }

    /// Olive-green foreground with an adaptive outline and slightly larger type for legibility.
    /// Use on **text** only — SF Symbols should use ``foregroundStyleOnCutsShellIcon()`` instead.
    func foregroundStyleOliveGreen(opacity: Double = 1) -> some View {
        foregroundStyle(Color.oliveGreen.opacity(opacity))
            .onCutsOliveGreenTextOutline()
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
