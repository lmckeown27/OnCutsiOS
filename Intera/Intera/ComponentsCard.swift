//
//  CampusCutsCard.swift
//  Intera
//
//  Reusable card component for CampusCuts design system
//

import SwiftUI

struct CampusCutsCard<Content: View>: View {
    let content: () -> Content
    var padding: CGFloat = .space4
    var cornerRadius: CGFloat = .radiusXL
    var shadowRadius: CGFloat = .shadowLarge
    var backgroundColor: Color = .white
    
    init(
        padding: CGFloat = .space4,
        cornerRadius: CGFloat = .radiusXL,
        shadowRadius: CGFloat = .shadowLarge,
        backgroundColor: Color = .white,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.backgroundColor = backgroundColor
        self.content = content
    }
    
    var body: some View {
        content()
            .padding(padding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .cardShadow(radius: shadowRadius)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: .space6) {
        CampusCutsCard {
            VStack(alignment: .leading, spacing: .space3) {
                Text("Card Title")
                    .campusCutsStyle(.headlineMedium)
                
                Text("This is a sample card with some content inside. It follows the CampusCuts design system.")
                    .campusCutsStyle(.bodyMedium)
                
                PrimaryButton(title: "Action", action: {})
            }
        }
        
        CampusCutsCard(backgroundColor: .oliveTint) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.oliveGreen)
                    .font(InteraFont.title2)
                
                VStack(alignment: .leading) {
                    Text("Information")
                        .campusCutsStyle(.labelLarge)
                    Text("Card with custom background")
                        .campusCutsStyle(.caption)
                }
            }
        }
    }
    .padding()
    .background(Color.backgroundSecondary)
}
