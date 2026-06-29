//
//  InteraFont.swift
//  Intera
//
//  App-wide Inter Variable typography (`Fonts/InterVariable.ttf`).
//  Apply weight via the OpenType `wght` axis — not SwiftUI `.weight()` on a custom font
//  (that triggers "Unable to update Font Descriptor's weight" console noise).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum InteraFont {
    /// PostScript name for the Inter Variable font file bundled under `Fonts/`.
    private static let variableFontName = "InterVariable"
    /// OpenType axis tag for `wght` (Inter Variable).
    private static let weightVariationAxis = 2003265652

    static func installGlobalAppearanceIfNeeded() {
        #if canImport(UIKit)
        guard !didInstallAppearance else { return }
        didInstallAppearance = true

        let body = uiFont(size: 17, weight: .regular)
        let headline = uiFont(size: 17, weight: .semibold)
        let largeTitle = uiFont(size: 34, weight: .bold)

        UILabel.appearance().font = body
        UITextField.appearance().font = body
        UITextView.appearance().font = body

        let navBar = UINavigationBar.appearance()
        navBar.titleTextAttributes = [.font: headline]
        navBar.largeTitleTextAttributes = [.font: largeTitle]

        UITabBarItem.appearance().setTitleTextAttributes([.font: uiFont(size: 10, weight: .medium)], for: .normal)
        #endif
    }

    #if canImport(UIKit)
    private static var didInstallAppearance = false

    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> UIFont {
        let wght = openTypeWeightValue(weight)
        guard let base = UIFont(name: variableFontName, size: size) else {
            return UIFont.systemFont(ofSize: size, weight: uiKitWeight(weight))
        }

        let variationKey = UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute")
        let descriptor = base.fontDescriptor.addingAttributes([
            variationKey: [
                NSNumber(value: weightVariationAxis): NSNumber(value: wght),
            ],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
    #endif

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        #if canImport(UIKit)
        return Font(uiFont(size: size, weight: weight))
        #else
        return Font.custom(variableFontName, size: size)
        #endif
    }

    /// Drop-in for `Font.system(size:weight:design:)` — design is ignored; Inter Variable is always used.
    static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        font(size: size, weight: weight)
    }

    /// Drop-in for `Font.system(_:design:)` — design is ignored; Inter Variable is always used.
    static func system(_ style: Font.TextStyle, design: Font.Design = .default) -> Font {
        switch style {
        case .largeTitle: return largeTitle
        case .title: return title
        case .title2: return title2
        case .title3: return title3
        case .headline: return headline
        case .body: return body
        case .callout: return callout
        case .subheadline: return subheadline
        case .footnote: return footnote
        case .caption: return caption
        case .caption2: return caption2
        @unknown default: return body
        }
    }

    // MARK: - Semantic styles (mirror SwiftUI dynamic type)

    static var largeTitle: Font { font(size: 34, weight: .bold) }
    static var title: Font { font(size: 28, weight: .bold) }
    static var title2: Font { font(size: 22, weight: .bold) }
    static var title3: Font { font(size: 20, weight: .semibold) }
    static var headline: Font { font(size: 17, weight: .semibold) }
    static var body: Font { font(size: 17, weight: .regular) }
    static var callout: Font { font(size: 16, weight: .regular) }
    static var subheadline: Font { font(size: 15, weight: .regular) }
    static var footnote: Font { font(size: 13, weight: .regular) }
    static var caption: Font { font(size: 12, weight: .regular) }
    static var caption2: Font { font(size: 11, weight: .regular) }

    // MARK: - Weighted semantic styles (use instead of `.weight()` on custom Inter fonts)

    static func largeTitle(weight: Font.Weight = .bold) -> Font { font(size: 34, weight: weight) }
    static func title(weight: Font.Weight = .bold) -> Font { font(size: 28, weight: weight) }
    static func title2(weight: Font.Weight = .bold) -> Font { font(size: 22, weight: weight) }
    static func title3(weight: Font.Weight = .semibold) -> Font { font(size: 20, weight: weight) }
    static func headline(weight: Font.Weight = .semibold) -> Font { font(size: 17, weight: weight) }
    static func body(weight: Font.Weight = .regular) -> Font { font(size: 17, weight: weight) }
    static func callout(weight: Font.Weight = .regular) -> Font { font(size: 16, weight: weight) }
    static func subheadline(weight: Font.Weight = .regular) -> Font { font(size: 15, weight: weight) }
    static func footnote(weight: Font.Weight = .regular) -> Font { font(size: 13, weight: weight) }
    static func caption(weight: Font.Weight = .regular) -> Font { font(size: 12, weight: weight) }
    static func caption2(weight: Font.Weight = .regular) -> Font { font(size: 11, weight: weight) }

    // MARK: - Design system aliases

    static var displayLarge: Font { font(size: 36, weight: .bold) }
    static var displayMedium: Font { font(size: 30, weight: .bold) }
    static var displaySmall: Font { font(size: 24, weight: .semibold) }
    static var headlineLarge: Font { font(size: 22, weight: .semibold) }
    static var headlineMedium: Font { font(size: 20, weight: .semibold) }
    static var headlineSmall: Font { font(size: 18, weight: .semibold) }
    static var bodyLarge: Font { font(size: 16, weight: .medium) }
    static var bodyMedium: Font { font(size: 14, weight: .regular) }
    static var bodySmall: Font { font(size: 12, weight: .regular) }
    static var labelLarge: Font { font(size: 14, weight: .medium) }
    static var labelMedium: Font { font(size: 12, weight: .medium) }
    static var labelSmall: Font { font(size: 10, weight: .medium) }
    static var captionSmall: Font { font(size: 10, weight: .regular) }

    static func headlineLarge(weight: Font.Weight = .semibold) -> Font { font(size: 22, weight: weight) }
    static func headlineMedium(weight: Font.Weight = .semibold) -> Font { font(size: 20, weight: weight) }
    static func headlineSmall(weight: Font.Weight = .semibold) -> Font { font(size: 18, weight: weight) }
    static func bodyLarge(weight: Font.Weight = .medium) -> Font { font(size: 16, weight: weight) }
    static func bodyMedium(weight: Font.Weight = .medium) -> Font { font(size: 14, weight: weight) }
    static func bodySmall(weight: Font.Weight = .regular) -> Font { font(size: 12, weight: weight) }
    static func labelLarge(weight: Font.Weight = .medium) -> Font { font(size: 14, weight: weight) }
    static func labelMedium(weight: Font.Weight = .medium) -> Font { font(size: 12, weight: weight) }
    static func labelSmall(weight: Font.Weight = .medium) -> Font { font(size: 10, weight: weight) }

    #if canImport(UIKit)
    private static func uiKitWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
    #endif

    private static func openTypeWeightValue(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: return 200
        case .thin: return 250
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }

    private static func relativeStyle(forSize size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: return .caption2
        case ..<13: return .caption
        case ..<16: return .footnote
        case ..<18: return .body
        case ..<21: return .title3
        case ..<29: return .title2
        default: return .title
        }
    }
}

extension View {
    /// Applies Inter Variable as the default font for descendant `Text` and UIKit-backed controls.
    func interaPlatformTypography() -> some View {
        self
            .environment(\.font, InteraFont.body)
            .onAppear { InteraFont.installGlobalAppearanceIfNeeded() }
    }

    /// Legacy name — use ``interaPlatformTypography()``.
    func interaClarendonTypography() -> some View {
        interaPlatformTypography()
    }
}
