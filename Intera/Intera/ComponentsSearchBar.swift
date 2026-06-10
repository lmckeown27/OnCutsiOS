//
//  SearchBar.swift
//  Intera
//
//  Reusable search bar component
//

import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var onSubmit: (() -> Void)? = nil
    /// When `false`, no material / glass / gray fill—only layout, focus ring, and labels (for floating headers over colorful backdrops).
    var fillsSearchFieldBackground: Bool = true
    
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        let iconColor = fillsSearchFieldBackground ? Color.neutral400 : Color.lavaShellCreamTertiary
        let textColor = fillsSearchFieldBackground ? Color.neutral800 : Color.lavaShellCream
        let row = HStack(spacing: .space3) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(iconColor)
                .font(.body)
            
            TextField(placeholder, text: $text)
                .font(.bodyMedium)
                .foregroundStyle(textColor)
                .focused($isSearchFieldFocused)
                .autocorrectionDisabled()
                .onSubmit {
                    onSubmit?()
                }
        }
        .padding(.space3)
        .tint(Color.oliveGreen)
        
        Group {
            if fillsSearchFieldBackground {
                row.liquidGlassSearchFieldChrome(cornerRadius: .radiusLarge)
            } else {
                row.clipShape(RoundedRectangle(cornerRadius: .radiusLarge, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: .radiusLarge, style: .continuous)
                .stroke(Color.oliveGreen, lineWidth: isSearchFieldFocused ? 2 : 0)
        }
        .animation(.easeInOut(duration: 0.2), value: isSearchFieldFocused)
    }
}

// MARK: - Preview

#Preview("Empty") {
    SearchBar(text: .constant(""))
        .padding()
}

#Preview("With Text") {
    SearchBar(text: .constant("Jordan"))
        .padding()
}

#Preview("Custom Placeholder") {
    SearchBar(
        text: .constant(""),
        placeholder: "Search barbers..."
    )
    .padding()
}
