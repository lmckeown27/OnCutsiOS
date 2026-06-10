//
//  HubPagingScrollOffsetReader.swift
//  Intera
//
//  Reads the horizontal paging `UIScrollView` used by SwiftUI’s `.tabViewStyle(.page)` so the hub
//  bubble can track `contentOffset.x` 1:1 with the main `TabView`.
//

#if canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

/// Observes the page `UIScrollView` under the hub `TabView` and publishes `contentOffset.x` + page width.
struct HubPagingScrollOffsetReader: UIViewRepresentable {
    @Binding var scrollOffsetX: CGFloat
    @Binding var pageWidth: CGFloat
    /// Bumps the search when selection changes (SwiftUI may rebuild the page controller).
    var hubPageIndex: Int
    /// When `false`, the hub’s horizontal page `UIScrollView` does not accept drags (e.g. interactive back on a Messages thread must not change Home / Bookings tabs).
    var isPagingInteractionEnabled: Bool = true
    /// When `true`, sets `contentOffset` to match `hubPageIndex` without animation (needed when selection changes with animations disabled — e.g. adjacent tab).
    @Binding var syncPagingScrollToSelection: Bool
    /// When `false`, only one deferred reconcile runs (icon snap); when `true`, multi-frame reconcile for drift after animated moves.
    @Binding var syncPagingScrollAggressive: Bool
    /// While `true`, ignores scroll view KVO for offset/width publishing so dragging the hub bubble does not re-render the whole `TabView` every frame.
    var suppressScrollPublishingFromObserver: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(
            scrollOffsetX: $scrollOffsetX,
            pageWidth: $pageWidth,
            syncPagingScrollToSelection: $syncPagingScrollToSelection,
            syncPagingScrollAggressive: $syncPagingScrollAggressive
        )
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.scrollOffsetX = $scrollOffsetX
        context.coordinator.pageWidth = $pageWidth
        context.coordinator.syncPagingScrollToSelection = $syncPagingScrollToSelection
        context.coordinator.syncPagingScrollAggressive = $syncPagingScrollAggressive
        context.coordinator.suppressScrollPublishingFromObserver = suppressScrollPublishingFromObserver
        context.coordinator.isPagingInteractionEnabled = isPagingInteractionEnabled
        context.coordinator.attachIfNeeded(anchoredTo: uiView)
        context.coordinator.applyPagingInteractionIfPossible()
        context.coordinator.setHubPageIndex(hubPageIndex)
        context.coordinator.syncScrollToHubPageIfNeeded(hubPageIndex: hubPageIndex)
        // SwiftUI sometimes re-enables the pager after layout; re-apply while a thread locks the hub.
        if !isPagingInteractionEnabled {
            let c = context.coordinator
            DispatchQueue.main.async { c.applyPagingInteractionIfPossible() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { c.applyPagingInteractionIfPossible() }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        var scrollOffsetX: Binding<CGFloat>
        var pageWidth: Binding<CGFloat>
        var syncPagingScrollToSelection: Binding<Bool>
        var syncPagingScrollAggressive: Binding<Bool>
        var suppressScrollPublishingFromObserver: Bool = false
        var isPagingInteractionEnabled: Bool = true
        private weak var observed: UIScrollView?
        private weak var anchorView: UIView?
        private var offsetObs: NSKeyValueObservation?
        private var boundsObs: NSKeyValueObservation?
        private var didBecomeActiveObs: NSObjectProtocol?
        private var attempts = 0
        private let maxAttempts = 12
        private var hubPageIndex = 0

        func setHubPageIndex(_ index: Int) {
            hubPageIndex = index
        }

        init(
            scrollOffsetX: Binding<CGFloat>,
            pageWidth: Binding<CGFloat>,
            syncPagingScrollToSelection: Binding<Bool>,
            syncPagingScrollAggressive: Binding<Bool>
        ) {
            self.scrollOffsetX = scrollOffsetX
            self.pageWidth = pageWidth
            self.syncPagingScrollToSelection = syncPagingScrollToSelection
            self.syncPagingScrollAggressive = syncPagingScrollAggressive
            super.init()
            didBecomeActiveObs = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleDidBecomeActive()
            }
        }

        deinit {
            if let didBecomeActiveObs {
                NotificationCenter.default.removeObserver(didBecomeActiveObs)
            }
        }

        private func handleDidBecomeActive() {
            if let anchor = anchorView {
                attempts = 0
                tryAttach(anchoredTo: anchor)
            }
            guard let scroll = observed else { return }
            reconcilePagingOffsetIfNeeded(page: hubPageIndex)
            publish(scroll, force: true)
        }

        func syncScrollToHubPageIfNeeded(hubPageIndex: Int) {
            guard syncPagingScrollToSelection.wrappedValue else { return }
            guard let scroll = observed else { return }
            let page = hubPageIndex
            let aggressive = syncPagingScrollAggressive.wrappedValue
            applyPagingOffset(scroll: scroll, page: page)
            syncPagingScrollToSelection.wrappedValue = false
            syncPagingScrollAggressive.wrappedValue = true
            publish(scroll, force: true)
            if aggressive {
                schedulePagingOffsetReconcile(page: page)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.reconcilePagingOffsetIfNeeded(page: page)
                }
            }
        }

        /// Forces the paging scroll view’s x-offset to match `page` when it has drifted (common for ±1 selection).
        private func reconcilePagingOffsetIfNeeded(page: Int) {
            guard let scroll = observed else { return }
            let w = max(1, scroll.bounds.width)
            let targetX = CGFloat(page) * w
            guard abs(scroll.contentOffset.x - targetX) > 0.5 else { return }
            applyPagingOffset(scroll: scroll, page: page)
            publish(scroll, force: true)
        }

        private func applyPagingOffset(scroll: UIScrollView, page: Int) {
            let w = max(1, scroll.bounds.width)
            let targetX = CGFloat(page) * w
            UIView.performWithoutAnimation {
                scroll.setContentOffset(CGPoint(x: targetX, y: scroll.contentOffset.y), animated: false)
            }
        }

        private func schedulePagingOffsetReconcile(page: Int) {
            DispatchQueue.main.async { [weak self] in
                self?.reconcilePagingOffsetIfNeeded(page: page)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.reconcilePagingOffsetIfNeeded(page: page)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.reconcilePagingOffsetIfNeeded(page: page)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                self?.reconcilePagingOffsetIfNeeded(page: page)
            }
        }

        func applyPagingInteractionIfPossible() {
            guard let scroll = observed else { return }
            scroll.isScrollEnabled = isPagingInteractionEnabled
            scroll.panGestureRecognizer.isEnabled = isPagingInteractionEnabled
        }

        func detach() {
            observed?.isScrollEnabled = true
            offsetObs = nil
            boundsObs = nil
            observed = nil
        }

        func attachIfNeeded(anchoredTo uiView: UIView) {
            anchorView = uiView
            attempts = 0
            tryAttach(anchoredTo: uiView)
        }

        private func tryAttach(anchoredTo uiView: UIView) {
            guard let window = uiView.window ?? uiView.superview?.window else {
                scheduleRetry(anchoredTo: uiView)
                return
            }
            guard let root = window.rootViewController else { return }
            let scroll: UIScrollView? = {
                if let pvc = intera_findPageViewControllerForHubScroll(from: root),
                   let s = pvc.view.intera_horizontalPagingScrollView() {
                    return s
                }
                // iOS 17+ paged `TabView` may not wrap a `UIPageViewController`; fall back to scanning the window.
                return window.intera_horizontalPagingScrollView()
            }()
            guard let scroll else {
                scheduleRetry(anchoredTo: uiView)
                return
            }
            if observed === scroll {
                applyPagingInteractionIfPossible()
                publish(scroll, force: true)
                return
            }
            detach()
            observed = scroll
            scroll.isScrollEnabled = isPagingInteractionEnabled
            scroll.panGestureRecognizer.isEnabled = isPagingInteractionEnabled
            offsetObs = scroll.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                self?.publish(sv, force: false)
            }
            boundsObs = scroll.observe(\.bounds, options: [.new]) { [weak self] sv, _ in
                self?.publish(sv, force: false)
            }
            publish(scroll, force: true)
        }

        private func scheduleRetry(anchoredTo uiView: UIView) {
            attempts += 1
            guard attempts < maxAttempts else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.tryAttach(anchoredTo: uiView)
            }
        }

        private func publish(_ sv: UIScrollView, force: Bool = false) {
            if !force, suppressScrollPublishingFromObserver { return }
            let w = max(1, sv.bounds.width)
            let x = sv.contentOffset.x
            if Thread.isMainThread {
                scrollOffsetX.wrappedValue = x
                pageWidth.wrappedValue = w
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.scrollOffsetX.wrappedValue = x
                    self?.pageWidth.wrappedValue = w
                }
            }
        }
    }
}

private extension UIView {
    func intera_horizontalPagingScrollView() -> UIScrollView? {
        func scan(_ v: UIView) -> UIScrollView? {
            if let s = v as? UIScrollView, s.isPagingEnabled, s.contentSize.width > s.bounds.width + 2 {
                return s
            }
            for sub in v.subviews {
                if let found = scan(sub) { return found }
            }
            return nil
        }
        return scan(self)
    }
}

/// Same search as `HubPageViewControllerSurfaceTint` (file-local to avoid duplicate `UIViewController` extension symbols).
private func intera_findPageViewControllerForHubScroll(from root: UIViewController) -> UIPageViewController? {
    if let p = root as? UIPageViewController { return p }
    for child in root.children {
        if let found = intera_findPageViewControllerForHubScroll(from: child) { return found }
    }
    if let nav = root as? UINavigationController {
        for vc in nav.viewControllers {
            if let found = intera_findPageViewControllerForHubScroll(from: vc) { return found }
        }
    }
    if let tab = root as? UITabBarController {
        for vc in tab.viewControllers ?? [] {
            if let found = intera_findPageViewControllerForHubScroll(from: vc) { return found }
        }
    }
    if let split = root as? UISplitViewController {
        for vc in split.viewControllers {
            if let found = intera_findPageViewControllerForHubScroll(from: vc) { return found }
        }
    }
    if let presented = root.presentedViewController {
        return intera_findPageViewControllerForHubScroll(from: presented)
    }
    return nil
}
#endif
