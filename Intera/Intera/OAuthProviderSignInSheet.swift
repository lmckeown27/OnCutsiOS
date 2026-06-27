//
//  OAuthProviderSignInSheet.swift
//  Intera
//
//  Sign in with Apple, Google, and email. (Phone placeholder commented out until SMS sign-in is integrated.)
//

import AuthenticationServices
import AvilaPlatformsModule
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
enum OAuthProviderSignInOptionsLayout {
    /// Sheet presentation: bottom-aligned create-account link and frosted backdrop.
    case sheet
    /// Hub guest tabs: pills flow in scroll content without sheet chrome.
    case inline
}

// MARK: - Physical press (matches Book control: easeInOut scale + light impact)

@available(iOS 17.0, macOS 14.0, *)
private struct SignInPopupPhysicalPressModifier: ViewModifier {
    private static let animation = Animation.easeInOut(duration: 0.14)

    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(Self.animation, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                    }
            )
    }
}

@available(iOS 17.0, macOS 14.0, *)
private extension View {
    func signInPopupPhysicalPress() -> some View {
        modifier(SignInPopupPhysicalPressModifier())
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct OAuthProviderSignInOptionsContent: View {
    let sessionManager: AppSessionManager
    @ObservedObject var appleOAuthFollowUp: AppleOAuthPostSignInCoordinator
    var layout: OAuthProviderSignInOptionsLayout = .sheet
    var showsCreateAccountLink: Bool = true
    var showsEmailSignInOption: Bool = true
    /// When `.horizontal`, Apple and Google pills sit side by side (compact icon treatment).
    var providerPillStackAxis: Axis = .vertical
    /// When set, provider pills are centered at this width instead of spanning the container.
    var pillMaxWidth: CGFloat? = nil
    let onNavigateToEmail: () -> Void
    var onCreateAccount: (() -> Void)?
    let onSignedIn: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var showAuthOutcomeAlert = false
    @State private var authOutcomeTitle = ""
    @State private var authOutcomeMessage = ""
    #if os(iOS) || os(visionOS)
    @StateObject private var appleNativeSignInPresenterBox = AppleNativeSignInPresenterBox()
    #endif

    private var showPrimaryOAuthProviderRows: Bool { !sessionManager.isAuthenticated }

    var body: some View {
        Group {
            switch layout {
            case .sheet:
                sheetLayoutBody
            case .inline:
                inlineLayoutBody
            }
        }
        .alert(authOutcomeTitle, isPresented: $showAuthOutcomeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authOutcomeMessage)
        }
    }

    private var providerPills: some View {
        Group {
            if providerPillStackAxis == .horizontal {
                HStack(spacing: 10) {
                    #if os(iOS) || os(macOS) || os(visionOS)
                    signInWithApplePillCompact
                    #endif
                    googleSignInPillCompact
                }
            } else {
                VStack(spacing: 14) {
                    #if os(iOS) || os(macOS) || os(visionOS)
                    signInWithApplePill
                    #endif
                    googleSignInPill
                }
            }
        }
        .modifier(OAuthSignInPillWidthModifier(maxWidth: pillMaxWidth))
        .opacity(showPrimaryOAuthProviderRows ? 1 : 0)
        .allowsHitTesting(showPrimaryOAuthProviderRows)
        .accessibilityHidden(!showPrimaryOAuthProviderRows)
    }

    @ViewBuilder
    private var manualSignInSection: some View {
        if showsEmailSignInOption {
            manualSignInPill
                .modifier(OAuthSignInPillWidthModifier(maxWidth: pillMaxWidth))
                .opacity(showPrimaryOAuthProviderRows ? 1 : 0)
                .allowsHitTesting(showPrimaryOAuthProviderRows)
            oauthOrDivider
                .modifier(OAuthSignInPillWidthModifier(maxWidth: pillMaxWidth))
                .padding(.top, providerPillStackAxis == .horizontal ? 6 : 16)
                .opacity(showPrimaryOAuthProviderRows ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    private var sheetLayoutBody: some View {
        VStack(spacing: 0) {
            manualSignInSection
                .padding(.horizontal, 22)
                .padding(.top, 8)

            providerPills
                .padding(.horizontal, 22)
                .padding(.top, showsEmailSignInOption ? 4 : 8)

            Spacer(minLength: 0)

            if showsCreateAccountLink, let onCreateAccount {
                oauthOrDivider
                    .padding(.horizontal, 22)
                createAccountLink(action: onCreateAccount)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                    .opacity(showPrimaryOAuthProviderRows ? 1 : 0)
                    .allowsHitTesting(showPrimaryOAuthProviderRows)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(Color.black.opacity(0.22))
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }

    private var inlineLayoutBody: some View {
        VStack(spacing: 0) {
            manualSignInSection

            providerPills
                .padding(.top, showsEmailSignInOption ? 4 : 0)

            if showsCreateAccountLink, let onCreateAccount {
                oauthOrDivider
                    .modifier(OAuthSignInPillWidthModifier(maxWidth: pillMaxWidth))
                    .padding(.top, providerPillStackAxis == .horizontal ? 6 : 16)
                createAccountLink(action: onCreateAccount)
                    .modifier(OAuthSignInPillWidthModifier(maxWidth: pillMaxWidth))
                    .padding(.top, 4)
                    .opacity(showPrimaryOAuthProviderRows ? 1 : 0)
                    .allowsHitTesting(showPrimaryOAuthProviderRows)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sign in with Apple (Guideline 4.8)

    #if os(iOS) || os(macOS) || os(visionOS)
    private static let applePillText = Color.black

    private var signInWithApplePill: some View {
        Group {
            #if os(iOS) || os(visionOS)
            Button {
                startNativeSignInWithApple()
            } label: {
                signInWithApplePillChrome
            }
            .buttonStyle(.plain)
            .signInPopupPhysicalPress()
            .disabled(appleOAuthFollowUp.appleBackendExchangeInProgress)
            #elseif os(macOS)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Self.oauthPillHeight)
            .padding(.horizontal, 20)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Self.googleButtonBorder, lineWidth: 1)
                    }
            }
            .clipShape(Capsule(style: .continuous))
            .signInPopupPhysicalPress()
            #endif
        }
    }

    #if os(iOS) || os(visionOS)
    private var signInWithApplePillChrome: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Image(systemName: "apple.logo")
                    .font(InteraFont.title3.weight(.semibold))
                    .foregroundStyle(Self.applePillText)
                Text("Sign in with Apple")
                    .font(InteraFont.body.weight(.semibold))
                    .foregroundStyle(Self.applePillText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: Self.oauthPillHeight)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Self.googleButtonBorder, lineWidth: 1)
                }
        }
    }

    private func startNativeSignInWithApple() {
        guard !sessionManager.isAuthenticated else { return }
        guard !appleOAuthFollowUp.appleBackendExchangeInProgress else { return }
        appleNativeSignInPresenterBox.presenter.resetForNewUserInitiatedSignIn()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let callbackOnce = AppleAuthorizationCallbackOnce()
        appleNativeSignInPresenterBox.presenter.performSignIn(request: request) { result in
            Task { @MainActor in
                guard callbackOnce.consume() else { return }
                handleAppleSignInResult(result)
            }
        }
    }
    #endif

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        Task { @MainActor in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let identityToken = String(data: tokenData, encoding: .utf8)
                else {
                    authOutcomeTitle = "Sign In With Apple"
                    authOutcomeMessage = AppleSignInFlowError.missingIdentityToken.localizedDescription
                    showAuthOutcomeAlert = true
                    return
                }
                if sessionManager.isAuthenticated {
                    return
                }
                if appleOAuthFollowUp.appleBackendExchangeInProgress {
                    return
                }
                appleOAuthFollowUp.appleBackendExchangeInProgress = true
                do {
                    try await AppleSignInAppSupport.completeLogin(
                        identityToken: identityToken,
                        credential: credential,
                        sessionManager: sessionManager,
                        presetPlatformPassword: nil
                    )
                    appleOAuthFollowUp.appleBackendExchangeInProgress = false
                    onSignedIn()
                } catch {
                    appleOAuthFollowUp.appleBackendExchangeInProgress = false
                    let outcome = InteraAuthUserMessaging.appleSignInOutcome(for: error)
                    authOutcomeTitle = outcome.title
                    authOutcomeMessage = outcome.message
                    showAuthOutcomeAlert = true
                    ProductionLogging.recordNonFatal(error, context: ["area": "apple_sign_in"])
                    return
                }
            case .failure(let error):
                if let authErr = error as? ASAuthorizationError, authErr.code == .canceled {
                    return
                }
                let outcome = InteraAuthUserMessaging.appleSignInOutcome(for: error)
                authOutcomeTitle = outcome.title
                authOutcomeMessage = outcome.message
                showAuthOutcomeAlert = true
                ProductionLogging.recordNonFatal(error, context: ["area": "apple_sign_in"])
            }
        }
    }
    #endif

    // MARK: Google

    private static let oauthPillHeight: CGFloat = 54
    private static let compactOAuthPillHeight: CGFloat = 48
    private static let googleButtonText = Color(red: 0.24, green: 0.25, blue: 0.26)
    private static let googleButtonBorder = Color(red: 0.86, green: 0.87, blue: 0.88)

    #if os(iOS) || os(macOS) || os(visionOS)
    private var signInWithApplePillCompact: some View {
        Group {
            #if os(iOS) || os(visionOS)
            Button {
                startNativeSignInWithApple()
            } label: {
                signInWithApplePillCompactChrome
            }
            .buttonStyle(.plain)
            .signInPopupPhysicalPress()
            .disabled(appleOAuthFollowUp.appleBackendExchangeInProgress)
            .accessibilityLabel("Sign in with Apple")
            #elseif os(macOS)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Self.compactOAuthPillHeight)
            .clipShape(Capsule(style: .continuous))
            .signInPopupPhysicalPress()
            #endif
        }
    }

    #if os(iOS) || os(visionOS)
    private var signInWithApplePillCompactChrome: some View {
        Image(systemName: "apple.logo")
            .font(InteraFont.title3.weight(.semibold))
            .foregroundStyle(Self.applePillText)
            .frame(maxWidth: .infinity)
            .frame(height: Self.compactOAuthPillHeight)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Self.googleButtonBorder, lineWidth: 1)
                    }
            }
    }
    #endif
    #endif

    private var googleSignInPillCompact: some View {
        Button {
            Task {
                do {
                    try await GoogleSignInAppSupport.signInInteractively(sessionManager: sessionManager)
                    onSignedIn()
                } catch {
                    guard !InteraAuthUserMessaging.isGoogleSignInCancellation(error) else { return }
                    let outcome = InteraAuthUserMessaging.googleSignInOutcome(for: error)
                    authOutcomeTitle = outcome.title
                    authOutcomeMessage = outcome.message
                    showAuthOutcomeAlert = true
                    ProductionLogging.recordNonFatal(error, context: ["area": "google_sign_in"])
                }
            }
        } label: {
            googleSignInAssetIcon(size: 22)
                .frame(maxWidth: .infinity)
                .frame(height: Self.compactOAuthPillHeight)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.white)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Self.googleButtonBorder, lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .signInPopupPhysicalPress()
        .accessibilityLabel("Sign in with Google")
    }

    private var googleSignInPill: some View {
        Button {
            Task {
                do {
                    try await GoogleSignInAppSupport.signInInteractively(sessionManager: sessionManager)
                    onSignedIn()
                } catch {
                    guard !InteraAuthUserMessaging.isGoogleSignInCancellation(error) else { return }
                    let outcome = InteraAuthUserMessaging.googleSignInOutcome(for: error)
                    authOutcomeTitle = outcome.title
                    authOutcomeMessage = outcome.message
                    showAuthOutcomeAlert = true
                    ProductionLogging.recordNonFatal(error, context: ["area": "google_sign_in"])
                }
            }
        } label: {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    googleSignInAssetIcon(size: 22)
                    Text("Sign in with Google")
                        .font(InteraFont.body.weight(.semibold))
                        .foregroundStyle(Self.googleButtonText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: Self.oauthPillHeight)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Self.googleButtonBorder, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .signInPopupPhysicalPress()
    }

    private func googleSignInAssetIcon(size: CGFloat) -> some View {
        Image("Google")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    // MARK: Manual sign-in (email / password)

    private var manualSignInPill: some View {
        Button {
            onNavigateToEmail()
        } label: {
            Text("Manual Sign-In")
                .font(InteraFont.body.weight(.semibold))
                .foregroundStyle(BookingSelectorTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    Capsule(style: .continuous)
                        .strokeBorder(BookingSelectorTheme.cream, lineWidth: 1)
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .signInPopupPhysicalPress()
    }

    // MARK: Create account

    private var oauthOrDivider: some View {
        Text("or")
            .font(InteraFont.caption.weight(.medium))
            .foregroundStyle(BookingSelectorTheme.cream.opacity(0.62))
            .frame(maxWidth: .infinity)
    }

    private func createAccountLink(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Create Account")
                .font(InteraFont.subheadline.weight(.semibold))
                .foregroundStyleOliveGreen()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            InteraOliveGreenTextStyle.outlineColor(for: colorScheme),
                            lineWidth: 1.5
                        )
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .signInPopupPhysicalPress()
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct OAuthSignInPillWidthModifier: ViewModifier {
    let maxWidth: CGFloat?

    func body(content: Content) -> some View {
        if let maxWidth {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct OAuthProviderSignInSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sessionManager: AppSessionManager
    let onFinished: () -> Void
    /// When set, shows **Create account** to open package-driven email sign-up (`IntegratedSignUpFlowRegistry`).
    var onRequestEmailSignUp: (() -> Void)?
    /// When `false`, hides the bottom “Create account” link (e.g. user already chose Sign Up on the prior sheet).
    var showsCreateAccountLink: Bool

    @State private var showsEmailSignInRoot = false
    /// Owned by the parent that presents this sheet so `login()` / `AppSessionManager` updates do not reset `@State`.
    @ObservedObject private var appleOAuthFollowUp: AppleOAuthPostSignInCoordinator

    init(
        sessionManager: AppSessionManager,
        appleOAuthFollowUp: AppleOAuthPostSignInCoordinator,
        onFinished: @escaping () -> Void,
        onRequestEmailSignUp: (() -> Void)? = nil,
        showsCreateAccountLink: Bool = true
    ) {
        self.sessionManager = sessionManager
        self._appleOAuthFollowUp = ObservedObject(wrappedValue: appleOAuthFollowUp)
        self.onFinished = onFinished
        self.onRequestEmailSignUp = onRequestEmailSignUp
        self.showsCreateAccountLink = showsCreateAccountLink
    }

    var body: some View {
        NavigationStack {
            Group {
                if showsEmailSignInRoot {
                    emailSignInScreen
                } else {
                    OAuthProviderSignInOptionsContent(
                        sessionManager: sessionManager,
                        appleOAuthFollowUp: appleOAuthFollowUp,
                        layout: .sheet,
                        showsCreateAccountLink: showsCreateAccountLink,
                        onNavigateToEmail: { showsEmailSignInRoot = true },
                        onCreateAccount: {
                            dismiss()
                            onRequestEmailSignUp?()
                        },
                        onSignedIn: {
                            onFinished()
                            dismiss()
                        }
                    )
                }
            }
            .navigationTitle(showsEmailSignInRoot ? "Manual Sign-In" : "Sign In")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear { dismissIfAlreadySignedIn() }
            .onChange(of: sessionManager.isAuthenticated) { _, authed in
                if authed { showsEmailSignInRoot = false }
            }
        }
    }

    private var emailSignInScreen: some View {
        EmailPasswordSignInView(
            sessionManager: sessionManager,
            apiV1BaseTrimmed: AppConfiguration.messagingAPIRootTrimmed,
            onSignedIn: {
                onFinished()
                dismiss()
            },
            onRequestSignUp: {
                dismiss()
                onRequestEmailSignUp?()
            }
        )
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        #endif
    }

    private func dismissIfAlreadySignedIn() {
        guard sessionManager.isAuthenticated else { return }
        guard !appleOAuthFollowUp.appleBackendExchangeInProgress else { return }
        onFinished()
        dismiss()
    }
}
