//
//  HubGuestAuthPrompt.swift
//  OnCuts
//
//  Floating sign-in chrome for signed-out hub users — replaces `ConsumerStickyHubBar`
//  over the home provider list (same overlay position and glass treatment).
//

import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

enum GuestHubSignInMetrics {
    /// Fallback before the guest panel reports a measured height (labels + email + Apple/Google).
    static let expandedChromeHeight: CGFloat = 236
    static let minimizedChromeHeight: CGFloat = 88
    /// Used until `GuestHubChromeHeightKey` reports a real panel height.
    static let overlayContentBottomPadding: CGFloat = expandedChromeHeight
    /// Centered width for the side-by-side provider pills and email field.
    static let pillMaxWidth: CGFloat = 260
    /// Extra gap between Discover pull-up content and the top of the guest panel / hub padding.
    static let pullUpClearanceGap: CGFloat = 12

    static func overlayContentBottomInset(
        expandedHeight: CGFloat,
        collapseProgress: CGFloat
    ) -> CGFloat {
        let expanded = max(expandedHeight, minimizedChromeHeight + 20)
        let collapsed = minimizedChromeHeight + 20
        return expanded - (expanded - collapsed) * min(1, max(0, collapseProgress))
    }

    static func overlayContentBottomInset(collapseProgress: CGFloat) -> CGFloat {
        overlayContentBottomInset(
            expandedHeight: overlayContentBottomPadding,
            collapseProgress: collapseProgress
        )
    }
}

/// Measured height of the floating guest Sign In / Sign Up panel (for Discover pull-up clearance).
struct GuestHubChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if canImport(UIKit) && !os(watchOS)
/// Overlap of the system keyboard with the key window’s bottom edge (0 when hidden).
enum GuestHubKeyboardOverlap {
    static func overlap(from notification: Notification) -> CGFloat {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
        else {
            return 0
        }
        let converted = window.convert(frame, from: nil)
        return max(0, window.bounds.maxY - converted.minY)
    }

    static func animation(from notification: Notification) -> Animation {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        return .easeOut(duration: max(0.15, duration))
    }
}
#endif

/// Sign-in options overlay shown instead of the hub bar when the user is signed out.
@available(iOS 17.0, macOS 14.0, *)
struct GuestHubSignInBar: View {
    let sessionManager: AppSessionManager
    @ObservedObject var appleOAuthFollowUp: AppleOAuthPostSignInCoordinator
    let onContinueWithNewEmail: (String) -> Void
    var collapseProgress: CGFloat = 0
    /// `true` while the guest email/password chrome is focused or expanded (drives Discover pull-up).
    var authChromeActive: Binding<Bool>? = nil

    #if canImport(UIKit) && !os(watchOS)
    /// Lifts the panel above the keyboard (Discover is full-bleed and ignores safe area).
    @State private var keyboardBottomInset: CGFloat = 0
    #endif

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
            // Measure panel only — keyboard inset must not inflate Discover pull-up clearance.
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: GuestHubChromeHeightKey.self, value: geo.size.height)
                }
            }
            #if canImport(UIKit) && !os(watchOS)
            .padding(.bottom, keyboardBottomInset)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                let next = GuestHubKeyboardOverlap.overlap(from: notification)
                withAnimation(GuestHubKeyboardOverlap.animation(from: notification)) {
                    keyboardBottomInset = next
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                withAnimation(GuestHubKeyboardOverlap.animation(from: notification)) {
                    keyboardBottomInset = 0
                }
            }
            #endif
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
            onSignedIn: {},
            authChromeActive: authChromeActive
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
