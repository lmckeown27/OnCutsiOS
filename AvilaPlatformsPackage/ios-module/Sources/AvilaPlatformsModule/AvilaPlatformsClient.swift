//
//  AvilaPlatformsClient.swift
//  AvilaPlatformsModule
//
//  Host-facing configuration for environment, production safety mode, and module entry.
//

import SwiftUI

/// Shared configuration for the AvilaPlatforms feature module.
public final class AvilaPlatformsClient: @unchecked Sendable {
    public let environment: AvilaPlatformsEnvironment
    /// When `true`, the shell should show a live-data banner and avoid real financial actions while debugging UI.
    public let isProduction: Bool
    public let session: UserSessionProtocol

    public init(session: UserSessionProtocol, environment: AvilaPlatformsEnvironment = .production, isProduction: Bool = false) {
        self.session = session
        self.environment = environment
        self.isProduction = isProduction
    }

    @MainActor
    public func makeHomeView() -> some View {
        AvilaPlatformsModuleBuilder.build(with: session, client: self)
    }

    @MainActor
    public func makeBarberDashboard() -> some View {
        AvilaPlatformsModuleBuilder.buildBarberDashboard(with: session, client: self)
    }

    @MainActor
    public func makeConsumerView() -> some View {
        AvilaPlatformsModuleBuilder.buildConsumerView(with: session, client: self)
    }

    @MainActor
    public func makeRoleBasedView() -> some View {
        AvilaPlatformsModuleBuilder.buildRoleBasedView(with: session, client: self)
    }
}
