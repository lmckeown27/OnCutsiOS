//
//  AvilaPlatformsCard.swift
//  Intera
//
//  Reusable card component for AvilaPlatforms design system
//

import SwiftUI

struct AvilaPlatformsCard<Content: View>: View {
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
        AvilaPlatformsCard {
            VStack(alignment: .leading, spacing: .space3) {
                Text("Card Title")
                    .avilaPlatformsStyle(.headlineMedium)
                
                Text("This is a sample card with some content inside. It follows the AvilaPlatforms design system.")
                    .avilaPlatformsStyle(.bodyMedium)
                
                PrimaryButton(title: "Action", action: {})
            }
        }
        
        AvilaPlatformsCard(backgroundColor: .oliveTint) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyleInteraShellIcon()
                    .font(InteraFont.title2)
                
                VStack(alignment: .leading) {
                    Text("Information")
                        .avilaPlatformsStyle(.labelLarge)
                    Text("Card with custom background")
                        .avilaPlatformsStyle(.caption)
                }
            }
        }
    }
    .padding()
    .background(Color.backgroundSecondary)
}
