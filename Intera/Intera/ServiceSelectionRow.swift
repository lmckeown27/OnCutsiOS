//
//  ServiceSelectionRow.swift
//  Intera
//
//  Service + price row for live booking: cream / charcoal states, timeline typography, selection haptics.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Timeline **Today** bold — shared by service name and price for matching typography.
private let serviceSelectionTitleFont = Font.system(size: 28, weight: .bold, design: .default)

struct ServiceSelectionRow: View {
    let title: String
    /// Display string (e.g. `"$30"`); same font/size as `title`.
    let priceText: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            if !isSelected {
                #if os(iOS)
                let feedback = UISelectionFeedbackGenerator()
                feedback.prepare()
                feedback.selectionChanged()
                #endif
            }
            action()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(serviceSelectionTitleFont)
                    .foregroundStyle(isSelected ? BookingSelectorTheme.deepCharcoal : Color.lavaShellCream.opacity(0.6))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(priceText)
                    .font(serviceSelectionTitleFont)
                    .foregroundStyle(isSelected ? BookingSelectorTheme.deepCharcoal : Color.lavaShellCream.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(BookingSelectorTheme.deepCharcoal)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .bookingSelectorSurface(isSelected: isSelected)
        }
        .buttonStyle(BookButtonStyle())
        .animation(BookingSelectorTheme.selectionSpring, value: isSelected)
    }
}

#if DEBUG
#Preview("ServiceSelectionRow") {
    VStack(spacing: 12) {
        ServiceSelectionRow(title: "Fade & lineup", priceText: "$35", isSelected: false, action: {})
        ServiceSelectionRow(title: "Classic cut", priceText: "$30", isSelected: true, action: {})
    }
    .padding()
    .background(Color.black.opacity(0.85))
}
#endif
