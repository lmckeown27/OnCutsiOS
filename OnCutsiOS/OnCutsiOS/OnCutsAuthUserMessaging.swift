//
//  OnCutsAuthUserMessaging.swift
//  OnCuts
//
//  Maps provider and API errors to clear titles + messages for alert popups (sign-in / sign-up).
//

import AuthenticationServices
import Foundation

enum OnCutsAuthUserMessaging {

    // MARK: - OAuth (Google)

    static func googleSignInOutcome(for error: Error) -> (title: String, message: String) {
        if let ver = error as? AuthBackendVerificationError {
            switch ver {
            case .serverRejected(let status, let msg):
                if isOAuthAccountNotFound(status: status, message: msg) {
                    return googleAccountNotFoundCreateAccountOutcome()
                }
                if status == 401 {
                    return (
                        "Sign In Failed",
                        msg ?? "Google sign-in was rejected. Try again or use another sign-in method."
                    )
                }
            default:
                break
            }
        }

        return oauthSignInOutcome(for: error)
    }

    /// User dismissed Google sign-in — callers should not show an alert.
    static func isGoogleSignInCancellation(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "com.google.GIDSignIn", ns.code == -5 {
            return true
        }
        if ns.domain == "com.google.GIDSignIn" {
            let lower = error.localizedDescription.lowercased()
            return lower.contains("cancel") || lower.contains("cancelled")
        }
        return false
    }

    static func oauthSignInOutcome(for error: Error) -> (title: String, message: String) {
        let ns = error as NSError
        let lower = error.localizedDescription.lowercased()

        // Google Sign-In (`com.google.GIDSignIn`, e.g. canceled = -5)
        if ns.domain == "com.google.GIDSignIn" {
            if ns.code == -5 {
                return (
                    "Sign In Canceled",
                    "You closed Google sign-in before it finished. Try again when you’re ready."
                )
            }
            return (
                "Google Sign-In",
                humanizeGoogleSignInMessage(error.localizedDescription)
            )
        }

        if lower.contains("cancel") || lower.contains("cancelled") || lower.contains("dismiss") {
            return (
                "Sign In Canceled",
                "The sign-in screen was closed before your account could be connected. You can try again anytime."
            )
        }

        if ns.domain == NSURLErrorDomain {
            return (
                "Connection Problem",
                "Check your internet connection and try again.\n\n\(error.localizedDescription)"
            )
        }

        return (
            "Sign In Couldn’t Complete",
            error.localizedDescription
        )
    }

    /// Sign in with Apple + `AuthBackendVerification` / `ASAuthorizationError`.
    static func appleSignInOutcome(for error: Error) -> (title: String, message: String) {
        if let authErr = error as? ASAuthorizationError, authErr.code == .canceled {
            return (
                "Sign In Canceled",
                "You closed Sign in with Apple before it finished. Try again when you’re ready."
            )
        }

        if let ver = error as? AuthBackendVerificationError {
            switch ver {
            case .serverRejected(let status, let msg):
                if status == 401, isOAuthAccountNotFound(status: status, message: msg) {
                    return (
                        "No Matching Account",
                        "There’s no \(AppBranding.displayName) account for this Apple ID yet. Use Sign Up in the app to create one, then sign in with the same Apple ID."
                    )
                }
                if status == 401 {
                    return ("Sign In Failed", msg ?? "Apple sign-in was rejected. Try again or use another sign-in method.")
                }
            default:
                break
            }
        }

        if let apple = error as? AppleSignInFlowError {
            switch apple {
            case .missingEmail:
                return (
                    "Sign In With Apple",
                    "We couldn’t confirm your account email from Apple on this device. Please try Sign in with Apple again. If it keeps failing, contact support — you should not need to create a separate email password for the same Apple ID."
                )
            case .missingIdentityToken:
                return (
                    "Sign In With Apple",
                    apple.errorDescription ?? "Apple did not return a credential."
                )
            }
        }

        return oauthSignInOutcome(for: error)
    }

    // MARK: - Email / password (OnCuts APIs)

    static func emailPasswordOutcome(for error: Error) -> (title: String, message: String) {
        let ns = error as NSError
        let lower = error.localizedDescription.lowercased()

        if ns.domain == NSURLErrorDomain {
            return (
                "Connection Problem",
                "We couldn’t reach the server. Check your connection and try again.\n\n\(error.localizedDescription)"
            )
        }

        if lower.contains("invalid") && (lower.contains("password") || lower.contains("credential") || lower.contains("unauthorized")) {
            return (
                "Sign In Failed",
                "That email or password doesn’t match our records. Try again, or reset your password if your app supports it."
            )
        }

        return (
            "Sign In Couldn’t Complete",
            error.localizedDescription
        )
    }

    static func invalidEmailFormatOutcome() -> (title: String, message: String) {
        (
            "Check Your Email",
            "Enter a valid email address so we can look up your account."
        )
    }

    // MARK: - Sign up (register / verify)

    static func signUpOutcome(for error: Error) -> (title: String, message: String) {
        let ns = error as NSError
        let lower = error.localizedDescription.lowercased()

        if ns.domain == NSURLErrorDomain {
            return (
                "Connection Problem",
                "We couldn’t reach the server. Check your connection and try again.\n\n\(error.localizedDescription)"
            )
        }

        if lower.contains("terms") {
            return (
                "Terms of Service",
                error.localizedDescription
            )
        }

        if lower.contains("already exists") || lower.contains("already registered") {
            return (
                "Account Already Exists",
                "An account with this email is already registered. Try signing in instead."
            )
        }

        return (
            "Couldn’t Finish Signing Up",
            error.localizedDescription
        )
    }

    /// Titles for validation copy and API messages already stored as plain strings (e.g. in `SignupCoordinator.errorMessage`).
    static func signUpAlertPresentation(message: String) -> (title: String, message: String) {
        let lower = message.lowercased()
        if lower.contains("terms of service") || lower.contains("accept the terms") {
            return ("Terms of Service", message)
        }
        if lower.hasPrefix("enter ") || lower.hasPrefix("missing ") || (lower.contains("password") && lower.contains("match")) {
            return ("Check your information", message)
        }
        if lower.contains("password must") || lower.contains("at least 8") {
            return ("Check your password", message)
        }
        if lower.contains("network") || lower.contains("couldn’t reach") || lower.contains("internet") {
            return (
                "Connection Problem",
                message
            )
        }
        if lower.contains("invalid") || lower.contains("expired") || lower.contains("already exists") {
            return signUpOutcome(for: NSError(domain: "intera.signup", code: 0, userInfo: [NSLocalizedDescriptionKey: message]))
        }
        return ("Couldn’t Finish Signing Up", message)
    }

    // MARK: - Private

    private static func isOAuthAccountNotFound(status: Int, message: String?) -> Bool {
        guard status == 401 else { return false }
        let m = (message ?? "").lowercased()
        return m.contains("not found")
            || m.contains("account_not_found")
            || m.contains("no account")
            || m.contains("no matching account")
    }

    private static func googleAccountNotFoundCreateAccountOutcome() -> (title: String, message: String) {
        (
            "Sign In Couldn’t Complete",
            "There’s no \(AppBranding.displayName) account for this Google account yet. Tap Create Account below to register, then sign in with Google again."
        )
    }

    private static func humanizeGoogleSignInMessage(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("network") {
            return "Check your internet connection and try Google sign-in again.\n\n\(raw)"
        }
        return raw
    }
}
