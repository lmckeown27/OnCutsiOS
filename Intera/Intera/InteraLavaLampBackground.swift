//
//  InteraLavaLampBackground.swift
//  Intera
//
//  Adaptive consumer shell background (white in light mode, black in dark mode).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Full-screen shell backdrop that follows the system appearance.
struct InteraShellBackground: View {
    var body: some View {
        Color.interaShellBackground
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Backward-compatible name for call sites that still reference the lava lamp type.
typealias InteraLavaLampBackground = InteraShellBackground

// MARK: - Consumer hub shell (paged `TabView`)

/// One shared adaptive backdrop behind `UnifiedProviderHomeScreen` so hub tabs do not flash mismatched backgrounds during swipes.
struct InteraHubTabShellBackground: View {
    var body: some View {
        InteraShellBackground()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(iOS)
/// SwiftUI’s navigation host often paints an opaque system background over the window; without this,
/// the root shell backdrop stays covered.
private struct InteraNavigationShellBackgroundClearModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.containerBackground(Color.clear, for: .navigation)
        } else {
            content
        }
    }
}

extension View {
    /// Apply to the root view inside a `NavigationStack` so the shell background remains visible behind clear content.
    func interaNavigationShellBackgroundClear() -> some View {
        modifier(InteraNavigationShellBackgroundClearModifier())
    }
}
#endif
