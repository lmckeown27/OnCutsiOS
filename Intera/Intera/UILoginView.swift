//
//  LoginView.swift
//  Intera
//
//  Created by Liam McKeown on 3/8/26.
//

import CampusCutsModule
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct LoginView: View {
    private enum CarouselPhase {
        case signIn
        case signup
    }

    @Namespace private var emailMorphNS

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isLoading = false
    @State private var isCheckingAccount = false
    @State private var showAuthOutcomeAlert = false
    @State private var authOutcomeTitle = ""
    @State private var authOutcomeMessage = ""
    @State private var showOAuthSignInSheet = false
    @StateObject private var appleOAuthPostSignInCoordinator = AppleOAuthPostSignInCoordinator()
    @State private var showIntegratedSignUpSheet = false

    @State private var didCompleteEmailHandshake = false
    @State private var showCreateAccountPrompt = false
    @State private var loginCardScale: CGFloat = 1
    @State private var carouselPhase: CarouselPhase = .signIn
    @State private var hasOpenedSignupColumn = false

    #if os(iOS)
    @State private var accountNotFoundSensoryTrigger = 0
    #endif

    let sessionManager: AppSessionManager

    private var apiRoot: String { AppConfiguration.messagingAPIRootTrimmed }

    var body: some View {
        NavigationStack {
            ZStack {
                InteraShellBackground()

                GeometryReader { geo in
                    let pageWidth = geo.size.width
                    HStack(spacing: 0) {
                        signInPage(width: pageWidth)
                            .frame(width: pageWidth)

                        if hasOpenedSignupColumn {
                            LiquidGlassSignupFlowView(
                                apiV1BaseTrimmed: apiRoot,
                                sessionManager: sessionManager,
                                onFinished: {
                                    withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                                        carouselPhase = .signIn
                                        loginCardScale = 1
                                    }
                                },
                                handoffEmail: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                emailMorphNamespace: emailMorphNS,
                                signupPanelIsEmailMorphSource: carouselPhase == .signup
                            )
                            .frame(width: pageWidth)
                        } else {
                            Color.clear.frame(width: pageWidth)
                        }
                    }
                    .offset(x: carouselPhase == .signIn ? 0 : -pageWidth)
                    .animation(.spring(response: 0.52, dampingFraction: 0.84), value: carouselPhase)
                }
                .ignoresSafeArea(edges: .bottom)

                if showCreateAccountPrompt {
                    accountNotFoundOverlay
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            #if os(iOS)
            .sensoryFeedback(.warning, trigger: accountNotFoundSensoryTrigger)
            #endif
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showOAuthSignInSheet, onDismiss: {
                let c = appleOAuthPostSignInCoordinator
                guard !c.appleBackendExchangeInProgress else { return }
                c.reset()
            }) {
                OAuthProviderSignInSheet(
                    sessionManager: sessionManager,
                    appleOAuthFollowUp: appleOAuthPostSignInCoordinator,
                    onFinished: {
                        showOAuthSignInSheet = false
                    },
                    onRequestEmailSignUp: {
                        showOAuthSignInSheet = false
                        showIntegratedSignUpSheet = true
                    }
                )
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
            }
            .sheet(isPresented: $showIntegratedSignUpSheet) {
                IntegratedSignUpSheet(sessionManager: sessionManager, onFinished: {
                    showIntegratedSignUpSheet = false
                })
                #if os(iOS)
                .presentationDetents([.large])
                #endif
            }
            .alert(authOutcomeTitle, isPresented: $showAuthOutcomeAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(authOutcomeMessage)
            }
            .interaConsumerShellAppearance()
        }
    }

    // MARK: - Sign-in column

    private func signInPage(width: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 32) {
                logoSection

                PrimaryButton(
                    title: "Sign In",
                    action: { showOAuthSignInSheet = true },
                    isLoading: false,
                    isDisabled: false,
                    size: .large
                )

                loginFormSection

                dividerSection

                #if DEBUG
                devLoginSection
                #endif

                signUpSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(minWidth: width)
        }
        .scaleEffect(loginCardScale)
        .animation(.spring(response: 0.48, dampingFraction: 0.82), value: loginCardScale)
    }

    private var logoSection: some View {
        VStack(spacing: .space4) {
            Image(systemName: "scissors.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.brand.gradient)

            Text("Sign in")
                .font(.displayLarge)
                .foregroundStyle(Color.lavaShellCream)

            Text("Book when you're ready")
                .campusCutsStyle(.bodyMedium)
        }
        .padding(.top, .space10)
    }

    private var loginFormSection: some View {
        VStack(spacing: .space4) {
            VStack(alignment: .leading, spacing: .space2) {
                Text("Email")
                    .campusCutsStyle(.labelLarge)

                TextField("", text: $email)
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    #endif
                    .autocorrectionDisabled()
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: .radiusMedium)
                            .fill(Color.white)
                            .overlay {
                                RoundedRectangle(cornerRadius: .radiusMedium)
                                    .strokeBorder(Color.neutral200, lineWidth: 1)
                            }
                    }
                    .matchedGeometryEffect(
                        id: "authIdentityEmail",
                        in: emailMorphNS,
                        properties: .position,
                        anchor: .leading,
                        isSource: carouselPhase == .signIn
                    )
            }

            if didCompleteEmailHandshake {
                VStack(alignment: .leading, spacing: .space2) {
                    Text("Password")
                        .campusCutsStyle(.labelLarge)

                    HStack(spacing: 10) {
                        Group {
                            if isPasswordVisible {
                                TextField("Enter your password", text: $password)
                            } else {
                                SecureField("Enter your password", text: $password)
                            }
                        }
                        .textContentType(.password)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.neutral600)
                                .frame(minWidth: 28, minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: .radiusMedium)
                            .fill(Color.white)
                            .overlay {
                                RoundedRectangle(cornerRadius: .radiusMedium)
                                    .strokeBorder(Color.neutral200, lineWidth: 1)
                            }
                    }
                }
            }

            if didCompleteEmailHandshake {
                PrimaryButton(
                    title: "Sign in with email",
                    action: { Task { await performLogin() } },
                    isLoading: isLoading,
                    isDisabled: email.isEmpty || password.isEmpty,
                    size: .large
                )
            } else {
                PrimaryButton(
                    title: "Continue",
                    action: { Task { await handshakeCheckAccount() } },
                    isLoading: isCheckingAccount,
                    isDisabled: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    size: .large
                )
            }

        }
    }

    private var dividerSection: some View {
        HStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)

            Text("OR")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
    }

    #if DEBUG
    private var devLoginSection: some View {
        VStack(spacing: .space3) {
            Text("Development Login")
                .campusCutsStyle(.caption)

            HStack(spacing: .space3) {
                Button {
                    sessionManager.mockLogin(as: .student)
                } label: {
                    Text("Student")
                        .campusCutsStyle(.caption)
                        .padding(.horizontal, .space4)
                        .padding(.vertical, .space2)
                        .background {
                            RoundedRectangle(cornerRadius: .radiusMedium)
                                .fill(Color.success.opacity(0.2))
                        }
                        .foregroundStyle(Color.success)
                }

                Button {
                    sessionManager.mockLogin(as: .barber)
                } label: {
                    Text("Barber")
                        .campusCutsStyle(.caption)
                        .padding(.horizontal, .space4)
                        .padding(.vertical, .space2)
                        .background {
                            RoundedRectangle(cornerRadius: .radiusMedium)
                                .fill(Color.brand.opacity(0.2))
                        }
                        .foregroundStyle(Color.brand)
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: .radiusLarge)
                .fill(Color.warning.opacity(0.1))
        }
    }
    #endif

    private var signUpSection: some View {
        HStack(spacing: 6) {
            Text("Don't have an account?")
                .foregroundStyle(.secondary)

            Button {
                showIntegratedSignUpSheet = true
            } label: {
                Text("Sign Up")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .font(.subheadline)
    }

    // MARK: - Account not found overlay

    private var accountNotFoundOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Text("No account found for this email.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 320)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    }

                Text("We couldn't find an account with that email. Would you like to create one now?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                        showCreateAccountPrompt = false
                        loginCardScale = 0.9
                        hasOpenedSignupColumn = true
                        carouselPhase = .signup
                    }
                } label: {
                    Text("Start Registration")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.1, green: 0.55, blue: 0.52),
                                            Color(red: 0.15, green: 0.35, blue: 0.75),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .shadow(color: Color(red: 0.1, green: 0.5, blue: 0.55).opacity(0.55), radius: 16, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)

                Button("Cancel") {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showCreateAccountPrompt = false
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 28, y: 14)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Actions

    private func handshakeCheckAccount() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else {
            let o = InteraAuthUserMessaging.invalidEmailFormatOutcome()
            authOutcomeTitle = o.title
            authOutcomeMessage = o.message
            showAuthOutcomeAlert = true
            return
        }
        isCheckingAccount = true
        defer { isCheckingAccount = false }

        do {
            let exists = try await CampusCutsAuthService.checkAccount(email: trimmed, apiV1BaseTrimmed: apiRoot)
            if exists {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                    didCompleteEmailHandshake = true
                }
            } else {
                triggerAccountNotFoundFeedback()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                    showCreateAccountPrompt = true
                }
            }
        } catch {
            let o = InteraAuthUserMessaging.emailPasswordOutcome(for: error)
            authOutcomeTitle = o.title
            authOutcomeMessage = o.message
            showAuthOutcomeAlert = true
        }
    }

    private func triggerAccountNotFoundFeedback() {
        #if os(iOS)
        accountNotFoundSensoryTrigger += 1
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.prepare()
        for i in 0 ..< 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07 * Double(i)) {
                gen.impactOccurred(intensity: 0.85)
            }
        }
        #endif
    }

    private func performLogin() async {
        isLoading = true
        defer { isLoading = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let verified = try await CampusCutsAuthService.loginWithEmailPassword(
                email: trimmedEmail,
                password: password,
                apiV1BaseTrimmed: apiRoot
            )
            sessionManager.login(session: UserSession(campusCutsVerified: verified))
            await sessionManager.refreshProfileFromServer()
        } catch {
            let o = InteraAuthUserMessaging.emailPasswordOutcome(for: error)
            authOutcomeTitle = o.title
            authOutcomeMessage = o.message
            showAuthOutcomeAlert = true
        }
    }
}

#Preview("Login View") {
    if #available(iOS 17.0, macOS 14.0, *) {
        LoginView(sessionManager: AppSessionManager())
    }
}

#Preview("Login View - Authenticated") {
    if #available(iOS 17.0, macOS 14.0, *) {
        LoginAuthenticatedPreviewHost()
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct LoginAuthenticatedPreviewHost: View {
    @State private var sessionManager = AppSessionManager()

    var body: some View {
        LoginView(sessionManager: sessionManager)
            .onAppear { sessionManager.mockLogin() }
    }
}
