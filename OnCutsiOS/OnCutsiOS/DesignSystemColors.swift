//
//  DesignSystem+Colors.swift
//  OnCuts
//
//  Simplified 3-color system: White, Black, Olive Green
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {

    // MARK: - Adaptive shell (light: white / black text, dark: black / white text)

    #if canImport(UIKit)
    private static func onCutsDynamic(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
    #endif

    /// Page and window backdrop.
    static var onCutsShellBackground: Color {
        #if canImport(UIKit)
        onCutsDynamic(.white, .black)
        #else
        Color.white
        #endif
    }

    /// Primary copy and icons on the shell.
    static var onCutsShellForeground: Color {
        #if canImport(UIKit)
        onCutsDynamic(.black, .white)
        #else
        Color.primary
        #endif
    }

    static var onCutsShellForegroundSecondary: Color {
        #if canImport(UIKit)
        onCutsDynamic(UIColor.black.withAlphaComponent(0.65), UIColor.white.withAlphaComponent(0.82))
        #else
        Color.secondary
        #endif
    }

    static var onCutsShellForegroundTertiary: Color {
        #if canImport(UIKit)
        onCutsDynamic(UIColor.black.withAlphaComponent(0.45), UIColor.white.withAlphaComponent(0.64))
        #else
        Color.secondary.opacity(0.8)
        #endif
    }

    /// Frosted-surface rim on shell chrome.
    static var onCutsShellGlassStroke: Color {
        #if canImport(UIKit)
        onCutsDynamic(UIColor.black.withAlphaComponent(0.12), UIColor.white.withAlphaComponent(0.22))
        #else
        Color.secondary.opacity(0.25)
        #endif
    }

    // MARK: - Payment takeover (Card / Cash / tips on adaptive shell)

    private static let paymentCharcoalUIColor = UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1)

    /// Filled primary CTA (Card, Submit) — light: white on white shell; dark: near-white on black shell.
    static var paymentFilledButtonFill: Color {
        #if canImport(UIKit)
        onCutsDynamic(.white, UIColor(white: 0.94, alpha: 1))
        #else
        Color.white
        #endif
    }

    /// Label on ``paymentFilledButtonFill``.
    static var paymentFilledButtonLabel: Color {
        #if canImport(UIKit)
        onCutsDynamic(paymentCharcoalUIColor, UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1))
        #else
        Color.primary
        #endif
    }

    /// Outline CTA stroke and label (Cash).
    static var paymentOutlineButtonLabel: Color { onCutsShellForeground }

    /// Frosted card wash over ``Material`` on the payment / post-payment screens.
    static var paymentGlassWash: Color {
        #if canImport(UIKit)
        onCutsDynamic(UIColor.black.withAlphaComponent(0.04), UIColor.white.withAlphaComponent(0.14))
        #else
        Color.primary.opacity(0.06)
        #endif
    }

    /// Text field surface on payment review.
    static var paymentFieldBackground: Color {
        #if canImport(UIKit)
        onCutsDynamic(.white, UIColor(white: 0.16, alpha: 1))
        #else
        Color(.secondarySystemBackground)
        #endif
    }

    static var paymentFieldForeground: Color { onCutsShellForeground }

    static var paymentFieldPlaceholder: Color { onCutsShellForegroundTertiary }

    #if canImport(UIKit)
    /// Resolved text color for ``UITextView`` / ``TextEditor`` (SwiftUI `foregroundStyle` alone is often ignored).
    static var paymentFieldForegroundUIColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : paymentCharcoalUIColor
        }
    }
    #endif

    /// Selected tip chip on the payment screen (high contrast on light and dark shell).
    static var paymentTipSelectedFill: Color { oliveGreen }

    static var paymentTipSelectedLabel: Color {
        #if canImport(UIKit)
        Color.white
        #else
        Color.white
        #endif
    }

    static var paymentTipUnselectedStroke: Color {
        #if canImport(UIKit)
        onCutsDynamic(UIColor.black.withAlphaComponent(0.22), UIColor.white.withAlphaComponent(0.38))
        #else
        Color.secondary.opacity(0.4)
        #endif
    }
    
    // MARK: - Core 3 Colors
    
    /// Pure white - backgrounds, cards
    static let appWhite = Color.white
    
    /// Pure black - text, icons
    static let appBlack = Color.black
    
    /// Olive green - brand color. Lighter on light shell (`849E92`), darker on dark shell (`556860`).
    /// For **text**, prefer ``View/foregroundStyleOliveGreen(opacity:)`` so glyphs get an adaptive outline.
    static var oliveGreen: Color {
        #if canImport(UIKit)
        onCutsDynamic(Self.oliveGreenLightUIColor, Self.oliveGreenDarkUIColor)
        #else
        Color(hex: "849E92")
        #endif
    }

    /// Canonical mid olive — fixed reference (pre-adaptive default `6E9082`).
    static let oliveGreenBase = Color(hex: "6E9082")
    
    // MARK: - Olive Green Variations (for hover, pressed, disabled states)
    
    /// Lighter olive for hover / light-mode brand fill endpoint
    static let oliveLight = Color(hex: "849E92")
    /// Darker olive for pressed/active / dark-mode brand fill endpoint
    static let oliveDark = Color(hex: "556860")
    /// Very light olive for subtle backgrounds
    static let oliveTint = Color(hex: "F2F5F4")
    
    // MARK: - Black/White with Opacity (for practical UI needs)
    
    /// Light text on dark backgrounds
    static let textLight = Color.white
    /// Dark text on light backgrounds  
    static let textDark = Color.black
    /// Subtle text (appearance-aware).
    static var textSecondary: Color { onCutsShellForegroundSecondary }
    /// Placeholder text (appearance-aware).
    static var textTertiary: Color { onCutsShellForegroundTertiary }
    /// Disabled text
    static let textDisabled = Color.black.opacity(0.3)
    
    /// Subtle borders/dividers
    static let borderLight = Color.black.opacity(0.1)
    /// Medium borders
    static let borderMedium = Color.black.opacity(0.2)
    
    /// Page background (follows system appearance).
    static var backgroundPrimary: Color { onCutsShellBackground }
    /// Subtle background tint
    static let backgroundSecondary = Color(hex: "FAFAFA")
    
    #if canImport(UIKit)
    private static let oliveGreenLightUIColor = UIColor(red: 132 / 255, green: 158 / 255, blue: 146 / 255, alpha: 1)
    private static let oliveGreenDarkUIColor = UIColor(red: 85 / 255, green: 104 / 255, blue: 96 / 255, alpha: 1)

    /// UIKit resolved olive fill (matches ``oliveGreen``).
    static var oliveGreenUIColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? oliveGreenDarkUIColor : oliveGreenLightUIColor
        }
    }
    #endif

    // MARK: - Legacy Aliases (for gradual migration)
    // TODO: Remove these once all references are updated
    
    static var brand: Color { oliveGreen }
    static let brandDark = oliveDark
    static let brandLight = oliveLight

    // MARK: - Shell foreground aliases (formerly lava/cream; now appearance-aware)

    static var lavaShellCream: Color { onCutsShellForeground }
    static var lavaShellCreamSecondary: Color { onCutsShellForegroundSecondary }
    static var lavaShellCreamTertiary: Color { onCutsShellForegroundTertiary }
    static var lavaShellGlassStroke: Color { onCutsShellGlassStroke }
    
    static let neutral50 = backgroundSecondary
    static let neutral100 = backgroundSecondary
    static let neutral200 = borderLight
    static let neutral300 = borderMedium
    static let neutral400 = textTertiary
    static let neutral500 = textSecondary
    static let neutral600 = textDark
    static let neutral700 = textDark
    static let neutral800 = textDark
    static let neutral900 = textDark
    
    static var success: Color { oliveGreen }
    static var warning: Color { oliveGreen }
    static var error: Color { oliveGreen }
    static var info: Color { oliveGreen }
    
    static var statusPending: Color { oliveGreen }
    static var statusAccepted: Color { oliveGreen }
    static var statusCompleted: Color { oliveGreen }
    static let statusCancelled = textSecondary
    static let statusNoShow = textTertiary
    
    // MARK: - Helper Initializer
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Consumer shell appearance

extension View {
    /// Reserves a hook for app-wide shell styling; follows the user’s light/dark setting (no forced scheme).
    @ViewBuilder
    func onCutsConsumerShellAppearance() -> some View {
        onCutsPlatformTypography()
    }

    #if os(iOS)
    /// Keeps ``TextEditor`` typed text visible in dark mode (UIKit text color + caret).
    func onCutsAdaptiveTextEditorForeground(_ uiColor: UIColor = Color.paymentFieldForegroundUIColor) -> some View {
        foregroundStyle(Color(uiColor: uiColor))
            .background(OnCutsTextEditorForegroundSync(uiColor: uiColor))
    }
    #endif
}

#if os(iOS)

/// Walks the view hierarchy from a ``TextEditor`` sibling to set ``UITextView`` colors.
private struct OnCutsTextEditorForegroundSync: UIViewRepresentable {
    var uiColor: UIColor

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let textView = Self.findTextView(from: uiView) else { return }
            textView.textColor = uiColor
            textView.tintColor = uiColor
        }
    }

    private static func findTextView(from anchor: UIView) -> UITextView? {
        var current: UIView? = anchor.superview
        var hops = 0
        while hops < 28, let view = current {
            hops += 1
            if let textView = view as? UITextView { return textView }
            if let found = scanSubviews(view, budget: 12) { return found }
            current = view.superview
        }
        return nil
    }

    private static func scanSubviews(_ root: UIView, budget: Int) -> UITextView? {
        var remaining = budget
        var stack: [UIView] = root.subviews
        while !stack.isEmpty, remaining > 0 {
            remaining -= 1
            let view = stack.removeLast()
            if let textView = view as? UITextView { return textView }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }
}
#endif

/// Legacy no-op scrim — kept so existing `ZStack` layouts compile without an extra dim layer.
struct OnCutsLavaViewportScrimLayer: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}

