//
//  OnCutsLavaLampBackground.swift
//  OnCuts
//
//  Adaptive consumer shell background (white in light mode, black in dark mode).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Full-screen shell backdrop that follows the system appearance.
struct OnCutsShellBackground: View {
    var body: some View {
        Color.onCutsShellBackground
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Backward-compatible name for call sites that still reference the lava lamp type.
typealias OnCutsLavaLampBackground = OnCutsShellBackground

// MARK: - Consumer hub shell (paged `TabView`)

/// One shared adaptive backdrop behind `UnifiedProviderHomeScreen` so hub tabs do not flash mismatched backgrounds during swipes.
struct OnCutsHubTabShellBackground: View {
    var body: some View {
        OnCutsShellBackground()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(iOS)
/// SwiftUI’s navigation host often paints an opaque system background over the window; without this,
/// the root shell backdrop stays covered.
private struct OnCutsNavigationShellBackgroundClearModifier: ViewModifier {
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
    func onCutsNavigationShellBackgroundClear() -> some View {
        modifier(OnCutsNavigationShellBackgroundClearModifier())
    }

    /// Re-enables the edge swipe-to-pop gesture when the navigation bar is hidden (e.g. conversation chrome).
    func onCutsEnableNavigationSwipeBack() -> some View {
        background(OnCutsNavigationInteractivePopEnabler())
    }
}

/// Keeps `UINavigationController`'s interactive pop alive when SwiftUI hides the navigation bar.
private struct OnCutsNavigationInteractivePopEnabler: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.enable(from: uiViewController)
    }

    final class Coordinator {
        private let popDelegate = PopGestureDelegate()

        func enable(from viewController: UIViewController) {
            DispatchQueue.main.async { [weak viewController, popDelegate] in
                guard let viewController,
                      let nav = viewController.navigationController,
                      let pop = nav.interactivePopGestureRecognizer else { return }
                pop.isEnabled = true
                popDelegate.navigationController = nav
                if pop.delegate !== popDelegate {
                    pop.delegate = popDelegate
                }
            }
        }
    }

    private final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
#endif
