//
//  InteraFont.swift
//  Intera
//
//  App-wide Clarendon typography (Superclarendon family).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum InteraFont {
    /// PostScript names in `Fonts/SuperClarendon.ttc`.
    private static let regularName = "Superclarendon-Regular"
    private static let lightName = "Superclarendon-Light"
    private static let boldName = "Superclarendon-Bold"
    private static let blackName = "Superclarendon-Black"

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
        let name = postScriptName(for: weight)
        if let font = UIFont(name: name, size: size) {
            return font
        }
        return UIFont.systemFont(ofSize: size, weight: uiKitWeight(weight))
    }
    #endif

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(postScriptName(for: weight), size: size, relativeTo: relativeStyle(forSize: size))
    }

    /// Drop-in for `Font.system(size:weight:design:)` — design is ignored; Clarendon is always used.
    static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        font(size: size, weight: weight)
    }

    /// Drop-in for `Font.system(_:design:)` — design is ignored; Clarendon is always used.
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

    private static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light:
            return lightName
        case .bold, .semibold, .heavy:
            return boldName
        case .black:
            return blackName
        default:
            return regularName
        }
    }

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
    /// Applies Clarendon as the default font for descendant `Text` and UIKit-backed controls.
    func interaClarendonTypography() -> some View {
        self
            .environment(\.font, InteraFont.body)
            .onAppear { InteraFont.installGlobalAppearanceIfNeeded() }
    }
}
