//
//  DesignSystem+Spacing.swift
//  Intera
//
//  AvilaPlatforms spacing and layout system (8pt grid)
//

import SwiftUI

extension CGFloat {
    
    // MARK: - Spacing Scale (8pt Grid)
    
    static let space0: CGFloat = 0
    static let space1: CGFloat = 4      // Tight spacing
    static let space2: CGFloat = 8      // Default small
    static let space3: CGFloat = 12     // Medium small
    static let space4: CGFloat = 16     // Default medium
    static let space5: CGFloat = 20     // Medium
    static let space6: CGFloat = 24     // Large
    static let space8: CGFloat = 32     // Extra large
    static let space10: CGFloat = 40    // Section spacing
    static let space12: CGFloat = 48    // Large section
    static let space16: CGFloat = 64    // Page margins
    
    // MARK: - Corner Radius
    
    static let radiusSmall: CGFloat = 4     // Tags, badges
    static let radiusMedium: CGFloat = 8    // Buttons, inputs
    static let radiusLarge: CGFloat = 12    // Cards
    static let radiusXL: CGFloat = 16       // Large cards, modals
    static let radiusFull: CGFloat = 9999   // Pills, avatars (use Capsule instead)
    
    // MARK: - Shadow
    
    static let shadowSmall: CGFloat = 2
    static let shadowMedium: CGFloat = 4
    static let shadowLarge: CGFloat = 8
    static let shadowXL: CGFloat = 16
}

// MARK: - Card Shadow Modifier

struct CardShadow: ViewModifier {
    var radius: CGFloat = 8
    var opacity: Double = 0.05
    var x: CGFloat = 0
    var y: CGFloat = 2
    
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(opacity), radius: radius, x: x, y: y)
    }
}

extension View {
    func cardShadow(
        radius: CGFloat = 8,
        opacity: Double = 0.05,
        x: CGFloat = 0,
        y: CGFloat = 2
    ) -> some View {
        modifier(CardShadow(radius: radius, opacity: opacity, x: x, y: y))
    }
}
