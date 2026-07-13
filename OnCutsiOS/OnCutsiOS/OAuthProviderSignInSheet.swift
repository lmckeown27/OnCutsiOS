//
//  OAuthProviderSignInSheet.swift
//  OnCuts
//
//  Sign in with Apple, Google, and email. (Phone placeholder commented out until SMS sign-in is integrated.)
//

import AuthenticationServices
import OnCutsModule
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
    /// Legacy: only shown when the email field is hidden (`showsEmailSignInOption == false`).
    var showsCreateAccountLink: Bool = false
    var showsEmailSignInOption: Bool = true
    /// When `.horizontal`, Apple and Google pills sit side by side (compact icon treatment).
    var providerPillStackAxis: Axis = .vertical
    /// When set, provider pills are centered at this width instead of spanning the container.
    var pillMaxWidth: CGFloat? = nil
    /// Unknown email — continue to Create Account with this email prefilled.
    var onContinueWithNewEmail: ((String) -> Void)?
    let onSignedIn: () -> Void

    @State private var emailEntry = ""
    @State private var passwordEntry = ""
    @State private var isPasswordVisible = false
    @State private var didCompleteEmailHandshake = false
    @State private var isCheckingAccount = false
    @State private var isSigningIn = false
    @State private var showAuthOutcomeAlert = false
    @State private var authOutcomeTitle = ""
    @State private var authOutcomeMessage = ""
    @FocusState private var focusedAuthField: AuthField?
    #if os(iOS) || os(visionOS)
    @StateObject private var appleNativeSignInPresenterBox = AppleNativeSignInPresenterBox()
    #endif

    private enum AuthField: Hashable {
        case email
        case password
    }

    private var showPrimaryOAuthProviderRows: Bool { !sessionManager.isAuthenticated }
    private var apiV1BaseTrimmed: String { AppConfiguration.messagingAPIRootTrimmed }
    /// Create Account is folded into the email field handshake; only expose a separate link when email entry is off.
    private var showsStandaloneCreateAccountLink: Bool {
        showsCreateAccountLink && !showsEmailSignInOption && onContinueWithNewEmail != nil
    }

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

    private func dismissAuthKeyboard() {
        focusedAuthField = nil
        #if canImport(UIKit) && !os(watchOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
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
    private var emailHandshakeSection: some View {
        if showsEmailSignInOption {
            VStack(spacing: 10) {
                emailHandshakeField
                if didCompleteEmailHandshake {
                    passwordHandshakeField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.88), value: didCompleteEmailHandshake)
            .modifier(OAuthSignInPillWidthModifier(maxWidth: pillMaxWidth))
            .opacity(showPrimaryOAuthProviderRows ? 1 : 0)
            .allowsHitTesting(showPrimaryOAuthProviderRows)

            oauthOrDivider
                .modifier(OAuthSignInPillWidthModifier(maxWidth: pillMaxWidth))
                .padding(.top, providerPillStackAxis == .horizontal ? 6 : 12)
                .opacity(showPrimaryOAuthProviderRows ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    private var sheetLayoutBody: some View {
        VStack(spacing: 0) {
            emailHandshakeSection
                .padding(.horizontal, 22)
                .padding(.top, 8)

            providerPills
                .padding(.horizontal, 22)
                .padding(.top, showsEmailSignInOption ? 4 : 8)
                .simultaneousGesture(TapGesture().onEnded { dismissAuthKeyboard() })

            Spacer(minLength: 0)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { dismissAuthKeyboard() }

            if showsStandaloneCreateAccountLink, let onContinueWithNewEmail {
                oauthOrDivider
                    .padding(.horizontal, 22)
                createAccountLink(action: { onContinueWithNewEmail("") })
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
            .contentShape(Rectangle())
            .onTapGesture { dismissAuthKeyboard() }
        }
    }

    private var inlineLayoutBody: some View {
        VStack(spacing: 0) {
            emailHandshakeSection

            providerPills
                .padding(.top, showsEmailSignInOption ? 4 : 0)
                .simultaneousGesture(TapGesture().onEnded { dismissAuthKeyboard() })

            if showsStandaloneCreateAccountLink, let onContinueWithNewEmail {
                oauthOrDivider
                    .modifier(OAuthSignInPillWidthModifier(maxWidth: pillMaxWidth))
                    .padding(.top, providerPillStackAxis == .horizontal ? 6 : 16)
                createAccountLink(action: { onContinueWithNewEmail("") })
                    .modifier(OAuthSignInPillWidthModifier(maxWidth: pillMaxWidth))
                    .padding(.top, 4)
                    .opacity(showPrimaryOAuthProviderRows ? 1 : 0)
                    .allowsHitTesting(showPrimaryOAuthProviderRows)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismissAuthKeyboard() }
        }
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
                    .font(OnCutsFont.title3(weight: .semibold))
                    .foregroundStyle(Self.applePillText)
                Text("Sign in with Apple")
                    .font(OnCutsFont.body(weight: .semibold))
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
        dismissAuthKeyboard()
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
                    let outcome = OnCutsAuthUserMessaging.appleSignInOutcome(for: error)
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
                let outcome = OnCutsAuthUserMessaging.appleSignInOutcome(for: error)
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
            .font(OnCutsFont.title3(weight: .semibold))
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
            dismissAuthKeyboard()
            Task {
                do {
                    try await GoogleSignInAppSupport.signInInteractively(sessionManager: sessionManager)
                    onSignedIn()
                } catch {
                    guard !OnCutsAuthUserMessaging.isGoogleSignInCancellation(error) else { return }
                    let outcome = OnCutsAuthUserMessaging.googleSignInOutcome(for: error)
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
            dismissAuthKeyboard()
            Task {
                do {
                    try await GoogleSignInAppSupport.signInInteractively(sessionManager: sessionManager)
                    onSignedIn()
                } catch {
                    guard !OnCutsAuthUserMessaging.isGoogleSignInCancellation(error) else { return }
                    let outcome = OnCutsAuthUserMessaging.googleSignInOutcome(for: error)
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
                        .font(OnCutsFont.body(weight: .semibold))
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

    // MARK: Email handshake (sign-in vs create account)

    private var emailHandshakeField: some View {
        HStack(spacing: 10) {
            TextField("Email", text: $emailEntry)
                .font(OnCutsFont.body(weight: .medium))
                .foregroundStyle(BookingSelectorTheme.cream)
                .tint(BookingSelectorTheme.cream)
                .textContentType(.emailAddress)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .focused($focusedAuthField, equals: .email)
                .submitLabel(.continue)
                .onSubmit {
                    Task { await continueWithEmailHandshake() }
                }
                .onChange(of: emailEntry) { _, _ in
                    if didCompleteEmailHandshake {
                        didCompleteEmailHandshake = false
                        passwordEntry = ""
                        isPasswordVisible = false
                        focusedAuthField = .email
                    }
                }
                .disabled(isCheckingAccount || isSigningIn)

            Button {
                Task { await continueWithEmailHandshake() }
            } label: {
                ZStack {
                    if isCheckingAccount {
                        ProgressView()
                            .tint(BookingSelectorTheme.cream)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(OnCutsFont.title3)
                            .foregroundStyle(BookingSelectorTheme.cream)
                    }
                }
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(
                emailEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isCheckingAccount
                    || isSigningIn
            )
            .opacity(
                emailEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isCheckingAccount
                    || isSigningIn
                    ? 0.45
                    : 1
            )
            .accessibilityLabel("Continue")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            Capsule(style: .continuous)
                .strokeBorder(BookingSelectorTheme.cream, lineWidth: 1)
        }
        .contentShape(Capsule(style: .continuous))
    }

    private var passwordHandshakeField: some View {
        HStack(spacing: 10) {
            Group {
                if isPasswordVisible {
                    TextField("Password", text: $passwordEntry)
                } else {
                    SecureField("Password", text: $passwordEntry)
                }
            }
            .font(OnCutsFont.body(weight: .medium))
            .foregroundStyle(BookingSelectorTheme.cream)
            .tint(BookingSelectorTheme.cream)
            .textContentType(.password)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .focused($focusedAuthField, equals: .password)
            .submitLabel(.go)
            .onSubmit {
                Task { await performInlinePasswordLogin() }
            }
            .onAppear {
                // Keep the keyboard up by moving first responder from email → password.
                focusedAuthField = .password
            }
            .onChange(of: isPasswordVisible) { _, _ in
                focusedAuthField = .password
            }
            .disabled(isSigningIn)

            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                    .font(OnCutsFont.body(weight: .medium))
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
            .disabled(isSigningIn)

            Button {
                Task { await performInlinePasswordLogin() }
            } label: {
                ZStack {
                    if isSigningIn {
                        ProgressView()
                            .tint(BookingSelectorTheme.cream)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(OnCutsFont.title3)
                            .foregroundStyle(BookingSelectorTheme.cream)
                    }
                }
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(passwordEntry.isEmpty || isSigningIn)
            .opacity(passwordEntry.isEmpty || isSigningIn ? 0.45 : 1)
            .accessibilityLabel("Sign in")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            Capsule(style: .continuous)
                .strokeBorder(BookingSelectorTheme.cream, lineWidth: 1)
        }
        .contentShape(Capsule(style: .continuous))
    }

    @MainActor
    private func continueWithEmailHandshake() async {
        let trimmed = emailEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else {
            let o = OnCutsAuthUserMessaging.invalidEmailFormatOutcome()
            authOutcomeTitle = o.title
            authOutcomeMessage = o.message
            showAuthOutcomeAlert = true
            return
        }
        isCheckingAccount = true
        defer { isCheckingAccount = false }

        do {
            let exists = try await OnCutsAuthService.checkAccount(
                email: trimmed,
                apiV1BaseTrimmed: apiV1BaseTrimmed
            )
            if exists {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                    didCompleteEmailHandshake = true
                }
                // Transfer first responder immediately so the keyboard stays up for password entry.
                focusedAuthField = .password
                Task { @MainActor in
                    // Second pass after the password field is in the hierarchy.
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    focusedAuthField = .password
                }
            } else if let onContinueWithNewEmail {
                onContinueWithNewEmail(trimmed)
            } else {
                authOutcomeTitle = "Account Not Found"
                authOutcomeMessage = "No \(AppBranding.displayName) account uses this email. Create an account to continue."
                showAuthOutcomeAlert = true
            }
        } catch {
            let o = OnCutsAuthUserMessaging.emailPasswordOutcome(for: error)
            authOutcomeTitle = o.title
            authOutcomeMessage = o.message
            showAuthOutcomeAlert = true
        }
    }

    @MainActor
    private func performInlinePasswordLogin() async {
        let trimmedEmail = emailEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !passwordEntry.isEmpty else { return }
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let verified = try await OnCutsAuthService.loginWithEmailPassword(
                email: trimmedEmail,
                password: passwordEntry,
                apiV1BaseTrimmed: apiV1BaseTrimmed
            )
            sessionManager.login(session: UserSession(onCutsVerified: verified))
            await sessionManager.refreshProfileFromServer()
            onSignedIn()
        } catch {
            let o = OnCutsAuthUserMessaging.emailPasswordOutcome(for: error)
            authOutcomeTitle = o.title
            authOutcomeMessage = o.message
            showAuthOutcomeAlert = true
        }
    }

    // MARK: Create account (legacy — only when email field is hidden)

    private var oauthOrDivider: some View {
        Text("or")
            .font(OnCutsFont.caption(weight: .medium))
            .foregroundStyle(BookingSelectorTheme.cream.opacity(0.62))
            .frame(maxWidth: .infinity)
    }

    private func createAccountLink(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Create Account")
                .font(OnCutsFont.body(weight: .semibold))
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
    /// When set, opens package-driven email sign-up (`IntegratedSignUpFlowRegistry`) with optional handoff email.
    var onRequestEmailSignUp: ((String?) -> Void)?
    /// Unused when the email field is shown (create account is part of the email handshake).
    var showsCreateAccountLink: Bool

    /// Owned by the parent that presents this sheet so `login()` / `AppSessionManager` updates do not reset `@State`.
    @ObservedObject private var appleOAuthFollowUp: AppleOAuthPostSignInCoordinator

    init(
        sessionManager: AppSessionManager,
        appleOAuthFollowUp: AppleOAuthPostSignInCoordinator,
        onFinished: @escaping () -> Void,
        onRequestEmailSignUp: ((String?) -> Void)? = nil,
        showsCreateAccountLink: Bool = false
    ) {
        self.sessionManager = sessionManager
        self._appleOAuthFollowUp = ObservedObject(wrappedValue: appleOAuthFollowUp)
        self.onFinished = onFinished
        self.onRequestEmailSignUp = onRequestEmailSignUp
        self.showsCreateAccountLink = showsCreateAccountLink
    }

    var body: some View {
        NavigationStack {
            OAuthProviderSignInOptionsContent(
                sessionManager: sessionManager,
                appleOAuthFollowUp: appleOAuthFollowUp,
                layout: .sheet,
                showsCreateAccountLink: showsCreateAccountLink,
                onContinueWithNewEmail: { email in
                    dismiss()
                    onRequestEmailSignUp?(email)
                },
                onSignedIn: {
                    onFinished()
                    dismiss()
                }
            )
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
            .onAppear { dismissIfAlreadySignedIn() }
        }
    }

    private func dismissIfAlreadySignedIn() {
        guard sessionManager.isAuthenticated else { return }
        guard !appleOAuthFollowUp.appleBackendExchangeInProgress else { return }
        onFinished()
        dismiss()
    }
}
