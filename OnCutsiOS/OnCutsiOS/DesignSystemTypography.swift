//
//  DesignSystem+Typography.swift
//  OnCuts
//
//  OnCuts typography — Inter Variable.
//

import SwiftUI

extension Font {
    
    // MARK: - Display (Largest headlines)
    
    static let displayLarge = OnCutsFont.displayLarge
    static let displayMedium = OnCutsFont.displayMedium
    static let displaySmall = OnCutsFont.displaySmall
    
    // MARK: - Headlines
    
    static let headlineLarge = OnCutsFont.headlineLarge
    static let headlineMedium = OnCutsFont.headlineMedium
    static let headlineSmall = OnCutsFont.headlineSmall
    
    // MARK: - Body Text
    
    static let bodyLarge = OnCutsFont.bodyLarge
    static let bodyMedium = OnCutsFont.bodyMedium
    static let bodySmall = OnCutsFont.bodySmall
    
    // MARK: - Labels (UI elements)
    
    static let labelLarge = OnCutsFont.labelLarge
    static let labelMedium = OnCutsFont.labelMedium
    static let labelSmall = OnCutsFont.labelSmall
    
    // MARK: - Captions
    
    static let caption = OnCutsFont.caption
    static let captionSmall = OnCutsFont.captionSmall
}

// MARK: - Text Styles (Custom ViewModifier)

struct OnCutsTextStyle: ViewModifier {
    enum Style {
        case displayLarge, displayMedium, displaySmall
        case headlineLarge, headlineMedium, headlineSmall
        case bodyLarge, bodyMedium, bodySmall
        case labelLarge, labelMedium, labelSmall
        case caption, captionSmall
        
        var font: Font {
            switch self {
            case .displayLarge: return .displayLarge
            case .displayMedium: return .displayMedium
            case .displaySmall: return .displaySmall
            case .headlineLarge: return .headlineLarge
            case .headlineMedium: return .headlineMedium
            case .headlineSmall: return .headlineSmall
            case .bodyLarge: return .bodyLarge
            case .bodyMedium: return .bodyMedium
            case .bodySmall: return .bodySmall
            case .labelLarge: return .labelLarge
            case .labelMedium: return .labelMedium
            case .labelSmall: return .labelSmall
            case .caption: return .caption
            case .captionSmall: return .captionSmall
            }
        }
        
        func color(for colorScheme: ColorScheme) -> Color {
            if colorScheme == .dark {
                switch self {
                case .displayLarge, .displayMedium, .displaySmall,
                     .headlineLarge, .headlineMedium, .headlineSmall:
                    return .onCutsShellForeground
                case .bodyLarge, .bodyMedium, .bodySmall:
                    return .onCutsShellForegroundSecondary
                case .labelLarge, .labelMedium, .labelSmall:
                    return .onCutsShellForegroundSecondary
                case .caption, .captionSmall:
                    return .onCutsShellForegroundTertiary
                }
            }
            switch self {
            case .displayLarge, .displayMedium, .displaySmall,
                 .headlineLarge, .headlineMedium, .headlineSmall:
                return .onCutsShellForeground
            case .bodyLarge, .bodyMedium, .bodySmall:
                return .onCutsShellForegroundSecondary
            case .labelLarge, .labelMedium, .labelSmall:
                return .onCutsShellForegroundSecondary
            case .caption, .captionSmall:
                return .onCutsShellForegroundTertiary
            }
        }
    }
    
    let style: Style
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .font(style.font)
            .foregroundStyle(style.color(for: colorScheme))
    }
}

extension View {
    func onCutsStyle(_ style: OnCutsTextStyle.Style) -> some View {
        modifier(OnCutsTextStyle(style: style))
    }
}
