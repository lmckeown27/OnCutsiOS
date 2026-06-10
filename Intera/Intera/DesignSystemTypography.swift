//
//  DesignSystem+Typography.swift
//  Intera
//
//  CampusCuts typography system based on Source Serif 4
//

import SwiftUI

extension Font {
    
    // MARK: - Display (Largest headlines)
    
    static let displayLarge = Font.system(size: 36, weight: .bold, design: .serif)
    static let displayMedium = Font.system(size: 30, weight: .bold, design: .serif)
    static let displaySmall = Font.system(size: 24, weight: .semibold, design: .serif)
    
    // MARK: - Headlines
    
    static let headlineLarge = Font.system(size: 22, weight: .semibold, design: .serif)
    static let headlineMedium = Font.system(size: 20, weight: .semibold, design: .serif)
    static let headlineSmall = Font.system(size: 18, weight: .semibold, design: .serif)
    
    // MARK: - Body Text
    
    static let bodyLarge = Font.system(size: 16, weight: .medium, design: .serif)
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .serif)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .serif)
    
    // MARK: - Labels (UI elements)
    
    static let labelLarge = Font.system(size: 14, weight: .medium, design: .serif)
    static let labelMedium = Font.system(size: 12, weight: .medium, design: .serif)
    static let labelSmall = Font.system(size: 10, weight: .medium, design: .serif)
    
    // MARK: - Captions
    
    static let caption = Font.system(size: 12, weight: .regular, design: .serif)
    static let captionSmall = Font.system(size: 10, weight: .regular, design: .serif)
}

// MARK: - Text Styles (Custom ViewModifier)

struct CampusCutsTextStyle: ViewModifier {
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
    func campusCutsStyle(_ style: CampusCutsTextStyle.Style) -> some View {
        modifier(CampusCutsTextStyle(style: style))
    }
}
