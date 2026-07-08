//
//  UserSessionProtocol.swift
//  Intera
//
//  Created by Liam McKeown on 3/8/26.
//
//  Protocol bridge for external feature modules
//

import Foundation
import SwiftUI

/// Protocol that external modules expect for user session data
/// This is the "Contract" that allows modules to work with the Shell
public protocol UserSessionProtocol: Sendable {
    var userId: String { get }
    var accessToken: String { get }
    var email: String { get }
    var displayName: String { get }
    var userRole: String { get }
    var stripeCustomerId: String? { get }
    var profileImageURL: String? { get }
    var isValid: Bool { get }
    
    /// Refresh the access token when it's about to expire
    func refreshAccessToken() async throws -> String
}

/// Extension to make UserSession conform to the protocol
extension UserSession: UserSessionProtocol {
    
    public var accessToken: String {
        return token
    }
    
    public var userRole: String {
        return role.rawValue
    }
    
    /// Refresh implementation - delegates to AppSessionManager
    /// Note: In practice, you'll call this through the SessionManager
    public func refreshAccessToken() async throws -> String {
        guard let manager = OnCutsSessionSync.appSessionManager else {
            throw SessionError.refreshFailed
        }
        try await manager.refreshSession()
        guard let token = manager.currentSession?.token else {
            throw SessionError.refreshFailed
        }
        return token
    }
}

// MARK: - Module Builder Support

/// Helper to create feature module views with proper session injection
@MainActor
public protocol FeatureModuleBuilder {
    associatedtype ContentView: View
    
    /// Build the module's root view with a session
    static func build(with session: any UserSessionProtocol) -> ContentView
}

// MARK: - Session Refresh Protocol

/// Protocol for the session manager to handle refresh
public protocol SessionRefreshable {
    func refreshSession() async throws
}

extension AppSessionManager: SessionRefreshable {
    // Already implemented in the main class
}
