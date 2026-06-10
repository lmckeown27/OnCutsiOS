//
//  PrimaryButton.swift
//  Intera
//
//  CampusCuts primary button component
//

import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var variant: Variant = .primary
    var size: Size = .medium
    
    enum Variant {
        case primary
        case secondary
        case outline
        case danger
        case ghost
        
        var backgroundColor: Color {
            switch self {
            case .primary: return .oliveGreen
            case .secondary: return .oliveTint
            case .outline: return .clear
            case .danger: return .oliveDark
            case .ghost: return .clear
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .textDark
            case .outline: return .oliveGreen
            case .danger: return .white
            case .ghost: return .oliveGreen
            }
        }
        
        var borderColor: Color? {
            switch self {
            case .outline: return .oliveGreen
            default: return nil
            }
        }
    }
    
    enum Size {
        case small, medium, large
        
        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 16
            case .large: return 24
            }
        }
        
        var verticalPadding: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 10
            case .large: return 14
            }
        }
        
        var fontSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 16
            case .large: return 18
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: .space2) {
                if isLoading {
                    ProgressView()
                        .tint(variant.foregroundColor)
                        .scaleEffect(0.8)
                }
                
                Text(title)
                    .font(.system(size: size.fontSize, weight: .medium, design: .serif))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(isDisabled ? Color.borderMedium : variant.backgroundColor)
            .foregroundStyle(isDisabled ? Color.textDisabled : variant.foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: .radiusMedium))
            .overlay {
                if let borderColor = variant.borderColor {
                    RoundedRectangle(cornerRadius: .radiusMedium)
                        .strokeBorder(borderColor, lineWidth: 1.5)
                }
            }
            // Outline / ghost use a clear interior; without this, taps only land on glyphs + stroke.
            .contentShape(RoundedRectangle(cornerRadius: .radiusMedium))
        }
        .buttonStyle(BookButtonStyle())
        .disabled(isDisabled || isLoading)
    }
}

// MARK: - Preview

#Preview("Button Variants") {
    VStack(spacing: .space4) {
        PrimaryButton(title: "Primary Button", action: {})
        
        PrimaryButton(title: "Secondary Button", action: {}, variant: .secondary)
        
        PrimaryButton(title: "Outline Button", action: {}, variant: .outline)
        
        PrimaryButton(title: "Danger Button", action: {}, variant: .danger)
        
        PrimaryButton(title: "Ghost Button", action: {}, variant: .ghost)
        
        PrimaryButton(title: "Loading...", action: {}, isLoading: true)
        
        PrimaryButton(title: "Disabled", action: {}, isDisabled: true)
    }
    .padding()
}

#Preview("Button Sizes") {
    VStack(spacing: .space4) {
        PrimaryButton(title: "Small Button", action: {}, size: .small)
        PrimaryButton(title: "Medium Button", action: {}, size: .medium)
        PrimaryButton(title: "Large Button", action: {}, size: .large)
    }
    .padding()
}
