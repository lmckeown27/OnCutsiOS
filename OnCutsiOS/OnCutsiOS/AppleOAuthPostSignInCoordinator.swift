//
//  AppleOAuthPostSignInCoordinator.swift
//  OnCuts
//
//  Holds Sign-in-with-Apple exchange state **outside** `OAuthProviderSignInSheet` so it is not wiped when
//  `AppSessionManager` publishes after `login()` and SwiftUI rebuilds the sheet content.
//

import Combine
import Foundation

@MainActor
final class AppleOAuthPostSignInCoordinator: ObservableObject {
    @Published var appleBackendExchangeInProgress = false

    func reset() {
        appleBackendExchangeInProgress = false
    }
}
