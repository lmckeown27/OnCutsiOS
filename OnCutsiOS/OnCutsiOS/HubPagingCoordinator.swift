//
//  HubPagingCoordinator.swift
//  OnCuts
//
//  Drives the hub cream bubble from the paging `UIScrollView` via UIKit layout (no SwiftUI
//  invalidation per scroll frame). Icon tint progress is reported on a throttled cadence only.
//

#if canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

// MARK: - Weak page container (file-level to avoid Release SIL inliner crash in nested generic)

private final class HubPageWeakContainer {
    weak var value: UIView?
    init(_ value: UIView) { self.value = value }
}

// MARK: - UIColor helpers (match ConsumerStickyHubNavigation semantic colors)

extension UIColor {
    static var onCutsHubBubbleFill: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 245 / 255, green: 245 / 255, blue: 220 / 255, alpha: 1)
                : .black
        }
    }
}

// MARK: - Bubble layout bridge (implementation in ConsumerStickyHubNavigation)

private enum HubBubbleLayoutBridge {
    static func metrics(
        railWidth: CGFloat,
        railHeight: CGFloat,
        progress: CGFloat,
        widthScale: CGFloat = 1
    ) -> HubBubbleLayout.Metrics {
        HubBubbleLayout.metrics(
            railWidth: railWidth,
            railHeight: railHeight,
            progress: progress,
            widthScale: widthScale
        )
    }

    static func scrollProgress(offsetX: CGFloat, pageWidth: CGFloat) -> CGFloat {
        HubBubbleLayout.scrollProgress(offsetX: offsetX, pageWidth: pageWidth)
    }
}

// MARK: - UIKit bubble host

final class HubBubbleHostView: UIView {
    let bubble = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        bubble.backgroundColor = .onCutsHubBubbleFill
        bubble.layer.cornerCurve = .continuous
        bubble.isUserInteractionEnabled = false
        addSubview(bubble)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private var lastAppliedDragGlow = false

    func apply(_ metrics: HubBubbleLayout.Metrics, visualScale: CGFloat, dragGlow: Bool) {
        bubble.frame = metrics.frame
        bubble.layer.cornerRadius = metrics.cornerRadius
        bubble.transform = CGAffineTransform(scaleX: visualScale, y: visualScale)
        if dragGlow {
            bubble.layer.shadowColor = UIColor.onCutsHubBubbleFill.cgColor
            bubble.layer.shadowRadius = 10
            bubble.layer.shadowOpacity = 0.85
            bubble.layer.shadowOffset = .zero
            lastAppliedDragGlow = true
        } else if lastAppliedDragGlow {
            bubble.layer.shadowOpacity = 0
            lastAppliedDragGlow = false
        }
    }
}

/// Embeds the cream bubble; layout is driven by ``HubPagingCoordinator`` (not SwiftUI).
struct HubBubbleUIKitHost: UIViewRepresentable {
    var coordinator: HubPagingCoordinator
    var railWidth: CGFloat
    var railHeight: CGFloat
    var visualScale: CGFloat
    var dragGlow: Bool

    func makeCoordinator() -> HostCoordinator { HostCoordinator(coordinator: coordinator) }

    func makeUIView(context: Context) -> HubBubbleHostView {
        let host = HubBubbleHostView()
        context.coordinator.attach(host)
        return host
    }

    func updateUIView(_ uiView: HubBubbleHostView, context: Context) {
        context.coordinator.attach(uiView)
        let size = CGSize(width: railWidth, height: railHeight)
        coordinator.bubbleHostSize = size
        coordinator.bubbleVisualScale = visualScale
        coordinator.bubbleDragGlow = dragGlow
        guard coordinator.isHubBarBubblePresentationEnabled else {
            uiView.isHidden = true
            return
        }
        uiView.isHidden = false
        coordinator.invalidateBubbleLayoutCache()
        coordinator.refreshBubbleLayout(animated: false)
    }

    static func dismantleUIView(_ uiView: HubBubbleHostView, coordinator: HostCoordinator) {
        coordinator.detach()
    }

    final class HostCoordinator {
        let coordinator: HubPagingCoordinator
        init(coordinator: HubPagingCoordinator) { self.coordinator = coordinator }
        func attach(_ host: HubBubbleHostView) { coordinator.noteBubbleHostAttached(host) }
        func detach() { coordinator.noteBubbleHostDetached() }
    }
}

// MARK: - Scroll bridge + bubble driver

final class HubPagingCoordinator: NSObject {
    weak var bubbleHost: HubBubbleHostView?

    var bubbleHostSize: CGSize = .zero
    var bubbleVisualScale: CGFloat = 1
    var bubbleDragGlow: Bool = false
    var tapFlightWidthScale: CGFloat = 1

    var manualDragProgress: CGFloat?
    var bubbleAnchoredToPageIndex = false
    var hubPageIndex = 0
    var suppressScrollPublish = false
    var isPagingInteractionEnabled = true

    var syncPagingScrollToSelection = false
    var syncPagingScrollAggressive = true

    /// Throttled hub icon tint progress (0…3).
    var onIconScrollProgress: ((CGFloat) -> Void)?

    private(set) var pageWidth: CGFloat = 0
    private(set) var scrollOffsetX: CGFloat = 0

    private weak var observed: UIScrollView?
    private weak var anchorView: UIView?
    private var offsetObs: NSKeyValueObservation?
    private var boundsObs: NSKeyValueObservation?
    private var didBecomeActiveObs: NSObjectProtocol?
    private var attempts = 0
    private let maxAttempts = 12
    private var lastReportedIconProgress: CGFloat = -.infinity
    private var lastBubbleFrame: CGRect = .null
    var lastBubbleVisualScale: CGFloat = 1
    var lastBubbleDragGlow = false
    private(set) var isUserScrolling = false
    private var wasUserScrolling = false
    private var lastScrollOffsetX: CGFloat = 0
    /// When `false`, hub bar is unmounted (e.g. utility search) — ignore KVO layout and hide any stale host.
    var isHubBarBubblePresentationEnabled = true

    /// Fired once when horizontal paging settles (for icon tint snap).
    var onScrollSettled: ((CGFloat) -> Void)?

    override init() {
        super.init()
        didBecomeActiveObs = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handleDidBecomeActive()
                }
            }
    }

    deinit {
        if let didBecomeActiveObs {
            NotificationCenter.default.removeObserver(didBecomeActiveObs)
        }
    }

    func attachScrollObserver(anchoredTo uiView: UIView) {
        anchorView = uiView
        attempts = 0
        tryAttach(anchoredTo: uiView)
    }

    func detachScrollObserver() {
        restoreSuspendedVerticalScrolls()
        observed?.isScrollEnabled = true
        offsetObs = nil
        boundsObs = nil
        observed = nil
    }

    func setHubPageIndex(_ index: Int) {
        let pageChanged = hubPageIndex != index
        hubPageIndex = index
        if pageChanged {
            restoreSuspendedVerticalScrolls()
        }
    }

    func refreshBubbleLayout(animated: Bool) {
        let progress = resolvedBubbleProgress(scrollView: observed)
        applyBubble(progress: progress, animated: animated)
    }

    func invalidateBubbleLayoutCache() {
        lastBubbleFrame = .null
    }

    func setHubBarBubblePresentationEnabled(_ enabled: Bool) {
        isHubBarBubblePresentationEnabled = enabled
        bubbleHost?.isHidden = !enabled
        if enabled, bubbleHost != nil {
            invalidateBubbleLayoutCache()
            refreshBubbleLayout(animated: false)
        }
    }

    /// Call after the hub bar SwiftUI subtree remounts so the cream bubble is laid out on the new UIKit host.
    func syncBubbleAfterHubBarMount(page: Int) {
        guard isHubBarBubblePresentationEnabled else { return }
        invalidateBubbleLayoutCache()
        bubbleAnchoredToPageIndex = false
        animateBubbleToPage(page, animated: false)
        refreshBubbleLayout(animated: false)
    }

    func noteBubbleHostAttached(_ host: HubBubbleHostView) {
        let hostChanged = bubbleHost !== host
        bubbleHost = host
        host.isHidden = !isHubBarBubblePresentationEnabled
        guard isHubBarBubblePresentationEnabled else { return }
        guard hostChanged else { return }
        invalidateBubbleLayoutCache()
        refreshBubbleLayout(animated: false)
    }

    func noteBubbleHostDetached() {
        bubbleHost = nil
        invalidateBubbleLayoutCache()
    }

    func animateBubbleToPage(_ page: Int, animated: Bool) {
        applyBubble(progress: CGFloat(page), animated: animated)
        reportIconProgress(CGFloat(page))
    }

    private func resolvedBubbleProgress(scrollView: UIScrollView?) -> CGFloat {
        if let manualDragProgress { return manualDragProgress }
        if bubbleAnchoredToPageIndex { return CGFloat(hubPageIndex) }
        if let scrollView, pageWidth > 1 {
            return HubBubbleLayoutBridge.scrollProgress(offsetX: scrollView.contentOffset.x, pageWidth: pageWidth)
        }
        return CGFloat(hubPageIndex)
    }

    private func applyBubble(progress: CGFloat, animated: Bool) {
        guard isHubBarBubblePresentationEnabled else { return }
        guard bubbleHostSize.width > 1, bubbleHostSize.height > 1, let host = bubbleHost else { return }
        let metrics = HubBubbleLayoutBridge.metrics(
            railWidth: bubbleHostSize.width,
            railHeight: bubbleHostSize.height,
            progress: progress,
            widthScale: tapFlightWidthScale
        )
        let frameChanged = metrics.frame != lastBubbleFrame
            || bubbleVisualScale != lastBubbleVisualScale
            || bubbleDragGlow != lastBubbleDragGlow
        guard frameChanged || animated else { return }

        lastBubbleFrame = metrics.frame
        lastBubbleVisualScale = bubbleVisualScale
        lastBubbleDragGlow = bubbleDragGlow

        let apply = { [weak host] in
            guard let host else { return }
            host.apply(metrics, visualScale: self.bubbleVisualScale, dragGlow: self.bubbleDragGlow)
        }
        if animated {
            UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: apply)
        } else {
            apply()
        }
    }

    private func handleScrollPhaseTransition(
        scrolling: Bool,
        settledProgress: CGFloat,
        rawProgress: CGFloat,
        deltaX: CGFloat
    ) {
        if scrolling != wasUserScrolling {
            if scrolling {
                if shouldSuspendHomeMessagesVerticalScrolls(progress: rawProgress, deltaX: deltaX) {
                    suspendHomeMessagesVerticalScrolls()
                }
            } else {
                restoreSuspendedVerticalScrolls()
                reportIconProgress(settledProgress)
                onScrollSettled?(settledProgress)
            }
        }
        isUserScrolling = scrolling
        wasUserScrolling = scrolling
    }

    private func reportIconProgress(_ progress: CGFloat) {
        guard abs(progress - lastReportedIconProgress) > 0.001 else { return }
        lastReportedIconProgress = progress
        onIconScrollProgress?(progress)
    }

    private func handleDidBecomeActive() {
        if let anchor = anchorView {
            attempts = 0
            tryAttach(anchoredTo: anchor)
        }
        guard let scroll = observed else { return }
        reconcilePagingOffsetIfNeeded(page: hubPageIndex)
        scrollViewDidUpdate(scroll, force: true)
    }

    func syncScrollToHubPageIfNeeded() -> Bool {
        guard syncPagingScrollToSelection else { return false }
        guard let scroll = observed else { return false }
        let page = hubPageIndex
        let aggressive = syncPagingScrollAggressive
        applyPagingOffset(scroll: scroll, page: page)
        syncPagingScrollToSelection = false
        syncPagingScrollAggressive = true
        scrollViewDidUpdate(scroll, force: true)
        if aggressive {
            schedulePagingOffsetReconcile(page: page)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.reconcilePagingOffsetIfNeeded(page: page)
            }
        }
        return true
    }

    private func reconcilePagingOffsetIfNeeded(page: Int) {
        guard let scroll = observed else { return }
        guard !scroll.isDragging, !scroll.isDecelerating else { return }
        let w = max(1, scroll.bounds.width)
        let targetX = CGFloat(page) * w
        guard abs(scroll.contentOffset.x - targetX) > 0.5 else { return }
        applyPagingOffset(scroll: scroll, page: page)
        scrollViewDidUpdate(scroll, force: true)
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

    private func tryAttach(anchoredTo uiView: UIView) {
        guard let window = uiView.window ?? uiView.superview?.window else {
            scheduleRetry(anchoredTo: uiView)
            return
        }
        guard let root = window.rootViewController else { return }
        let scroll: UIScrollView? = {
            if let pvc = onCuts_hubFindPageViewController(from: root),
               let s = pvc.view.onCuts_hubHorizontalPagingScrollView() {
                return s
            }
            return window.onCuts_hubHorizontalPagingScrollView()
        }()
        guard let scroll else {
            scheduleRetry(anchoredTo: uiView)
            return
        }
        if observed === scroll {
            applyPagingInteractionIfPossible()
            return
        }
        detachScrollObserver()
        observed = scroll
        lastScrollOffsetX = scroll.contentOffset.x
        scroll.isScrollEnabled = isPagingInteractionEnabled
        scroll.panGestureRecognizer.isEnabled = isPagingInteractionEnabled
        offsetObs = scroll.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
            guard Thread.isMainThread else {
                DispatchQueue.main.async { self?.scrollViewDidUpdate(sv, force: false) }
                return
            }
            self?.scrollViewDidUpdate(sv, force: false)
        }
        boundsObs = scroll.observe(\.bounds, options: [.new]) { [weak self] sv, _ in
            guard Thread.isMainThread else {
                DispatchQueue.main.async { self?.scrollViewDidUpdate(sv, force: false) }
                return
            }
            self?.scrollViewDidUpdate(sv, force: false)
        }
        scrollViewDidUpdate(scroll, force: true)
        warmPagingScrollView(scroll)
    }

    private func warmPagingScrollView(_ scroll: UIScrollView) {
        scroll.delaysContentTouches = false
        scroll.layoutIfNeeded()
        refreshPageInteractionLocks()
    }

    private var pageContainers: [Int: HubPageWeakContainer] = [:]

    func registerPageContainer(pageIndex: Int, anchor: UIView) {
        guard let container = anchor.onCuts_hubPageContainerAncestor() else { return }
        if pageContainers[pageIndex]?.value === container { return }
        pageContainers[pageIndex] = HubPageWeakContainer(container)
        refreshPageInteractionLocks()
    }

    private func refreshPageInteractionLocks() {
        for (idx, box) in pageContainers {
            guard let container = box.value else { continue }
            let enabled = idx == hubPageIndex
            if container.isUserInteractionEnabled != enabled {
                container.isUserInteractionEnabled = enabled
            }
        }
    }

    func refreshPageInteractionLocksAfterSelectionChange() {
        refreshPageInteractionLocks()
    }

    /// Browse overlay present/dismiss can leave vertical `UIScrollView`s disabled if hub paging KVO fired mid-transition.
    func releaseSuspendedVerticalScrollsIfNeeded() {
        restoreSuspendedVerticalScrolls()
        wasUserScrolling = false
        isUserScrolling = false
    }

    private func scheduleRetry(anchoredTo uiView: UIView) {
        attempts += 1
        guard attempts < maxAttempts else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.tryAttach(anchoredTo: uiView)
        }
    }

    private func scrollViewDidUpdate(_ sv: UIScrollView, force: Bool) {
        if !force, suppressScrollPublish { return }

        let deltaX = sv.contentOffset.x - lastScrollOffsetX
        lastScrollOffsetX = sv.contentOffset.x

        pageWidth = max(1, sv.bounds.width)
        scrollOffsetX = sv.contentOffset.x

        let scrolling = sv.isDragging || sv.isDecelerating
        let rawProgress = scrollOffsetX / pageWidth
        let settledProgress = resolvedBubbleProgress(scrollView: sv)
        applyBubble(progress: settledProgress, animated: false)
        handleScrollPhaseTransition(
            scrolling: scrolling,
            settledProgress: settledProgress,
            rawProgress: rawProgress,
            deltaX: deltaX
        )
    }

    private var suspendedScrollStates: [ObjectIdentifier: (scrollView: UIScrollView, wasEnabled: Bool)] = [:]

    private func isHubHorizontalPager(_ scrollView: UIScrollView) -> Bool {
        scrollView.isPagingEnabled && scrollView.contentSize.width > scrollView.bounds.width + 2
    }

    /// Only the Home (0) ↔ Messages (1) gutter — not Messages→Bookings or other pairs.
    private func shouldSuspendHomeMessagesVerticalScrolls(progress: CGFloat, deltaX: CGFloat) -> Bool {
        if progress > 0.04 && progress < 0.96 { return true }
        if hubPageIndex == 0 && deltaX > 0 && progress < 1.05 { return true }
        if hubPageIndex == 1 && deltaX < 0 && progress > 0.95 && progress < 1.05 { return true }
        return false
    }

    private func suspendHomeMessagesVerticalScrolls() {
        guard suspendedScrollStates.isEmpty else { return }
        for pageIndex in 0 ... 1 {
            guard let container = pageContainers[pageIndex]?.value else { continue }
            suspendVerticalScrolls(under: container)
        }
    }

    private func suspendVerticalScrolls(under root: UIView) {
        if let scroll = root as? UIScrollView, scroll !== observed, !isHubHorizontalPager(scroll) {
            let key = ObjectIdentifier(scroll)
            guard suspendedScrollStates[key] == nil else { return }
            suspendedScrollStates[key] = (scroll, scroll.isScrollEnabled)
            scroll.isScrollEnabled = false
            scroll.panGestureRecognizer.isEnabled = false
        }
        for subview in root.subviews {
            suspendVerticalScrolls(under: subview)
        }
    }

    private func restoreSuspendedVerticalScrolls() {
        for (_, entry) in suspendedScrollStates {
            entry.scrollView.isScrollEnabled = entry.wasEnabled
            entry.scrollView.panGestureRecognizer.isEnabled = entry.wasEnabled
        }
        suspendedScrollStates.removeAll()
    }
}

// MARK: - Per-page touch isolation (UIKit — avoids `allowsHitTesting(hubPageIndex)` TabView re-renders)

/// Locks off-screen hub pages from stealing taps without SwiftUI `allowsHitTesting` on `hubPageIndex`.
struct HubPageInteractionGate: UIViewRepresentable {
    let pageIndex: Int
    var coordinator: HubPagingCoordinator

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        coordinator.registerPageContainer(pageIndex: pageIndex, anchor: uiView)
    }
}

private extension UIView {
    /// The page content container under the horizontal paging `UIScrollView`.
    func onCuts_hubPageContainerAncestor() -> UIView? {
        var current: UIView? = self
        while let view = current {
            if let scroll = view.superview as? UIScrollView, scroll.isPagingEnabled {
                return view
            }
            current = view.superview
        }
        return nil
    }
}

extension View {
    /// UIKit hit-test lock so inactive hub tabs do not intercept touches (no SwiftUI pager invalidation).
    func onCutsHubPageInteractionLock(pageIndex: Int, coordinator: HubPagingCoordinator) -> some View {
        background {
            HubPageInteractionGate(pageIndex: pageIndex, coordinator: coordinator)
        }
    }
}

// MARK: - Environment (browse / inbox scroll bridges read horizontal paging without shell re-renders)

private struct OnCutsHubPagingCoordinatorKey: EnvironmentKey {
    static var defaultValue: HubPagingCoordinator?
}

extension EnvironmentValues {
    var onCutsHubPagingCoordinator: HubPagingCoordinator? {
        get { self[OnCutsHubPagingCoordinatorKey.self] }
        set { self[OnCutsHubPagingCoordinatorKey.self] = newValue }
    }
}

// MARK: - SwiftUI scroll observer (shell overlay — off the `TabView` subtree)

struct HubPagingScrollOffsetReader: UIViewRepresentable {
    var coordinator: HubPagingCoordinator
    var hubPageIndex: Int
    var isPagingInteractionEnabled: Bool = true
    @Binding var syncPagingScrollToSelection: Bool
    @Binding var syncPagingScrollAggressive: Bool
    var suppressScrollPublishingFromObserver: Bool = false

    func makeCoordinator() -> ReaderCoordinator {
        ReaderCoordinator(
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
        coordinator.setHubPageIndex(hubPageIndex)
        coordinator.isPagingInteractionEnabled = isPagingInteractionEnabled
        coordinator.suppressScrollPublish = suppressScrollPublishingFromObserver
        coordinator.syncPagingScrollToSelection = syncPagingScrollToSelection
        coordinator.syncPagingScrollAggressive = syncPagingScrollAggressive
        coordinator.attachScrollObserver(anchoredTo: uiView)
        coordinator.applyPagingInteractionIfPossible()
        coordinator.refreshPageInteractionLocksAfterSelectionChange()
        if coordinator.syncScrollToHubPageIfNeeded() {
            context.coordinator.syncPagingScrollToSelection.wrappedValue = false
            context.coordinator.syncPagingScrollAggressive.wrappedValue = true
        }
        if !isPagingInteractionEnabled {
            let c = coordinator
            DispatchQueue.main.async { c.applyPagingInteractionIfPossible() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { c.applyPagingInteractionIfPossible() }
        }
    }

    final class ReaderCoordinator {
        var syncPagingScrollToSelection: Binding<Bool>
        var syncPagingScrollAggressive: Binding<Bool>

        init(
            syncPagingScrollToSelection: Binding<Bool>,
            syncPagingScrollAggressive: Binding<Bool>
        ) {
            self.syncPagingScrollToSelection = syncPagingScrollToSelection
            self.syncPagingScrollAggressive = syncPagingScrollAggressive
        }
    }
}

// MARK: - View hierarchy search (file-local)

private extension UIView {
    func onCuts_hubHorizontalPagingScrollView() -> UIScrollView? {
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

private func onCuts_hubFindPageViewController(from root: UIViewController) -> UIPageViewController? {
    if let p = root as? UIPageViewController { return p }
    for child in root.children {
        if let found = onCuts_hubFindPageViewController(from: child) { return found }
    }
    if let nav = root as? UINavigationController {
        for vc in nav.viewControllers {
            if let found = onCuts_hubFindPageViewController(from: vc) { return found }
        }
    }
    if let tab = root as? UITabBarController {
        for vc in tab.viewControllers ?? [] {
            if let found = onCuts_hubFindPageViewController(from: vc) { return found }
        }
    }
    if let split = root as? UISplitViewController {
        for vc in split.viewControllers {
            if let found = onCuts_hubFindPageViewController(from: vc) { return found }
        }
    }
    if let presented = root.presentedViewController {
        return onCuts_hubFindPageViewController(from: presented)
    }
    return nil
}
#endif
