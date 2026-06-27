//
//  FeatureProvider.swift
//  Intera
//
//  Created by Liam McKeown on 3/8/26.
//

import Foundation

/// Protocol that defines how the Shell injects dependencies into Feature Modules
/// Each external Swift Package (Feature Module) should expect this protocol
public protocol FeatureProvider {
    /// Provides the current authenticated session
    var session: UserSession { get }
    
    /// Provides access to the session manager for logout/refresh operations
    var sessionManager: AppSessionManager { get }
    
    /// Base URL for your AWS backend API
    var apiBaseURL: URL { get }
    
    /// Environment configuration
    var environment: AppEnvironment { get }
}

/// App environment configuration
public enum AppEnvironment: String, Sendable {
    case development
    case staging
    case production
    
    public var apiBaseURL: URL {
        switch self {
        case .development:
            return URL(string: "https://dev-api.campuscuts.com")!
        case .staging:
            return URL(string: "https://staging-api.campuscuts.com")!
        case .production:
            return URL(string: "https://avilaplatforms.com/api/v1")!
        }
    }
    
    public var isProduction: Bool {
        self == .production
    }
}

// MARK: - Concrete Implementation

/// Default implementation of FeatureProvider used by the Shell
final class DefaultFeatureProvider: FeatureProvider {
    let session: UserSession
    let sessionManager: AppSessionManager
    let environment: AppEnvironment
    
    var apiBaseURL: URL {
        AppConfiguration.apiBaseURL
    }
    
    init(
        session: UserSession,
        sessionManager: AppSessionManager,
        environment: AppEnvironment = .production
    ) {
        self.session = session
        self.sessionManager = sessionManager
        self.environment = environment
    }
}

// MARK: - Feature Module Base Protocol

/// Protocol that all feature modules should conform to
/// This ensures consistency across your repositories
public protocol FeatureModule {
    associatedtype RootView: View
    
    /// Initialize the feature with dependencies from the Shell
    init(provider: FeatureProvider)
    
    /// The root view of this feature module
    var rootView: RootView { get }
}

import SwiftUI

/// Example of how a feature module would be structured
/// Your external repos (Marketplace, Booking, etc.) should follow this pattern
struct ExampleFeatureModule: FeatureModule {
    let provider: FeatureProvider
    
    init(provider: FeatureProvider) {
        self.provider = provider
    }
    
    var rootView: some View {
        Text("Feature Module with user: \(provider.session.displayName)")
    }
}
