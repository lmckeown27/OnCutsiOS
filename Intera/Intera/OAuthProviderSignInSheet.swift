//
//  OAuthProviderSignInSheet.swift
//  Intera
//
//  Sign in with Apple, Google, and email. (Phone placeholder commented out until SMS sign-in is integrated.)
//

import AuthenticationServices
import CampusCutsModule
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
private enum OAuthSignInSubroute: Hashable {
    // case phone — re-enable with `Phone number` button below
    case email
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
struct OAuthProviderSignInSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sessionManager: AppSessionManager
    let onFinished: () -> Void
    /// When set, shows **Create account** to open package-driven email sign-up (`IntegratedSignUpFlowRegistry`).
    var onRequestEmailSignUp: (() -> Void)?
    /// When `false`, hides the bottom “Create account” link (e.g. user already chose Sign Up on the prior sheet).
    var showsCreateAccountLink: Bool

    @State private var showAuthOutcomeAlert = false
    @State private var authOutcomeTitle = ""
    @State private var authOutcomeMessage = ""
    @State private var path: [OAuthSignInSubroute] = []
    #if os(iOS) || os(visionOS)
    @StateObject private var appleNativeSignInPresenterBox = AppleNativeSignInPresenterBox()
    #endif
    /// Owned by the parent that presents this sheet so `login()` / `AppSessionManager` updates do not reset `@State`.
    @ObservedObject private var appleOAuthFollowUp: AppleOAuthPostSignInCoordinator

    private var apiRoot: String { AppConfiguration.messagingAPIRootTrimmed }

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
        NavigationStack(path: $path) {
            signInOptionsRoot
                .navigationDestination(for: OAuthSignInSubroute.self) { route in
                    switch route {
                    case .email:
                        EmailPasswordSignInView(
                            sessionManager: sessionManager,
                            apiV1BaseTrimmed: apiRoot,
                            onSignedIn: {
                                onFinished()
                                dismiss()
                            },
                            onRequestSignUp: {
                                dismiss()
                                onRequestEmailSignUp?()
                            }
                        )
                    }
                }
                .navigationTitle("Sign In")
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
                .alert(authOutcomeTitle, isPresented: $showAuthOutcomeAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(authOutcomeMessage)
                }
                .onAppear { dismissIfAlreadySignedIn() }
                /// After Apple / Google sign-in, `isAuthenticated` flips while `path` may still hold `.email` — clear so reviewers never see password fields “after” Apple.
                .onChange(of: sessionManager.isAuthenticated) { _, authed in
                    if authed { path = [] }
                }
        }
    }

    private func dismissIfAlreadySignedIn() {
        guard sessionManager.isAuthenticated else { return }
        // During `completeLogin` the session becomes authenticated while this flag is still true; avoid dismissing
        // until the Apple exchange finishes so the sheet can close cleanly.
        guard !appleOAuthFollowUp.appleBackendExchangeInProgress else { return }
        onFinished()
        dismiss()
    }

    /// Keep sign-in pills in the hierarchy after `login()` flips `isAuthenticated`.
    /// Removing rows with `if !isAuthenticated` can recreate `NavigationStack` content and reset `@State`,
    /// which can dismiss the OAuth UI unexpectedly right after sign-in.
    private var showPrimaryOAuthProviderRows: Bool { !sessionManager.isAuthenticated }

    private var signInOptionsRoot: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                #if os(iOS) || os(macOS) || os(visionOS)
                signInWithApplePill
                #endif
                googleSignInPill
                continueWithEmailPill
            }
            .opacity(showPrimaryOAuthProviderRows ? 1 : 0)
            .allowsHitTesting(showPrimaryOAuthProviderRows)
            .accessibilityHidden(!showPrimaryOAuthProviderRows)
            .padding(.horizontal, 22)
            .padding(.top, 8)

            Spacer(minLength: 0)

            if showsCreateAccountLink, let onRequestEmailSignUp {
                createAccountLink(onRequestEmailSignUp: onRequestEmailSignUp)
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

    // MARK: - Sign in with Apple (Guideline 4.8)

    #if os(iOS) || os(macOS) || os(visionOS)
    /// White pill styling shared with the custom iOS button; macOS uses `SignInWithAppleButton` in the same footprint.
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Self.applePillText)
                Text("Sign in with Apple")
                    .font(.body.weight(.semibold))
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

    /// Presents only the system Sign in with Apple UI (Face ID / passcode). Name and email come from Authentication Services + Keychain replay.
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
                    onFinished()
                    dismiss()
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

    // MARK: Google — same pill layout / press as peers; white “Sign in with Google” treatment + brand colors

    /// Shared vertical size for Apple + Google provider rows.
    private static let oauthPillHeight: CGFloat = 54

    /// Google brand neutrals (Sign-in button guidelines).
    private static let googleButtonText = Color(red: 0.24, green: 0.25, blue: 0.26)
    private static let googleButtonBorder = Color(red: 0.86, green: 0.87, blue: 0.88)

    private var googleSignInPill: some View {
        Button {
            Task {
                do {
                    try await GoogleSignInAppSupport.signInInteractively(sessionManager: sessionManager)
                    onFinished()
                    dismiss()
                } catch {
                    let outcome = InteraAuthUserMessaging.oauthSignInOutcome(for: error)
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
                    GoogleFourColorRingGlyph(size: 22)
                    Text("Sign in with Google")
                        .font(.body.weight(.semibold))
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

    // MARK: Email — ghost

    private var continueWithEmailPill: some View {
        Button {
            path.append(.email)
        } label: {
            Text("Continue with Email")
                .font(.body.weight(.semibold))
                .foregroundStyle(BookingSelectorTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    Capsule(style: .continuous)
                        .strokeBorder(BookingSelectorTheme.cream, lineWidth: 1)
                }
                // Text only hit-tests glyphs; expand to the full ghost pill.
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .signInPopupPhysicalPress()
    }

    // MARK: Create account (Past link)

    private func createAccountLink(onRequestEmailSignUp: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            onRequestEmailSignUp()
        } label: {
            Text("Create account")
                .bookingCalendarWeekdayLabelStyle()
                .foregroundStyle(BookingSelectorTheme.cream)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Google identity glyph (brand palette ring)

/// Four-color arc ring using Google’s standard blue / red / yellow / green — reads instantly as Google next to email sign-in.
@available(iOS 17.0, macOS 14.0, *)
private struct GoogleFourColorRingGlyph: View {
    var size: CGFloat = 22

    private var lineWidth: CGFloat { max(2.25, size * 0.12) }

    private static let blue = Color(red: 0.26, green: 0.52, blue: 0.96)
    private static let red = Color(red: 0.92, green: 0.25, blue: 0.21)
    private static let yellow = Color(red: 0.98, green: 0.74, blue: 0.02)
    private static let green = Color(red: 0.20, green: 0.66, blue: 0.33)

    private var segmentColors: [Color] {
        [Self.blue, Self.red, Self.yellow, Self.green]
    }

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .trim(from: CGFloat(i) * 0.25, to: CGFloat(i) * 0.25 + 0.24)
                    .stroke(
                        segmentColors[i],
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
