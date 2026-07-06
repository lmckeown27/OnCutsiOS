//
//  LiquidGlassSignupFlow.swift
//  Intera
//
//  Multi-step signup: email path = name → Terms → contact → password → verify (final); verify logs in and dismisses.
//  Phone path (when `SignupPhoneSignupIntegration.isEnabled`): name → Terms → contact → verify (SMS) → password; then dismiss.
//  uses `/auth/signup/send-phone-code`, `/auth/signup/verify-phone-code`, `/auth/signup/complete-phone`.
//  Terms: inline `InteraTermsOfServiceDocumentScrollView` + agreement on the same screen. Keychain resume may still show a post-verify Terms card when `pendingSession` is set.
//

import CampusCutsModule
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Phone signup feature flag

/// SMS / phone-first signup is **off** until product + backend are ready; the app uses **email-only** account creation.
/// Phone-specific UI and `SignupCoordinator` APIs remain in this file for a later integration — flip to `true` to enable.
enum SignupPhoneSignupIntegration {
    static let isEnabled = false
}

// MARK: - Contact method

enum SignupContactChannel: String, CaseIterable, Sendable {
    case email
    case phone
}

// MARK: - Coordinator

@Observable
@MainActor
final class SignupCoordinator {
    var step: CustomerOnboardingStep = .name

    var email: String = ""
    /// Digits-only entry for the phone path (US 10-digit → normalized to E.164 `+1…`).
    var phoneDigits: String = ""
    /// Set when advancing from the contact step with **Phone** selected (`+1XXXXXXXXXX`).
    var phoneE164: String = ""
    /// After a successful SMS code check; used with `complete-phone`.
    var phoneSignupToken: String?
    var contactChannel: SignupContactChannel = .email

    var password: String = ""
    var confirmPassword: String = ""

    /// Single field driving the six glass digit cells (filter to digits in the view layer).
    var verificationCode: String = ""

    var firstName: String = ""
    var lastName: String = ""

    /// Accepted on the Terms step (step 2) before email/contact; required before register / phone code send.
    var termsAccepted: Bool = false

    /// Host sets this to dismiss the signup UI after email verification or phone signup completes (user is already logged in).
    var onAuthenticatedSignupFinished: (() -> Void)?

    /// Present only while resuming a legacy saved verified session until it is applied to `AppSessionManager`.
    var pendingSession: CampusCutsAuthSession?

    private var didApplyRestoredSessionLogin: Bool = false

    var devVerificationHint: String?
    var isSubmitting: Bool = false
    var errorMessage: String?

    var verificationShakeTrigger: Int = 0
    var verificationHasErrorTint: Bool = false

    private let apiBase: String

    init(apiV1BaseTrimmed: String, handoffEmail: String? = nil) {
        apiBase = apiV1BaseTrimmed
        if let h = handoffEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            email = h
        }
        restoreIfNeeded()
        applyPhoneSignupFeatureFlagIfNeeded()
    }

    /// When phone signup is disabled, keep `contactChannel` on `.email` so no SMS/API paths run.
    func applyPhoneSignupFeatureFlagIfNeeded() {
        guard !SignupPhoneSignupIntegration.isEnabled else { return }
        contactChannel = .email
    }

    func restoreIfNeeded() {
        guard let saved = SignupOnboardingPersistence.loadStep() else { return }
        switch saved {
        case .verification:
            if let em = SignupOnboardingPersistence.loadEmail(), !em.isEmpty {
                // Mid–phone-signup persistence is invalid while phone integration is off — avoid a stuck verification step.
                if !SignupPhoneSignupIntegration.isEnabled, em.hasSuffix("@phone.signup.campuscuts.com") {
                    SignupOnboardingPersistence.clearSignupNavigationState()
                    return
                }
                email = em
                if em.hasSuffix("@phone.signup.campuscuts.com") {
                    contactChannel = .phone
                    let local = String(em.split(separator: "@").first ?? "")
                    if local.allSatisfy(\.isNumber) {
                        phoneE164 = "+\(local)"
                        if local.count == 11, local.hasPrefix("1") {
                            phoneDigits = String(local.dropFirst())
                        } else if local.count == 10 {
                            phoneDigits = local
                        }
                    }
                }
                step = .verification
                verificationCode = ""
                errorMessage = nil
            }
        case .legacyProfile, .terms:
            if let s = try? SignupOnboardingPersistence.loadVerifiedSession() {
                pendingSession = s
                firstName = s.firstName.isEmpty ? "" : s.firstName
                lastName = s.lastName.isEmpty ? "" : s.lastName
                email = s.email
                termsAccepted = false
                step = .terms
                SignupOnboardingPersistence.clearSignupNavigationState()
            }
        default:
            break
        }
    }

    func persistStep() {
        switch step {
        case .verification:
            SignupOnboardingPersistence.save(step: .verification, email: email)
        case .name, .contact, .password, .terms, .legacyProfile:
            break
        }
    }

    /// US 10-digit mobile → E.164 `+1…` (matches web + CampusCuts backend defaults).
    static func normalizedUSPhoneE164(digits: String) -> String? {
        let d = digits.filter(\.isNumber)
        guard d.count == 10 else { return nil }
        return "+1\(d)"
    }

    /// Matches `syntheticEmailFromPhoneE164` in the CampusCuts API.
    static func syntheticEmailFromPhoneE164(_ e164: String) -> String {
        let digits = e164.filter(\.isNumber)
        return "\(digits)@phone.signup.campuscuts.com"
    }

    func advanceFromName() {
        errorMessage = nil
        let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty else {
            errorMessage = "Enter your first name."
            return
        }
        guard !l.isEmpty else {
            errorMessage = "Enter your last name."
            return
        }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
            step = .terms
        }
    }

    func advanceFromTerms() {
        errorMessage = nil
        guard termsAccepted else {
            errorMessage = "Please read and accept the Terms of Service to continue."
            return
        }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
            step = .contact
        }
    }

    func advanceFromContact() {
        errorMessage = nil
        guard contactChannel == .email else { return }
        let em = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !em.isEmpty else {
            errorMessage = "Enter your email."
            return
        }
        guard em.contains("@") else {
            errorMessage = "Enter a valid email address."
            return
        }
        phoneE164 = ""
        phoneSignupToken = nil
        withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
            step = .password
        }
    }

    /// Phone path: validate number, send SMS, go to verification (not password).
    func sendPhoneVerificationAfterContact() async {
        errorMessage = nil
        guard SignupPhoneSignupIntegration.isEnabled, contactChannel == .phone else { return }
        guard let e164 = Self.normalizedUSPhoneE164(digits: phoneDigits) else {
            errorMessage = "Enter a valid 10-digit US mobile number."
            return
        }
        let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !l.isEmpty else {
            errorMessage = "Go back and enter your name."
            return
        }
        guard termsAccepted else {
            errorMessage = "Go back and accept the Terms of Service."
            return
        }
        phoneE164 = e164
        email = Self.syntheticEmailFromPhoneE164(e164)
        phoneSignupToken = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let sent = try await CampusCutsAuthService.sendPhoneSignupCode(
                apiV1BaseTrimmed: apiBase,
                phone: e164,
                firstName: f,
                lastName: l,
                role: "student",
                campusId: nil
            )
            devVerificationHint = sent.devVerificationCode
            verificationCode = ""
            errorMessage = nil
            withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                step = .verification
            }
            SignupOnboardingPersistence.save(step: .verification, email: email)
        } catch {
            errorMessage = error.localizedDescription
            ProductionLogging.recordNonFatal(error, context: ["area": "liquid_signup_send_phone_code"])
        }
    }

    /// Email path: register with password and send verification email.
    func submitPasswordAndSendVerification() async {
        errorMessage = nil
        guard contactChannel == .email else {
            errorMessage = "Use the email signup path for this action."
            return
        }
        let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let em = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !l.isEmpty, !em.isEmpty else {
            errorMessage = "Go back and complete your name and email."
            return
        }
        guard termsAccepted else {
            errorMessage = "Go back and accept the Terms of Service."
            return
        }
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let req = CampusCutsRegisterRequest(
            email: em,
            password: password,
            firstName: f,
            lastName: l,
            role: "student",
            campusId: nil,
            acceptedTerms: true
        )
        do {
            let sent = try await CampusCutsAuthService.sendVerificationCode(apiV1BaseTrimmed: apiBase, request: req)
            email = sent.email
            devVerificationHint = sent.devVerificationCode
            verificationCode = ""
            errorMessage = nil
            withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                step = .verification
            }
            SignupOnboardingPersistence.save(step: .verification, email: email)
        } catch {
            errorMessage = error.localizedDescription
            ProductionLogging.recordNonFatal(error, context: ["area": "liquid_signup_register"])
        }
    }

    /// Resend SMS (phone path) or email code (email path).
    func resendVerificationEmail() async {
        errorMessage = nil
        guard !isSubmitting else { return }
        if SignupPhoneSignupIntegration.isEnabled, contactChannel == .phone {
            let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !f.isEmpty, !l.isEmpty, !phoneE164.isEmpty else {
                errorMessage = "Missing details for resend."
                return
            }
            isSubmitting = true
            defer { isSubmitting = false }
            do {
                let sent = try await CampusCutsAuthService.sendPhoneSignupCode(
                    apiV1BaseTrimmed: apiBase,
                    phone: phoneE164,
                    firstName: f,
                    lastName: l,
                    role: "student",
                    campusId: nil
                )
                devVerificationHint = sent.devVerificationCode
                verificationCode = ""
                #if os(iOS)
                InteraLiquidGlassHaptics.notification(.success)
                #endif
            } catch {
                errorMessage = error.localizedDescription
                ProductionLogging.recordNonFatal(error, context: ["area": "liquid_signup_resend_phone"])
            }
            return
        }
        let em = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !em.isEmpty else {
            errorMessage = "Missing email for resend."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let sent = try await CampusCutsAuthService.resendVerificationCode(email: em, apiV1BaseTrimmed: apiBase)
            email = sent.email
            devVerificationHint = sent.devVerificationCode
            verificationCode = ""
            SignupOnboardingPersistence.save(step: .verification, email: email)
            #if os(iOS)
            InteraLiquidGlassHaptics.notification(.success)
            #endif
        } catch {
            errorMessage = error.localizedDescription
            ProductionLogging.recordNonFatal(error, context: ["area": "liquid_signup_resend_verification"])
        }
    }

    /// Clears disk/keychain signup progress so the user can begin with a new email. Does not call the server.
    func discardSavedSignupProgress() {
        SignupOnboardingPersistence.clearAll()
        step = .name
        verificationCode = ""
        pendingSession = nil
        devVerificationHint = nil
        errorMessage = nil
        verificationHasErrorTint = false
        password = ""
        confirmPassword = ""
        email = ""
        phoneDigits = ""
        phoneE164 = ""
        phoneSignupToken = nil
        contactChannel = .email
        firstName = ""
        lastName = ""
        termsAccepted = false
        didApplyRestoredSessionLogin = false
    }

    func performVerify(sessionManager: AppSessionManager) async {
        if SignupPhoneSignupIntegration.isEnabled, contactChannel == .phone {
            await verifyPhoneCodeThenPassword()
            return
        }
        errorMessage = nil
        verificationHasErrorTint = false
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let em = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, !em.isEmpty else { return }
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var session = try await CampusCutsAuthService.verify(code: code, email: em, apiV1BaseTrimmed: apiBase)
            let localFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let localLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            let mergedFirst = localFirst.isEmpty ? (session.firstName.isEmpty ? "" : session.firstName) : localFirst
            let mergedLast = localLast.isEmpty ? (session.lastName.isEmpty ? "" : session.lastName) : localLast
            firstName = mergedFirst
            lastName = mergedLast
            session = CampusCutsVerifiedSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                userId: session.userId,
                email: session.email,
                firstName: mergedFirst.isEmpty ? session.firstName : mergedFirst,
                lastName: mergedLast.isEmpty ? session.lastName : mergedLast,
                backendRole: session.backendRole
            )
            #if os(iOS)
            InteraLiquidGlassHaptics.notification(.success)
            #endif
            sessionManager.login(session: UserSession(campusCutsVerified: session))
            SignupOnboardingPersistence.clearAll()
            pendingSession = nil
            onAuthenticatedSignupFinished?()
        } catch {
            errorMessage = error.localizedDescription
            verificationShakeTrigger += 1
            verificationHasErrorTint = true
            verificationCode = ""
            #if os(iOS)
            InteraLiquidGlassHaptics.notification(.error)
            #endif
            ProductionLogging.recordNonFatal(error, context: ["area": "liquid_signup_verify"])
        }
    }

    /// Phone path: verify SMS → advance to password (no session yet).
    private func verifyPhoneCodeThenPassword() async {
        guard SignupPhoneSignupIntegration.isEnabled else { return }
        errorMessage = nil
        verificationHasErrorTint = false
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, !phoneE164.isEmpty else { return }
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result = try await CampusCutsAuthService.verifyPhoneSignupCode(
                apiV1BaseTrimmed: apiBase,
                phone: phoneE164,
                code: code
            )
            phoneSignupToken = result.phoneSignupToken
            verificationCode = ""
            errorMessage = nil
            SignupOnboardingPersistence.clearSignupNavigationState()
            #if os(iOS)
            InteraLiquidGlassHaptics.notification(.success)
            #endif
            withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
                step = .password
            }
        } catch {
            errorMessage = error.localizedDescription
            verificationShakeTrigger += 1
            verificationHasErrorTint = true
            verificationCode = ""
            #if os(iOS)
            InteraLiquidGlassHaptics.notification(.error)
            #endif
            ProductionLogging.recordNonFatal(error, context: ["area": "liquid_signup_verify_phone"])
        }
    }

    /// Phone path: password + `complete-phone` → session, then Terms.
    func submitPhonePasswordAndCompleteSignup(sessionManager: AppSessionManager) async {
        errorMessage = nil
        guard SignupPhoneSignupIntegration.isEnabled, contactChannel == .phone else {
            errorMessage = "Use the phone signup path for this action."
            return
        }
        guard let token = phoneSignupToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            errorMessage = "Verification expired. Go back and enter the code from your text again."
            return
        }
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var session = try await CampusCutsAuthService.completePhoneSignup(
                apiV1BaseTrimmed: apiBase,
                phoneSignupToken: token,
                password: password
            )
            let localFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let localLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            let mergedFirst = localFirst.isEmpty ? (session.firstName.isEmpty ? "" : session.firstName) : localFirst
            let mergedLast = localLast.isEmpty ? (session.lastName.isEmpty ? "" : session.lastName) : localLast
            firstName = mergedFirst
            lastName = mergedLast
            session = CampusCutsVerifiedSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                userId: session.userId,
                email: session.email,
                firstName: mergedFirst.isEmpty ? session.firstName : mergedFirst,
                lastName: mergedLast.isEmpty ? session.lastName : mergedLast,
                backendRole: session.backendRole
            )
            #if os(iOS)
            InteraLiquidGlassHaptics.notification(.success)
            #endif
            sessionManager.login(session: UserSession(campusCutsVerified: session))
            phoneSignupToken = nil
            SignupOnboardingPersistence.clearAll()
            pendingSession = nil
            onAuthenticatedSignupFinished?()
        } catch {
            errorMessage = error.localizedDescription
            ProductionLogging.recordNonFatal(error, context: ["area": "liquid_signup_complete_phone"])
        }
    }

    /// Applies a verified session restored from Keychain (legacy Keychain saves) to the session manager.
    func finishRestoredVerifiedUserIfNeeded(sessionManager: AppSessionManager) {
        guard !didApplyRestoredSessionLogin else { return }
        guard step == .terms, let s = pendingSession, !sessionManager.isAuthenticated else { return }
        didApplyRestoredSessionLogin = true
        sessionManager.login(session: UserSession(campusCutsVerified: s))
        pendingSession = nil
        SignupOnboardingPersistence.deleteVerifiedSessionFromKeychain()
    }
}

// MARK: - Root

@available(iOS 17.0, macOS 14.0, *)
struct LiquidGlassSignupFlowView: View {
    let apiV1BaseTrimmed: String
    let sessionManager: AppSessionManager
    let onFinished: () -> Void
    /// Prefills identity email when branching from sign-in.
    let handoffEmail: String?
    /// When non-nil (e.g. login carousel), identity email morphs with the same namespace in `LoginView`.
    let emailMorphNamespace: Namespace.ID?
    /// With `emailMorphNamespace`, set to `true` once the carousel shows the signup panel (geometry handoff).
    let signupPanelIsEmailMorphSource: Bool

    @State private var coordinator: SignupCoordinator
    @Namespace private var signupGlassNS
    @State private var completeOpacity: Double = 1
    @State private var isSignupPasswordVisible = false
    /// Gated by scrolling the inline Terms viewport to the end marker.
    @State private var termsDocumentReachedBottom = false
    @State private var showSignupOutcomeAlert = false
    @State private var signupAlertTitle = ""
    @State private var signupAlertMessage = ""
    /// Drives the UIKit OTP field’s first responder (SwiftUI `TextField` + `.oneTimeCode` often ignores SMS QuickType).
    @State private var otpFieldFocused = false
    /// Recreates the UIKit field when the code is cleared so UIKit state cannot stay out of sync with the model.
    @State private var otpFieldRemountId = 0
    @FocusState private var phoneNumberFieldFocused: Bool

    @Environment(\.dismiss) private var dismiss

    private var otpBinding: Binding<String> {
        Binding(
            get: { coordinator.verificationCode },
            set: { new in
                coordinator.verificationCode = String(new.filter(\.isNumber).prefix(6))
            }
        )
    }

    /// Display `(555) 555-5555` while `coordinator.phoneDigits` stays digits-only (max 10).
    private var phoneDigitsFormattedBinding: Binding<String> {
        Binding(
            get: { Self.formatUSPhoneDisplay(digits: coordinator.phoneDigits) },
            set: { newValue in
                coordinator.phoneDigits = String(newValue.filter(\.isNumber).prefix(10))
            }
        )
    }

    /// Progressive US formatting for a 10-digit national number (stored value is digits only).
    private static func formatUSPhoneDisplay(digits: String) -> String {
        let d = String(digits.filter(\.isNumber).prefix(10))
        guard !d.isEmpty else { return "" }
        if d.count <= 3 {
            return "(" + d
        }
        let areaCode = d.prefix(3)
        if d.count <= 6 {
            return "(\(areaCode)) " + d.dropFirst(3)
        }
        let prefix = d.dropFirst(3).prefix(3)
        let line = d.dropFirst(6)
        return "(\(areaCode)) \(prefix)-\(line)"
    }

    /// Prefer this over `Bindable(coordinator).termsAccepted`, which can fail to write through `@State` + `@Observable`.
    private var termsAcceptedBinding: Binding<Bool> {
        Binding(
            get: { coordinator.termsAccepted },
            set: { coordinator.termsAccepted = $0 }
        )
    }

    /// Keychain resume: verified session not yet applied — show the legacy “Enter Intera” Terms card, not the pre-account Terms step.
    private var isPostVerificationTermsResume: Bool {
        coordinator.pendingSession != nil
    }

    private var navigationTitleForStep: String {
        switch coordinator.step {
        case .name, .contact, .password, .verification:
            return "Create account"
        case .terms, .legacyProfile:
            return isPostVerificationTermsResume ? "Terms of Service" : "Create account"
        }
    }

    private var showsSignupBackButton: Bool {
        switch coordinator.step {
        case .name:
            return false
        case .terms, .legacyProfile:
            return !isPostVerificationTermsResume
        case .contact, .password, .verification:
            return true
        }
    }

    private var showsSignupForwardButton: Bool {
        switch coordinator.step {
        case .name:
            return false
        case .contact, .password, .verification, .terms, .legacyProfile:
            return true
        }
    }

    private var signupStepIndicator: (current: Int, total: Int) {
        let total = 5
        if SignupPhoneSignupIntegration.isEnabled, coordinator.contactChannel == .phone {
            switch coordinator.step {
            case .name: return (1, total)
            case .terms, .legacyProfile: return (2, total)
            case .contact: return (3, total)
            case .verification: return (4, total)
            case .password: return (5, total)
            }
        }
        switch coordinator.step {
        case .name: return (1, total)
        case .terms, .legacyProfile: return (2, total)
        case .contact: return (3, total)
        case .password: return (4, total)
        case .verification: return (5, total)
        }
    }

    init(
        apiV1BaseTrimmed: String,
        sessionManager: AppSessionManager,
        onFinished: @escaping () -> Void,
        handoffEmail: String? = nil,
        emailMorphNamespace: Namespace.ID? = nil,
        signupPanelIsEmailMorphSource: Bool = false
    ) {
        self.apiV1BaseTrimmed = apiV1BaseTrimmed
        self.sessionManager = sessionManager
        self.onFinished = onFinished
        self.handoffEmail = handoffEmail
        self.emailMorphNamespace = emailMorphNamespace
        self.signupPanelIsEmailMorphSource = signupPanelIsEmailMorphSource
        _coordinator = State(
            initialValue: SignupCoordinator(apiV1BaseTrimmed: apiV1BaseTrimmed, handoffEmail: handoffEmail)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    stepHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    Group {
                        switch coordinator.step {
                        case .name:
                            nameCard
                        case .contact:
                            contactCard
                        case .password:
                            passwordCard
                        case .verification:
                            verificationCard
                        case .terms, .legacyProfile:
                            termsCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.86), value: coordinator.step)

                    Color.clear.frame(height: 32)
                }
                .frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .interaNavigationShellBackgroundClear()
            #endif
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(navigationTitleForStep)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // Lava lives on NavigationStack.background so system chrome doesn’t paint grouped grey on top of it.
            .toolbarBackground(.hidden, for: .navigationBar)
            #if os(iOS)
            .modifier(SignupNavigationBarTransparentWhenAvailable())
            #endif
            .toolbar {
                if showsSignupBackButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            goBackStep()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back")
                    }
                }
                if showsSignupForwardButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            performToolbarForward()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .accessibilityLabel(forwardToolbarAccessibilityLabel)
                        .disabled(!isForwardToolbarEnabled)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(InteraFont.subheadline(weight: .semibold))
                            .foregroundStyle(Color.lavaShellCream)
                    }
                }
            }
            .tint(Color.oliveGreen)
        }
        .background {
            InteraShellBackground()
                .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(completeOpacity)
        .onChange(of: coordinator.errorMessage) { _, new in
            guard let new, !new.isEmpty else { return }
            let p = InteraAuthUserMessaging.signUpAlertPresentation(message: new)
            signupAlertTitle = p.title
            signupAlertMessage = p.message
            showSignupOutcomeAlert = true
        }
        .alert(signupAlertTitle, isPresented: $showSignupOutcomeAlert) {
            Button("OK", role: .cancel) {
                coordinator.errorMessage = nil
            }
        } message: {
            Text(signupAlertMessage)
        }
        .onAppear {
            coordinator.onAuthenticatedSignupFinished = { dismissAndFinishSignupChrome() }
            coordinator.finishRestoredVerifiedUserIfNeeded(sessionManager: sessionManager)
            // Restore runs in `SignupCoordinator.init` only — avoid re-applying persistence here, which can
            // fight in-memory step updates right after a successful verify.
            if coordinator.step == .verification {
                coordinator.errorMessage = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    otpFieldFocused = true
                }
            }
        }
        .onChange(of: coordinator.step) { _, newStep in
            if newStep == .contact {
                coordinator.applyPhoneSignupFeatureFlagIfNeeded()
            }
            if newStep == .verification {
                coordinator.errorMessage = nil
                coordinator.verificationHasErrorTint = false
            }
            if newStep == .terms {
                termsDocumentReachedBottom = coordinator.termsAccepted
            }
            if newStep != .contact {
                phoneNumberFieldFocused = false
            }
            if newStep != .verification {
                otpFieldFocused = false
            }
        }
        .onChange(of: coordinator.termsAccepted) { _, accepted in
            if !accepted {
                termsDocumentReachedBottom = false
            }
        }
    }

    // MARK: - View Components

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(signupStepIndicator.current) of \(signupStepIndicator.total)")
                .font(InteraFont.subheadline(weight: .semibold))
                .foregroundStyle(Color.lavaShellCream.opacity(0.92))
                .tracking(0.3)

            if !headerTitle.isEmpty {
                Text(headerTitle)
                    .font(InteraLiquidGlassTypography.title(28, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            if coordinator.step == .contact,
               coordinator.contactChannel == .email,
               let ns = emailMorphNamespace,
               !coordinator.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(coordinator.email)
                    .font(InteraFont.subheadline(weight: .semibold))
                    .foregroundStyle(.secondary)
                    .matchedGeometryEffect(
                        id: "authIdentityEmail",
                        in: ns,
                        properties: .position,
                        anchor: .leading,
                        isSource: signupPanelIsEmailMorphSource
                    )
                Text(headerSubtitle)
                    .font(InteraFont.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                Text(headerSubtitle)
                    .font(InteraFont.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerTitle: String {
        switch coordinator.step {
        case .name:
            return "What’s your name?"
        case .contact:
            return "How should we reach you?"
        case .password:
            return "Create a password"
        case .verification:
            return SignupPhoneSignupIntegration.isEnabled && coordinator.contactChannel == .phone
                ? "Check your phone"
                : "Check your inbox"
        case .terms, .legacyProfile:
            return isPostVerificationTermsResume ? "Welcome" : "Terms of Service"
        }
    }

    private var headerSubtitle: String {
        switch coordinator.step {
        case .name:
            return "We’ll use this on your profile and bookings."
        case .contact:
            return SignupPhoneSignupIntegration.isEnabled && coordinator.contactChannel == .phone
                ? "We’ll text a 6-digit code to verify it’s you."
                : "We’ll send a 6-digit code to verify it’s you."
        case .password:
            return SignupPhoneSignupIntegration.isEnabled && coordinator.contactChannel == .phone
                ? "Use at least 8 characters. This is the last step before your account is created."
                : "Use at least 8 characters. Next you’ll enter the verification code we email you."
        case .verification:
            return SignupPhoneSignupIntegration.isEnabled && coordinator.contactChannel == .phone
                ? "Enter the code we texted you. Next you’ll create a password."
                : "Enter the 6-digit code we sent. This is the last step — verifying activates your account."
        case .terms, .legacyProfile:
            if isPostVerificationTermsResume {
                return "Read and accept the Terms of Service to continue into \(AppBranding.displayName)."
            }
            return "Use the preview on this page. Scroll to the end, agree, then continue with your email."
        }
    }

    // MARK: Name

    private var nameCard: some View {
        liquidCard {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    glassTextField(title: "First name", content: {
                        TextField("", text: Bindable(coordinator).firstName, prompt: glassTextFieldPlaceholder("First name"))
                            .textContentType(.givenName)
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                    })
                    glassTextField(title: "Last name", content: {
                        TextField("", text: Bindable(coordinator).lastName, prompt: glassTextFieldPlaceholder("Last name"))
                            .textContentType(.familyName)
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                    })
                }

                Button {
                    coordinator.advanceFromName()
                } label: {
                    Text("Continue")
                        .font(InteraFont.body(weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.oliveGreen)
            }
        }
        .matchedGeometryEffect(id: "liquidSignupCard", in: signupGlassNS)
    }

    // MARK: Contact

    private var contactCard: some View {
        liquidCard {
            VStack(spacing: 16) {
                if SignupPhoneSignupIntegration.isEnabled {
                    Picker("Contact method", selection: Bindable(coordinator).contactChannel) {
                        Text("Email").tag(SignupContactChannel.email)
                        Text("Phone").tag(SignupContactChannel.phone)
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.oliveGreen)
                }

                // Phone UI lives in the `else` below when `SignupPhoneSignupIntegration.isEnabled` is true.
                if !SignupPhoneSignupIntegration.isEnabled || coordinator.contactChannel == .email {
                    glassTextField(title: "Email", content: {
                        TextField("", text: Bindable(coordinator).email, prompt: glassTextFieldPlaceholder("you@email.com"))
                            .textContentType(.emailAddress)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                    })
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        glassTextField(title: "Mobile number", content: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "circle.grid.3x3.fill")
                                    .font(InteraFont.title3(weight: .semibold))
                                    .foregroundStyleInteraShellIconSecondary()
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField(
                                        "",
                                        text: phoneDigitsFormattedBinding,
                                        prompt: Text("(555) 555-5555").foregroundStyle(.tertiary.opacity(0.75))
                                    )
                                    .textContentType(.telephoneNumber)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #elseif os(macOS)
                                    .keyboardType(.asciiCapableNumberPad)
                                    #endif
                                    .font(InteraFont.title2.monospacedDigit().weight(.semibold))
                                    .focused($phoneNumberFieldFocused)
                                    .accessibilityLabel("Mobile number")
                                    .accessibilityHint("Ten digit US phone number. Use number keys only.")
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    #endif
                                    .autocorrectionDisabled()
                                    .minimumScaleFactor(0.65)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    HStack {
                                        Text("Digits only · area + number")
                                            .font(InteraFont.caption2(weight: .medium))
                                            .foregroundStyle(.tertiary)
                                        Spacer(minLength: 0)
                                        Text("\(min(coordinator.phoneDigits.count, 10))/10")
                                            .font(InteraFont.caption2.monospacedDigit().weight(.semibold))
                                            .foregroundStyle(
                                                coordinator.phoneDigits.count == 10
                                                    ? Color.oliveGreen.opacity(0.95)
                                                    : Color.secondary.opacity(0.85)
                                            )
                                            .accessibilityLabel("\(coordinator.phoneDigits.count) of 10 digits")
                                    }
                                }
                            }
                        })
                        Text("We’ll text a one-time code to this US mobile number (message and data rates may apply).")
                            .font(InteraFont.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    if SignupPhoneSignupIntegration.isEnabled, coordinator.contactChannel == .phone {
                        Task { await coordinator.sendPhoneVerificationAfterContact() }
                    } else {
                        coordinator.advanceFromContact()
                    }
                } label: {
                    Text(
                        SignupPhoneSignupIntegration.isEnabled && coordinator.contactChannel == .phone
                            ? (coordinator.isSubmitting ? "Sending code…" : "Continue")
                            : "Continue"
                    )
                        .font(InteraFont.body(weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.oliveGreen)
                .disabled(SignupPhoneSignupIntegration.isEnabled && coordinator.contactChannel == .phone && coordinator.isSubmitting)
            }
        }
        .matchedGeometryEffect(id: "liquidSignupCard", in: signupGlassNS)
    }

    // MARK: Password

    private var passwordCard: some View {
        liquidCard {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    glassTextField(title: "Password", content: {
                        signupPasswordVisibilityRow(
                            text: Bindable(coordinator).password,
                            placeholder: "At least 8 characters"
                        )
                    })
                    glassTextField(title: "Confirm password", content: {
                        signupPasswordVisibilityRow(
                            text: Bindable(coordinator).confirmPassword,
                            placeholder: "Re-enter password"
                        )
                    })
                }

                Button {
                    Task {
                        if SignupPhoneSignupIntegration.isEnabled, coordinator.contactChannel == .phone {
                            await coordinator.submitPhonePasswordAndCompleteSignup(sessionManager: sessionManager)
                        } else {
                            await coordinator.submitPasswordAndSendVerification()
                        }
                    }
                } label: {
                    Text(passwordPrimaryButtonTitle)
                        .font(InteraFont.body(weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.oliveGreen)
                .disabled(coordinator.isSubmitting)
            }
        }
        .matchedGeometryEffect(id: "liquidSignupCard", in: signupGlassNS)
    }

    // MARK: Verification

    private var passwordPrimaryButtonTitle: String {
        if coordinator.isSubmitting {
            return SignupPhoneSignupIntegration.isEnabled && coordinator.contactChannel == .phone
                ? "Creating account…"
                : "Sending code…"
        }
        return "Continue"
    }

    private var verificationDestinationLabel: String {
        let em = coordinator.email
        if em.hasSuffix("@phone.signup.campuscuts.com"), let digitsPart = em.split(separator: "@").first {
            let s = String(digitsPart)
            guard s.count >= 4 else { return em }
            return "•••• ••• " + String(s.suffix(4))
        }
        return em
    }

    private var verificationCard: some View {
        liquidCard {
            VStack(spacing: 18) {
                Text(verificationDestinationLabel)
                    .font(InteraFont.subheadline(weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let hint = coordinator.devVerificationHint, !hint.isEmpty {
                    Text("Dev code: \(hint)")
                        .font(InteraFont.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Digit boxes are the visual; the TextField is a full-size overlay on top so SMS AutoFill
                // sees a normal field (tiny/hidden fields often don’t receive Security Code suggestions).
                ZStack {
                    HStack(spacing: 8) {
                        ForEach(0 ..< 6, id: \.self) { i in
                            let ch = digitAt(i, in: coordinator.verificationCode)
                            let focused = otpFieldFocused && coordinator.verificationCode.count == i
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .frame(height: 52)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            focused
                                                ? Color.oliveGreen.opacity(0.85)
                                                : (coordinator.verificationHasErrorTint ? Color.red.opacity(0.55) : Color.white.opacity(0.2)),
                                            lineWidth: focused ? 2 : 0.75
                                        )
                                }
                                .shadow(color: focused ? Color.oliveGreen.opacity(0.35) : .clear, radius: 8, y: 0)
                                .overlay {
                                    Text(ch.map({ String($0) }) ?? " ")
                                        .font(InteraFont.title2(weight: .semibold))
                                        .monospacedDigit()
                                }
                                .allowsHitTesting(false)
                        }
                    }
                    .modifier(ShakeEffect(animatableData: CGFloat(coordinator.verificationShakeTrigger)))

                    #if os(iOS)
                    SignupOTPTextField(text: otpBinding, isFocused: $otpFieldFocused)
                        .id("otp-\(otpFieldRemountId)")
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    #else
                    TextField("", text: otpBinding)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .autocorrectionDisabled()
                        .font(InteraFont.body.monospacedDigit())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.clear)
                        .tint(.clear)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    #endif
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
                .onTapGesture { otpFieldFocused = true }
                .onChange(of: coordinator.verificationCode) { oldVal, newVal in
                    #if os(iOS)
                    if newVal.isEmpty, oldVal.count > 0 {
                        otpFieldRemountId += 1
                        DispatchQueue.main.async {
                            otpFieldFocused = true
                        }
                    }
                    if !newVal.isEmpty {
                        InteraLiquidGlassHaptics.selectionChanged()
                    }
                    #endif
                    if newVal.count == 6 {
                        Task { await coordinator.performVerify(sessionManager: sessionManager) }
                    }
                }

                Button {
                    Task { await coordinator.resendVerificationEmail() }
                } label: {
                    Text(coordinator.isSubmitting ? "Sending…" : "Didn’t get a code? Send again")
                        .font(InteraFont.caption(weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyleOliveGreen(opacity: 0.95)
                .disabled(coordinator.isSubmitting)

                if coordinator.isSubmitting {
                    ProgressView()
                        .tint(Color.oliveGreen)
                }

                if SignupOnboardingPersistence.hasPersistedProgress {
                    Button(
                        SignupPhoneSignupIntegration.isEnabled && coordinator.contactChannel == .phone
                            ? "Start over with a different phone number"
                            : "Start over with a different email"
                    ) {
                        coordinator.discardSavedSignupProgress()
                    }
                    .font(InteraFont.caption(weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                }
            }
        }
        .matchedGeometryEffect(id: "liquidSignupCard", in: signupGlassNS)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                otpFieldFocused = true
            }
        }
    }

    private func digitAt(_ index: Int, in code: String) -> Character? {
        guard index < code.count else { return nil }
        return code[code.index(code.startIndex, offsetBy: index)]
    }

    // MARK: Terms

    private var termsCard: some View {
        Group {
            if isPostVerificationTermsResume {
                postVerificationTermsResumeCard
            } else {
                earlySignupTermsCard
            }
        }
    }

    private var earlySignupTermsCard: some View {
        liquidCard {
            VStack(spacing: 20) {
                Text("Read before you continue")
                    .font(InteraLiquidGlassTypography.title(24, weight: .bold))
                    .multilineTextAlignment(.center)

                liquidTermsAgreementEntry

                Button {
                    coordinator.advanceFromTerms()
                } label: {
                    Text("Continue")
                        .font(InteraFont.body(weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.oliveGreen)
                .disabled(!coordinator.termsAccepted)
            }
            .frame(maxWidth: .infinity)
        }
        .matchedGeometryEffect(id: "liquidSignupCard", in: signupGlassNS)
    }

    private var postVerificationTermsResumeCard: some View {
        liquidCard {
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(InteraFont.system(size: 48))
                    .foregroundStyleInteraShellIcon()
                Text("You’re verified")
                    .font(InteraLiquidGlassTypography.title(24, weight: .bold))
                Text("One last step: accept the Terms of Service to enter \(AppBranding.displayName).")
                    .font(InteraFont.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                liquidTermsAgreementEntry

                Button {
                    enterInteraFromComplete()
                } label: {
                    Text("Enter \(AppBranding.displayName)")
                        .font(InteraFont.body(weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.oliveGreen)
                .disabled(!coordinator.termsAccepted)
            }
            .frame(maxWidth: .infinity)
        }
        .matchedGeometryEffect(id: "liquidSignupCard", in: signupGlassNS)
    }

    // MARK: Chrome

    private var liquidTermsAgreementEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: coordinator.termsAccepted ? "checkmark.circle.fill" : "doc.text.fill")
                    .font(InteraFont.title3)
                    .foregroundStyle(coordinator.termsAccepted ? Color.oliveGreen : .secondary)
                    .interaOliveGreenTextOutline(when: coordinator.termsAccepted)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Terms of Service")
                        .font(InteraFont.caption(weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        coordinator.termsAccepted
                            ? "Accepted — scroll below if you want to read again."
                            : "Scroll the preview to the bottom, then tap I agree."
                    )
                    .font(InteraFont.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            InteraTermsOfServiceDocumentScrollView(reachedEnd: $termsDocumentReachedBottom)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                }
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }

            if !coordinator.termsAccepted {
                Button {
                    termsAcceptedBinding.wrappedValue = true
                } label: {
                    Text("I agree to the Terms of Service")
                        .font(InteraFont.subheadline(weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(termsDocumentReachedBottom ? Color.oliveGreen : Color.secondary)
                        .interaOliveGreenTextOutline(when: termsDocumentReachedBottom)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    termsDocumentReachedBottom
                                        ? Color.lavaShellCream
                                        : Color.lavaShellCream.opacity(0.22)
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(termsDocumentReachedBottom ? 0.35 : 0.12), lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!termsDocumentReachedBottom)
            }
        }
    }

    private func glassTextFieldPlaceholder(_ string: String) -> Text {
        Text(string).foregroundStyle(.secondary)
    }

    private func signupPasswordVisibilityRow(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Group {
                if isSignupPasswordVisible {
                    TextField("", text: text, prompt: glassTextFieldPlaceholder(placeholder))
                } else {
                    SecureField("", text: text, prompt: glassTextFieldPlaceholder(placeholder))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textContentType(.newPassword)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()

            Button {
                isSignupPasswordVisible.toggle()
            } label: {
                Image(systemName: isSignupPasswordVisible ? "eye.slash.fill" : "eye.fill")
                    .font(InteraFont.body(weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSignupPasswordVisible ? "Hide passwords" : "Show passwords")
        }
    }

    private func liquidCard<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
    }

    private func glassTextField<Content: View>(title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(InteraFont.caption(weight: .semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                }
        }
    }

    private func goBackStep() {
        withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
            switch coordinator.step {
            case .contact:
                coordinator.step = .terms
            case .password:
                if SignupPhoneSignupIntegration.isEnabled, coordinator.contactChannel == .phone, coordinator.phoneSignupToken != nil {
                    coordinator.phoneSignupToken = nil
                    coordinator.verificationCode = ""
                    coordinator.step = .verification
                } else {
                    coordinator.step = .contact
                }
            case .verification:
                if SignupPhoneSignupIntegration.isEnabled, coordinator.contactChannel == .phone {
                    coordinator.step = .contact
                } else {
                    coordinator.step = .password
                }
            case .terms, .legacyProfile:
                if !isPostVerificationTermsResume {
                    coordinator.termsAccepted = false
                    coordinator.step = .name
                }
            case .name:
                break
            }
        }
        coordinator.errorMessage = nil
        coordinator.verificationHasErrorTint = false
    }

    private var isForwardToolbarEnabled: Bool {
        switch coordinator.step {
        case .name:
            return false
        case .contact:
            if coordinator.contactChannel == .email {
                let em = coordinator.email.trimmingCharacters(in: .whitespacesAndNewlines)
                return !em.isEmpty && em.contains("@")
            }
            return SignupCoordinator.normalizedUSPhoneE164(digits: coordinator.phoneDigits) != nil
                && !coordinator.isSubmitting
        case .password:
            return coordinator.password.count >= 8
                && coordinator.password == coordinator.confirmPassword
                && !coordinator.isSubmitting
                && (coordinator.contactChannel == .email
                    || (SignupPhoneSignupIntegration.isEnabled && coordinator.phoneSignupToken != nil))
        case .verification:
            let code = coordinator.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
            return code.count == 6 && !coordinator.isSubmitting
        case .terms, .legacyProfile:
            return coordinator.termsAccepted
        }
    }

    private var forwardToolbarAccessibilityLabel: String {
        switch coordinator.step {
        case .name:
            return "Continue"
        case .contact:
            return "Continue"
        case .password:
            return SignupPhoneSignupIntegration.isEnabled && coordinator.contactChannel == .phone
                ? "Create password"
                : "Send verification code"
        case .verification:
            return "Verify code"
        case .terms, .legacyProfile:
            return isPostVerificationTermsResume ? "Enter \(AppBranding.displayName)" : "Continue"
        }
    }

    private func performToolbarForward() {
        switch coordinator.step {
        case .name:
            coordinator.advanceFromName()
        case .contact:
            if SignupPhoneSignupIntegration.isEnabled, coordinator.contactChannel == .phone {
                Task { await coordinator.sendPhoneVerificationAfterContact() }
            } else {
                coordinator.advanceFromContact()
            }
        case .password:
            Task {
                if SignupPhoneSignupIntegration.isEnabled, coordinator.contactChannel == .phone {
                    await coordinator.submitPhonePasswordAndCompleteSignup(sessionManager: sessionManager)
                } else {
                    await coordinator.submitPasswordAndSendVerification()
                }
            }
        case .verification:
            Task { await coordinator.performVerify(sessionManager: sessionManager) }
        case .terms, .legacyProfile:
            if isPostVerificationTermsResume {
                enterInteraFromComplete()
            } else {
                coordinator.advanceFromTerms()
            }
        }
    }

    private func dismissAndFinishSignupChrome() {
        withAnimation(.easeOut(duration: 0.35)) {
            completeOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            onFinished()
        }
    }

    private func enterInteraFromComplete() {
        dismissAndFinishSignupChrome()
    }
}

// MARK: - Navigation chrome (avoid grouped grey over mesh)

#if os(iOS)
private struct SignupNavigationBarTransparentWhenAvailable: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        } else {
            content
        }
    }
}
#endif

#if os(iOS)
// MARK: - SMS / email OTP (UIKit)

/// `UITextField` with `textContentType = .oneTimeCode` so the system applies the SMS security code when the user taps the QuickType bar.
/// SwiftUI’s `TextField` frequently does not accept that insertion even when the suggestion appears.
private struct SignupOTPTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.textContentType = .oneTimeCode
        tf.keyboardType = .numberPad
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.textAlignment = .center
        tf.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        tf.tintColor = .clear
        tf.textColor = .clear
        tf.isSecureTextEntry = false
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textDidChangeNotification(_:)),
            name: UITextField.textDidChangeNotification,
            object: tf
        )
        return tf
    }

    static func dismantleUIView(_ uiView: UITextField, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.textBinding = $text
        context.coordinator.isFocusedBinding = $isFocused

        if isFocused {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }

        // Critical: do not push a stale SwiftUI `text` into the UITextField while it is first responder.
        // SMS / “Fill Code” updates UIKit first; the binding often updates one frame later — assigning here
        // would clear the field (`text` still "") and make autofill appear broken.
        if uiView.isFirstResponder {
            return
        }
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var textBinding = Binding.constant("")
        var isFocusedBinding = Binding.constant(false)

        @objc func textDidChangeNotification(_ note: Notification) {
            guard let tf = note.object as? UITextField else { return }
            editingChanged(tf)
        }

        @objc func editingChanged(_ sender: UITextField) {
            applyDigits(from: sender)
        }

        private func applyDigits(from sender: UITextField) {
            let raw = sender.text ?? ""
            let digits = String(raw.filter(\.isNumber).prefix(6))
            if sender.text != digits {
                sender.text = digits
            }
            guard textBinding.wrappedValue != digits else { return }
            textBinding.wrappedValue = digits
        }

        /// Keeps the SwiftUI binding in sync *before* the run loop, so `updateUIView` never sees an empty `text`
        /// while UIKit already has the security code (avoids wiping autofill in the parent).
        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = textField.text ?? ""
            guard let textRange = Range(range, in: current) else { return true }
            let proposed = current.replacingCharacters(in: textRange, with: string)
            let digits = String(proposed.filter(\.isNumber).prefix(6))
            if textBinding.wrappedValue != digits {
                textBinding.wrappedValue = digits
            }
            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !isFocusedBinding.wrappedValue {
                isFocusedBinding.wrappedValue = true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if isFocusedBinding.wrappedValue {
                isFocusedBinding.wrappedValue = false
            }
        }
    }
}
#endif

// MARK: - Shake

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = sin(animatableData * .pi * 4) * 6
        return ProjectionTransform(CGAffineTransform(translationX: t, y: 0))
    }
}

#if DEBUG
@available(iOS 17.0, macOS 14.0, *)
#Preview("Liquid signup") {
    LiquidGlassSignupFlowView(
        apiV1BaseTrimmed: "https://oncuts.com/api/v1",
        sessionManager: AppSessionManager(),
        onFinished: {}
    )
}
#endif
