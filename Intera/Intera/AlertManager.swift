//
//  AlertManager.swift
//  Intera
//
//  Global toast messages for network and auth failures (paired with `GlassErrorToastOverlay`).
//

import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@Observable
@MainActor
final class AlertManager {
    /// Shared instance for app-wide presentation from view models and services.
    static let shared = AlertManager()

    private(set) var toastMessage: String?
    /// When true, `GlassErrorToastOverlay` uses a `systemRed` glow (validation / errors).
    private(set) var toastUsesErrorGlow: Bool = false
    private var dismissTask: Task<Void, Never>?

    func present(_ message: String, duration: Duration = .seconds(4)) {
        dismissTask?.cancel()
        toastUsesErrorGlow = false
        toastMessage = message
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            toastMessage = nil
            toastUsesErrorGlow = false
        }
    }

    /// Glass toast at the bottom with red glow (e.g. review-step validation).
    func presentErrorToast(_ message: String, duration: Duration = .seconds(4)) {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
        dismissTask?.cancel()
        toastUsesErrorGlow = true
        toastMessage = message
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            toastMessage = nil
            toastUsesErrorGlow = false
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        toastMessage = nil
        toastUsesErrorGlow = false
    }

    /// Maps common transport errors to copy that mentions campus Wi‑Fi where appropriate.
    func presentUserFriendlyMessage(for error: Error) {
        if InteraRefreshCancellation.isBenignCancellation(error) { return }
        let message = Self.friendlyMessage(for: error)
        present(message)
    }

    private static func friendlyMessage(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut:
                return "Connection timed out. If you’re on campus, try turning Wi‑Fi off and on, or switch networks."
            case NSURLErrorNotConnectedToInternet:
                return "You appear to be offline. Check your connection and try again."
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return "Couldn’t reach the server. Check your connection or VPN."
            case NSURLErrorNetworkConnectionLost:
                return "The network dropped. Please try again."
            case NSURLErrorCancelled:
                return "Request was cancelled."
            default:
                break
            }
        }
        if error is DecodingError || error is HTTPJSONBodyValidation.Error {
            return "We couldn’t read the server response. Please try again later."
        }
        return error.localizedDescription.isEmpty
            ? "Something went wrong. Please try again."
            : error.localizedDescription
    }
}
