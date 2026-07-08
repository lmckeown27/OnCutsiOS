//
//  AppleNativeSignInPresenter.swift
//  Intera
//
//  Presents Sign in with Apple via `ASAuthorizationController` only (system Face ID / passcode UI).
//  Name and email must come only from Authentication Services + server — no post-authorization manual fields.
//

import AuthenticationServices
import Combine
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if os(iOS) || os(visionOS)
/// `ASAuthorizationController` can invoke the completion path more than once; only forward the first to SwiftUI.
final class AppleAuthorizationCallbackOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false

    func consume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if consumed { return false }
        consumed = true
        return true
    }
}

@available(iOS 17.0, visionOS 1.0, *)
final class AppleNativeSignInPresenter: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var completion: ((Result<ASAuthorization, Error>) -> Void)?
    private var activeController: ASAuthorizationController?
    /// Prevents overlapping `performRequests()` while a controller is active.
    private var didCompleteWithAppleSuccess = false
    private var isPerformingRequest = false

    /// Call before each user-initiated Sign in with Apple so a failed backend exchange can retry Face ID.
    func resetForNewUserInitiatedSignIn() {
        didCompleteWithAppleSuccess = false
    }

    func performSignIn(request: ASAuthorizationAppleIDRequest, completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        guard !didCompleteWithAppleSuccess else { return }
        guard !isPerformingRequest else { return }
        guard activeController == nil else { return }
        isPerformingRequest = true
        self.completion = completion
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        activeController = controller
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        activeController = nil
        isPerformingRequest = false
        guard let completion else { return }
        self.completion = nil
        didCompleteWithAppleSuccess = true
        completion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        activeController = nil
        isPerformingRequest = false
        guard let completion else { return }
        self.completion = nil
        completion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let ordered = scenes.filter { $0.activationState == .foregroundActive } + scenes
        for scene in ordered {
            if let w = scene.windows.first(where: \.isKeyWindow) { return w }
        }
        let any = scenes.flatMap(\.windows)
        if let w = any.first { return w }
        preconditionFailure("No UIWindow for Sign in with Apple presentation anchor.")
    }
}

@available(iOS 17.0, visionOS 1.0, *)
@MainActor
final class AppleNativeSignInPresenterBox: ObservableObject {
    let presenter = AppleNativeSignInPresenter()
}
#endif
