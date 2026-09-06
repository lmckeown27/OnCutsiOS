//
//  OnCutsHubChromeLayout.swift
//  OnCuts
//
//  Shared top clearance for Home browse chrome and Messages / Bookings / Profile
//  floating headers so hub pages align under the status bar / Dynamic Island.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum OnCutsHubChromeLayout {
    /// Floor when the window hasn’t reported insets yet.
    static var cameraClearanceFloor: CGFloat { 12 }
    /// Slight lift toward the status bar (matches Home browse chrome).
    static var topNudgeUp: CGFloat { 6 }

    static var windowSafeAreaTop: CGFloat {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        return window?.safeAreaInsets.top ?? 0
        #else
        return 0
        #endif
    }

    /// iPad: hub `NavigationStack` + clear nav can under-report top inset and clip chrome.
    static func topUnderlapCompensation(safeAreaTop: CGFloat) -> CGFloat {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .pad else { return 0 }
        return max(0, 56 - safeAreaTop)
        #else
        return 0
        #endif
    }

    /// Top pad for floating hub chrome on a full-bleed page (Home, Messages, Bookings, Profile).
    static func floatingChromeTopPadding(resolvedSafeAreaTop: CGFloat = windowSafeAreaTop) -> CGFloat {
        let top = resolvedSafeAreaTop > 1 ? resolvedSafeAreaTop : windowSafeAreaTop
        let cleared = max(cameraClearanceFloor, top)
        let padded = cleared + topUnderlapCompensation(safeAreaTop: cleared)
        return max(cameraClearanceFloor, padded - topNudgeUp)
    }
}
