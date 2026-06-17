//
//  EmailPasswordSignInView.swift
//  Intera
//
//  CampusCuts email handshake + password sign-in for use inside the sign-in sheet stack.
//  UI aligned with `PhoneNumberSignInPlaceholderView` (intro copy, field chrome, olive buttons).
//

import CampusCutsModule
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct EmailPasswordSignInView: View {
    let sessionManager: AppSessionManager
    let apiV1BaseTrimmed: String
    let onSignedIn: () -> Void
    /// When the email is not registered — parent typically opens Create account.
    let onRequestSignUp: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isLoading = false
    @State private var isCheckingAccount = false
    @State private var showAuthOutcomeAlert = false
    @State private var authOutcomeTitle = ""
    @State private var authOutcomeMessage = ""
    @State private var didCompleteEmailHandshake = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if didCompleteEmailHandshake {
                    Text("Enter your password to sign in.")
                        .font(InteraFont.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Group {
                            if isPasswordVisible {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
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
                                .font(InteraFont.body.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 28, minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                    }
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    }

                    signInActionButton(
                        title: "Sign in with email",
                        isBusy: isLoading,
                        isDisabled: email.isEmpty || password.isEmpty || isLoading
                    ) {
                        Task { await performLogin() }
                    }
                } else {
                    Text("Enter your email address. We’ll check if you already have an account.")
                        .font(InteraFont.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        }

                    signInActionButton(
                        title: "Continue",
                        isBusy: isCheckingAccount,
                        isDisabled: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCheckingAccount
                    ) {
                        Task { await handshakeCheckAccount() }
                    }
                }
            }
            .padding(24)
        }
        .alert(authOutcomeTitle, isPresented: $showAuthOutcomeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authOutcomeMessage)
        }
    }

    /// Matches `PhoneNumberSignInPlaceholderView` primary action (bordered prominent + olive).
    private func signInActionButton(
        title: String,
        isBusy: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(InteraFont.body.weight(.semibold))
                    .opacity(isBusy ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.oliveGreen)
        .disabled(isDisabled)
    }

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
            let exists = try await CampusCutsAuthService.checkAccount(email: trimmed, apiV1BaseTrimmed: apiV1BaseTrimmed)
            if exists {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                    didCompleteEmailHandshake = true
                }
            } else {
                onRequestSignUp()
            }
        } catch {
            let o = InteraAuthUserMessaging.emailPasswordOutcome(for: error)
            authOutcomeTitle = o.title
            authOutcomeMessage = o.message
            showAuthOutcomeAlert = true
        }
    }

    private func performLogin() async {
        isLoading = true
        defer { isLoading = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let verified = try await CampusCutsAuthService.loginWithEmailPassword(
                email: trimmedEmail,
                password: password,
                apiV1BaseTrimmed: apiV1BaseTrimmed
            )
            sessionManager.login(session: UserSession(campusCutsVerified: verified))
            await sessionManager.refreshProfileFromServer()
            onSignedIn()
        } catch {
            let o = InteraAuthUserMessaging.emailPasswordOutcome(for: error)
            authOutcomeTitle = o.title
            authOutcomeMessage = o.message
            showAuthOutcomeAlert = true
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct ManualEmailSignInSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sessionManager: AppSessionManager
    let onFinished: () -> Void
    let onRequestEmailSignUp: () -> Void

    var body: some View {
        NavigationStack {
            EmailPasswordSignInView(
                sessionManager: sessionManager,
                apiV1BaseTrimmed: AppConfiguration.messagingAPIRootTrimmed,
                onSignedIn: {
                    onFinished()
                    dismiss()
                },
                onRequestSignUp: {
                    onFinished()
                    onRequestEmailSignUp()
                }
            )
            .navigationTitle("Manual Sign-In")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
