//
//  PrimaryButton.swift
//  Intera
//
//  AvilaPlatforms primary button component
//

import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var variant: Variant = .primary
    var size: Size = .medium
    var shape: Shape = .rounded
    var isFullWidth: Bool = true
    /// Dark glyph outline around the label (primary variant: white fill on olive).
    var titleUsesOutline: Bool = false
    
    enum Shape {
        case rounded
        case pill
    }
    
    enum Variant {
        case primary
        case secondary
        case outline
        case danger
        case ghost
        /// Cream fill + dark label for CTAs on the lava booking shell (matches provider **Book**).
        case shell
        
        var backgroundColor: Color {
            switch self {
            case .primary: return .oliveGreen
            case .secondary: return .oliveTint
            case .outline: return .clear
            case .danger: return .oliveDark
            case .ghost: return .clear
            case .shell: return .lavaShellCream
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .textDark
            case .outline: return .oliveGreen
            case .danger: return .white
            case .ghost: return .oliveGreen
            case .shell: return .interaShellBackground
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
        case small, medium, large, footer, prominent
        
        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 16
            case .large: return 24
            case .footer: return 14
            case .prominent: return 16
            }
        }
        
        var verticalPadding: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 10
            case .large: return 14
            case .footer: return 5
            case .prominent: return 12
            }
        }
        
        var fontSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 16
            case .large: return 18
            case .footer: return 18
            case .prominent: return 28
            }
        }

        var fontWeight: Font.Weight {
            switch self {
            case .prominent: return .bold
            case .footer: return .semibold
            default: return .medium
            }
        }

        var fontDesign: Font.Design {
            switch self {
            case .prominent, .footer: return .default
            default: return .serif
            }
        }

        var minHeight: CGFloat? {
            switch self {
            case .footer: return 40
            case .prominent: return 54
            default: return nil
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .footer: return 10
            case .prominent: return 14
            default: return .radiusMedium
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            buttonLabel
                .interaOliveGreenTextOutline(when: !isDisabled && (variant == .outline || variant == .ghost))
                .interaFilledPrimaryButtonLabelOutline(
                    when: !isDisabled && titleUsesOutline && variant == .primary && size != .prominent
                )
                .modifier(PrimaryButtonShapeModifier(
                    shape: shape,
                    borderColor: variant.borderColor,
                    cornerRadius: size.cornerRadius
                ))
        }
        .buttonStyle(BookButtonStyle())
        .disabled(isDisabled || isLoading)
        .fixedSize(horizontal: false, vertical: size == .prominent || size == .footer)
    }

    private var buttonLabel: some View {
        HStack(spacing: .space2) {
            if isLoading {
                ProgressView()
                    .tint(variant.foregroundColor)
                    .scaleEffect(0.8)
            }

            Group {
                if titleUsesOutline && size == .prominent {
                    prominentOutlinedTitleLabel
                } else {
                    Text(title)
                        .font(InteraFont.system(size: size.fontSize, weight: size.fontWeight, design: size.fontDesign))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: isFullWidth ? .infinity : nil)
        .frame(minHeight: size.minHeight)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(isDisabled ? Color.borderMedium : variant.backgroundColor)
        .foregroundStyle(isDisabled ? Color.textDisabled : variant.foregroundColor)
    }

    private var prominentOutlinedTitleLabel: some View {
        Text(title)
            .font(InteraFont.system(size: size.fontSize, weight: size.fontWeight, design: size.fontDesign))
            .lineLimit(2)
            .minimumScaleFactor(0.78)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .interaFilledPrimaryButtonLabelOutline(when: true, width: 0.58, opacity: 0.96, strong: true)
    }
}

private struct InteraFilledPrimaryButtonLabelOutlineModifier: ViewModifier {
    var isEnabled: Bool
    var width: CGFloat = 0.48
    var opacity: CGFloat = 0.88
    var strong: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            let outline = Color.black.opacity(opacity)
            if strong {
                content
                    .modifier(InteraGlyphOutlineShadows(color: outline, width: width))
                    .modifier(InteraGlyphOutlineShadows(color: outline, width: width * 0.62))
            } else {
                content
                    .modifier(InteraGlyphOutlineShadows(color: outline, width: width))
            }
        } else {
            content
        }
    }
}

private struct InteraGlyphOutlineShadows: ViewModifier {
    let color: Color
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color, radius: 0, x: -width, y: 0)
            .shadow(color: color, radius: 0, x: width, y: 0)
            .shadow(color: color, radius: 0, x: 0, y: -width)
            .shadow(color: color, radius: 0, x: 0, y: width)
            .shadow(color: color, radius: 0, x: -width, y: -width)
            .shadow(color: color, radius: 0, x: width, y: -width)
            .shadow(color: color, radius: 0, x: -width, y: width)
            .shadow(color: color, radius: 0, x: width, y: width)
    }
}

private extension View {
    func interaFilledPrimaryButtonLabelOutline(
        when isEnabled: Bool,
        width: CGFloat = 0.48,
        opacity: CGFloat = 0.88,
        strong: Bool = false
    ) -> some View {
        modifier(InteraFilledPrimaryButtonLabelOutlineModifier(
            isEnabled: isEnabled,
            width: width,
            opacity: opacity,
            strong: strong
        ))
    }
}

private struct PrimaryButtonShapeModifier: ViewModifier {
    let shape: PrimaryButton.Shape
    let borderColor: Color?
    var cornerRadius: CGFloat = .radiusMedium

    func body(content: Content) -> some View {
        switch shape {
        case .rounded:
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    if let borderColor {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(borderColor, lineWidth: 1.5)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        case .pill:
            content
                .clipShape(Capsule(style: .continuous))
                .overlay {
                    if let borderColor {
                        Capsule(style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1.5)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
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
        PrimaryButton(title: "Prominent Button", action: {}, size: .prominent, titleUsesOutline: true)
    }
    .padding()
}
