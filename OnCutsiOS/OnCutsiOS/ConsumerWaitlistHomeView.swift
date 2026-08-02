//
//  ConsumerWaitlistHomeView.swift
//  OnCuts
//
//  Consumer Home when `consumerHomeMode == waitlist`: title + platform user count
//  (same total as web). Not a roster — joining is create / sign-in as a consumer.
//

import SwiftUI

struct ConsumerWaitlistHomeView: View {
    let userCount: Int
    let isAuthenticated: Bool
    let isRefreshing: Bool
    let onRefresh: () async -> Void
    var onCreateAccount: (() -> Void)?
    var onSignIn: (() -> Void)?

    private var formattedCount: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: userCount)) ?? "\(userCount)"
    }

    /// Large count digits with a smaller trailing “users” label.
    private var userCountLabel: Text {
        Text(formattedCount)
            .font(OnCutsFont.system(size: 64, weight: .bold, design: .rounded))
        + Text(" users")
            .font(OnCutsFont.system(size: 22, weight: .semibold, design: .rounded))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 48)

                Text("\(AppBranding.displayName) Waitlist")
                    .font(OnCutsLiquidGlassTypography.title(34, weight: .bold))
                    .foregroundStyle(Color.onCutsShellForeground)
                    .frame(maxWidth: .infinity)

                if isAuthenticated {
                    VStack(spacing: 10) {
                        Text("You and")
                            .font(OnCutsFont.title3(weight: .semibold))
                            .foregroundStyle(Color.onCutsShellForegroundSecondary)

                        userCountLabel
                            .foregroundStyle(Color.onCutsShellForeground)
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)

                        Text("are patiently waiting for the launch of \(AppBranding.displayName)")
                            .font(OnCutsFont.body)
                            .foregroundStyle(Color.onCutsShellForegroundSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 28)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "You and \(userCount) users are patiently waiting for the launch of \(AppBranding.displayName)"
                    )
                } else {
                    VStack(spacing: 10) {
                        userCountLabel
                            .foregroundStyle(Color.onCutsShellForeground)
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .accessibilityLabel("\(userCount) users on the waitlist")

                        Text("Create an account or sign in to join the waitlist.")
                            .font(OnCutsFont.body)
                            .foregroundStyle(Color.onCutsShellForegroundSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 28)

                    VStack(spacing: 12) {
                        if let onCreateAccount {
                            Button(action: onCreateAccount) {
                                Text("Create account")
                                    .font(OnCutsFont.body(weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.oliveGreen)
                        }
                        if let onSignIn {
                            Button(action: onSignIn) {
                                Text("Sign in")
                                    .font(OnCutsFont.body(weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.oliveGreen)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                }

                if isRefreshing {
                    ProgressView()
                        .tint(Color.oliveGreen)
                        .padding(.top, 8)
                }

                Spacer(minLength: 120)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable {
            await onRefresh()
        }
    }
}
