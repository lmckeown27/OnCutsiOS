//
//  BookingFlowSheetPresentation.swift
//  OnCuts
//
//  `LiveBookingView` is presented as a sheet from provider detail / rebook.
//  From iPadOS 18 / iOS 18, SwiftUI’s default sheet is a compact “form” sheet;
//  `presentationSizing(.page)` restores a large page-style sheet. On iOS 17 iPad
//  we pin a tall `.height` detent so the intake isn’t stuck in a short card.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension View {
    /// iPad: large page-style sheet (iOS 18+) or tall height detent (iOS 17). iPhone: standard large detent.
    func onCutsBookingFlowSheetPresentation() -> some View {
        modifier(BookingFlowSheetPresentationModifier())
    }
}

private struct BookingFlowSheetPresentationModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            padBookingSheet(content)
        } else {
            content
                .presentationDetents([.large])
        }
        #else
        content
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private func padBookingSheet(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            // iPadOS 18+ defaults to a compact form sheet; `.page` matches the prior large booking surface.
            content
                .presentationSizing(.page)
        } else {
            content
                .presentationDetents([.height(Self.ipadLegacyTallSheetHeight()), .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// Pre–iOS 18 iPad: explicit height so the sheet isn’t capped to a short form height.
    private static func ipadLegacyTallSheetHeight() -> CGFloat {
        let b = UIScreen.main.bounds
        let longEdge = max(b.width, b.height)
        return min(longEdge * 0.92, 1200)
    }
    #endif
}
