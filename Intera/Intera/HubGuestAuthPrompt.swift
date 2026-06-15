//
//  HubGuestAuthPrompt.swift
//  Intera
//
//  Shared call-to-action for hub tabs (Messages, Bookings, Profile) when the user is not signed in.
//

import SwiftUI

/// Sign-in / sign-up prompt shown on main-tab hub pages for signed-out users.
struct HubGuestAuthPrompt: View {
    let title: String
    let systemImage: String
    /// Optional copy between the title and the sign-in block.
    var message: String? = nil
    /// Shown directly above the Sign In button.
    let signInCallout: String
    let onSignIn: () -> Void
    let onSignUp: () -> Void

    private let calloutFont = Font.body
    private let calloutColor = Color.lavaShellCreamSecondary

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: systemImage)
                    .font(InteraFont.system(size: 44, weight: .medium))
                    .foregroundStyle(Color.oliveGreen)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)

                Text(title)
                    .font(InteraFont.title2.weight(.bold))
                    .foregroundStyle(Color.lavaShellCream)
                    .multilineTextAlignment(.center)

                if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(message)
                        .font(InteraFont.body)
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    Text(signInCallout)
                        .font(calloutFont)
                        .foregroundStyle(calloutColor)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    PrimaryButton(title: "Sign In", action: onSignIn, size: .large)
                }
                .frame(maxWidth: .infinity)

                PrimaryButton(title: "Sign Up", action: onSignUp, variant: .outline, size: .large)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
    }
}
