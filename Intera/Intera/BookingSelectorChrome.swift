//
//  BookingSelectorChrome.swift
//  Intera
//
//  Shared ghost/solid cream styling, spring, and selection haptics for live booking selectors.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum BookingSelectorTheme {
    /// Label on a selected cream/foreground chip (inverse of shell foreground).
    static var deepCharcoal: Color { Color.interaShellBackground }
    static var cream: Color { Color.interaShellForeground }
    static let cornerRadius: CGFloat = 12
    static let selectionSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Timeline **Today** bold (service title / shop name / day number).
    static let todayBoldFont = InteraFont.font(size: 28, weight: .bold)

    static func triggerSelectionChangedIfNewSelection(wasSelected: Bool) {
        guard !wasSelected else { return }
        #if os(iOS)
        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
        #endif
    }
}

private struct PastLabelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(InteraFont.font(size: 14, weight: .medium))
            .textCase(.uppercase)
            .kerning(2.2)
    }
}

/// Calendar weekday initials: small caps row with **+15%** tracking (relative to font size).
private struct CalendarWeekdayLabelModifier: ViewModifier {
    private let fontSize: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .font(InteraFont.font(size: fontSize, weight: .medium))
            .textCase(.uppercase)
            .kerning(fontSize * 0.15)
    }
}

extension View {
    func bookingPastLabelStyle() -> some View {
        modifier(PastLabelModifier())
    }

    func bookingCalendarWeekdayLabelStyle() -> some View {
        modifier(CalendarWeekdayLabelModifier())
    }
}

/// Ghost: transparent + cream stroke. Solid: cream fill + no outer stroke (selection).
struct BookingSelectorSurface: ViewModifier {
    let isSelected: Bool
    /// When `false`, slot is shown dimmed and non-interactive (e.g. unavailable time).
    var isEnabled: Bool = true

    func body(content: Content) -> some View {
        let showGhostBorder = !isSelected && isEnabled
        return content
            .opacity(isEnabled ? 1 : 0.28)
            .background {
                if isSelected && isEnabled {
                    RoundedRectangle(cornerRadius: BookingSelectorTheme.cornerRadius, style: .continuous)
                        .fill(BookingSelectorTheme.cream)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: BookingSelectorTheme.cornerRadius, style: .continuous)
                    .strokeBorder(
                        BookingSelectorTheme.cream.opacity(isEnabled ? 1 : 0.35),
                        lineWidth: showGhostBorder ? 1 : 0
                    )
            }
    }
}

extension View {
    func bookingSelectorSurface(isSelected: Bool, isEnabled: Bool = true) -> some View {
        modifier(BookingSelectorSurface(isSelected: isSelected, isEnabled: isEnabled))
    }
}
