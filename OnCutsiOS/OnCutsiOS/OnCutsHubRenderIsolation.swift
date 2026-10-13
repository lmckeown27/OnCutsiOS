//
//  OnCutsHubRenderIsolation.swift
//  OnCuts
//
//  Prevents the paged hub `TabView` (and scroll bridge) from re-rendering when unrelated
//  shell state changes (hub bar collapse, unread counts, bubble icon tint, etc.).
//

import SwiftUI

/// Re-renders `content` only when `hubPageIndex` or `messagesHubNavigationStackEpoch` change.
struct OnCutsHubPagerRenderGate<Content: View>: View, Equatable {
    var hubPageIndex: Int
    var messagesHubNavigationStackEpoch: Int
    @ViewBuilder var content: () -> Content

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hubPageIndex == rhs.hubPageIndex
            && lhs.messagesHubNavigationStackEpoch == rhs.messagesHubNavigationStackEpoch
    }

    var body: some View {
        content()
    }
}

/// Holds a page's hub-bar inset while another page is showing. The inset tracks hub bar collapse, which animates
/// on every scroll of the visible page; environment changes bypass `OnCutsHubPagerRenderGate`.
struct OnCutsHubOffPageInsetFreeze: ViewModifier {
    /// `nil` passes the live inset through (page is showing).
    var frozenInset: CGFloat?

    func body(content: Content) -> some View {
        content.transformEnvironment(\.onCutsHubBarOverlayBottomInset) { inset in
            if let frozenInset { inset = frozenInset }
        }
    }
}

#if os(iOS)
/// Re-renders the UIKit scroll bridge only when paging sync / lock inputs change.
struct OnCutsHubScrollBridgeRenderGate<Content: View>: View, Equatable {
    var hubPageIndex: Int
    var isPagingInteractionEnabled: Bool
    var syncPagingScrollToSelection: Bool
    var suppressScrollPublishingFromObserver: Bool
    @ViewBuilder var content: () -> Content

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hubPageIndex == rhs.hubPageIndex
            && lhs.isPagingInteractionEnabled == rhs.isPagingInteractionEnabled
            && lhs.syncPagingScrollToSelection == rhs.syncPagingScrollToSelection
            && lhs.suppressScrollPublishingFromObserver == rhs.suppressScrollPublishingFromObserver
    }

    var body: some View {
        content()
    }
}
#endif
