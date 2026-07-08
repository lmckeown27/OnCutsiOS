//
//  InteraHubRenderIsolation.swift
//  Intera
//
//  Prevents the paged hub `TabView` (and scroll bridge) from re-rendering when unrelated
//  shell state changes (hub bar collapse, unread counts, bubble icon tint, etc.).
//

import SwiftUI

/// Re-renders `content` only when `hubPageIndex` or `messagesHubNavigationStackEpoch` change.
struct InteraHubPagerRenderGate<Content: View>: View, Equatable {
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

#if os(iOS)
/// Re-renders the UIKit scroll bridge only when paging sync / lock inputs change.
struct InteraHubScrollBridgeRenderGate<Content: View>: View, Equatable {
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
