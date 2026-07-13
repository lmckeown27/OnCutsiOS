//
//  HubGuestAuthPrompt.swift
//  OnCuts
//
//  Floating sign-in chrome for signed-out hub users — replaces `ConsumerStickyHubBar`
//  over the home provider list (same overlay position and glass treatment).
//

import SwiftUI

enum GuestHubSignInMetrics {
    /// Expanded guest sign-in panel height reference (email + optional password + Apple/Google row).
    static let expandedChromeHeight: CGFloat = 220
    static let minimizedChromeHeight: CGFloat = 88
    static let overlayContentBottomPadding: CGFloat = 240
    /// Centered width for the side-by-side provider pills and email field.
    static let pillMaxWidth: CGFloat = 260

    static func overlayContentBottomInset(collapseProgress: CGFloat) -> CGFloat {
        let expanded = overlayContentBottomPadding
        let collapsed = minimizedChromeHeight + 20
        return expanded - (expanded - collapsed) * min(1, max(0, collapseProgress))
    }
}

/// Sign-in options overlay shown instead of the hub bar when the user is signed out.
@available(iOS 17.0, macOS 14.0, *)
struct GuestHubSignInBar: View {
    let sessionManager: AppSessionManager
    @ObservedObject var appleOAuthFollowUp: AppleOAuthPostSignInCoordinator
    let onContinueWithNewEmail: (String) -> Void
    var collapseProgress: CGFloat = 0

    private static let panelCorner: CGFloat = 28

    var body: some View {
        guestSignInPanel
            .scaleEffect(1.0 - 0.08 * collapseProgress, anchor: .bottom)
            .offset(y: 14 * collapseProgress)
            .opacity(1.0 - 0.18 * collapseProgress)
            .shadow(
                color: .black.opacity(0.18 * (1.0 - collapseProgress * 0.35)),
                radius: 14,
                y: 4
            )
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: collapseProgress)
    }

    private var guestSignInPanel: some View {
        OAuthProviderSignInOptionsContent(
            sessionManager: sessionManager,
            appleOAuthFollowUp: appleOAuthFollowUp,
            layout: .inline,
            showsCreateAccountLink: false,
            showsEmailSignInOption: true,
            providerPillStackAxis: .horizontal,
            pillMaxWidth: GuestHubSignInMetrics.pillMaxWidth,
            onContinueWithNewEmail: onContinueWithNewEmail,
            onSignedIn: {}
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Self.panelCorner, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.panelCorner, style: .continuous)
                .stroke(Color.onCutsShellGlassStroke, lineWidth: 1)
        }
    }
}
