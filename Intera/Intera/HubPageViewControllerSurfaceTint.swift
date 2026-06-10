//
//  HubPageViewControllerSurfaceTint.swift
//  Intera
//
//  SwiftUI’s paged `TabView` uses `UIPageViewController`. Clearing every scroll view inside it (global
//  appearance) lets the root lava lamp show through during transitions (“entire page very bright”).
//  Instead we only set the **page controller’s** root view to a semantic surface color so swipe gutters
//  match normal page backgrounds without fighting each screen’s own scroll/table styling.
//

#if canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

/// Matches `Color.interaShellBackground` so hub swipe gutters do not flash the wrong tone between tabs.
private let interaHubPageSwipeChromeUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? .black : .white
}

/// Finds the hosting `UIPageViewController` and paints its root + the **horizontal** paging `UIScrollView`
/// shell so gutters during `TabView` page transitions match the lava shell (not system white).
struct HubPageViewControllerSurfaceTint: UIViewRepresentable {
    /// Bumps `updateUIView` on each swipe so we re-apply after UIKit rebuilds transition subviews.
    var hubPageIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.applySurfaceTint(anchoredTo: uiView)
    }

    final class Coordinator {
        private var attempts = 0
        private let maxAttempts = 10

        func applySurfaceTint(anchoredTo uiView: UIView) {
            let color = interaHubPageSwipeChromeUIColor

            func tryApply() {
                guard let window = uiView.window ?? uiView.superview?.window else {
                    attempts += 1
                    if attempts < maxAttempts {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { tryApply() }
                    }
                    return
                }
                guard let root = window.rootViewController else { return }
                guard let pvc = root.intera_firstPageViewControllerDeep() else { return }
                pvc.view.backgroundColor = color
                // Horizontal page curl scroll is usually a direct subview; tint only those (not deep nested vertical scrolls).
                for sub in pvc.view.subviews {
                    if let scroll = sub as? UIScrollView {
                        scroll.backgroundColor = color
                    }
                }
            }

            attempts = 0
            DispatchQueue.main.async(execute: tryApply)
        }
    }
}

private extension UIViewController {
    /// Depth-first search for a `UIPageViewController` under the window root (SwiftUI may nest deeply).
    func intera_firstPageViewControllerDeep() -> UIPageViewController? {
        if let p = self as? UIPageViewController { return p }
        for child in children {
            if let found = child.intera_firstPageViewControllerDeep() { return found }
        }
        if let nav = self as? UINavigationController {
            for vc in nav.viewControllers {
                if let found = vc.intera_firstPageViewControllerDeep() { return found }
            }
        }
        if let tab = self as? UITabBarController {
            for vc in tab.viewControllers ?? [] {
                if let found = vc.intera_firstPageViewControllerDeep() { return found }
            }
        }
        if let split = self as? UISplitViewController {
            for vc in split.viewControllers {
                if let found = vc.intera_firstPageViewControllerDeep() { return found }
            }
        }
        if let presented = presentedViewController {
            return presented.intera_firstPageViewControllerDeep()
        }
        return nil
    }
}
#endif
