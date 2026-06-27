//
//  DesignSystem+Typography.swift
//  Intera
//
//  Intera typography — Inter Variable.
//

import SwiftUI

extension Font {
    
    // MARK: - Display (Largest headlines)
    
    static let displayLarge = InteraFont.displayLarge
    static let displayMedium = InteraFont.displayMedium
    static let displaySmall = InteraFont.displaySmall
    
    // MARK: - Headlines
    
    static let headlineLarge = InteraFont.headlineLarge
    static let headlineMedium = InteraFont.headlineMedium
    static let headlineSmall = InteraFont.headlineSmall
    
    // MARK: - Body Text
    
    static let bodyLarge = InteraFont.bodyLarge
    static let bodyMedium = InteraFont.bodyMedium
    static let bodySmall = InteraFont.bodySmall
    
    // MARK: - Labels (UI elements)
    
    static let labelLarge = InteraFont.labelLarge
    static let labelMedium = InteraFont.labelMedium
    static let labelSmall = InteraFont.labelSmall
    
    // MARK: - Captions
    
    static let caption = InteraFont.caption
    static let captionSmall = InteraFont.captionSmall
}

// MARK: - Text Styles (Custom ViewModifier)

struct AvilaPlatformsTextStyle: ViewModifier {
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
                    return .interaShellForeground
                case .bodyLarge, .bodyMedium, .bodySmall:
                    return .interaShellForegroundSecondary
                case .labelLarge, .labelMedium, .labelSmall:
                    return .interaShellForegroundSecondary
                case .caption, .captionSmall:
                    return .interaShellForegroundTertiary
                }
            }
            switch self {
            case .displayLarge, .displayMedium, .displaySmall,
                 .headlineLarge, .headlineMedium, .headlineSmall:
                return .interaShellForeground
            case .bodyLarge, .bodyMedium, .bodySmall:
                return .interaShellForegroundSecondary
            case .labelLarge, .labelMedium, .labelSmall:
                return .interaShellForegroundSecondary
            case .caption, .captionSmall:
                return .interaShellForegroundTertiary
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
    func avilaPlatformsStyle(_ style: AvilaPlatformsTextStyle.Style) -> some View {
        modifier(AvilaPlatformsTextStyle(style: style))
    }
}
