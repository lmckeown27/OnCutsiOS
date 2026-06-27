//
//  AvilaPlatformsModuleBuilder.swift
//  AvilaPlatformsModule
//
//  Public entry point for the Shell app to instantiate this module.
//

import SwiftUI

/// Factory class for building the AvilaPlatforms module views
public struct AvilaPlatformsModuleBuilder {

    @MainActor
    public static func build(with session: UserSessionProtocol, client: AvilaPlatformsClient) -> some View {
        let apiService = AvilaPlatformsAPIService(session: session, environment: client.environment)
        let viewModel = AvilaPlatformsHomeViewModel(session: session, apiService: apiService)
        return AvilaPlatformsHomeView(viewModel: viewModel, liveDataSafetyMode: client.isProduction)
    }

    @MainActor
    public static func buildBarberDashboard(with session: UserSessionProtocol, client: AvilaPlatformsClient) -> some View {
        let apiService = AvilaPlatformsAPIService(session: session, environment: client.environment)
        let viewModel = BarberDashboardViewModel(session: session, apiService: apiService, liveDataSafetyMode: client.isProduction)
        return BarberDashboardView(viewModel: viewModel, liveDataSafetyMode: client.isProduction)
    }

    @MainActor
    public static func buildConsumerView(with session: UserSessionProtocol, client: AvilaPlatformsClient) -> some View {
        let apiService = AvilaPlatformsAPIService(session: session, environment: client.environment)
        let viewModel = ConsumerViewModel(session: session, apiService: apiService, liveDataSafetyMode: client.isProduction)
        return ConsumerHomeView(viewModel: viewModel, liveDataSafetyMode: client.isProduction)
    }

    @MainActor
    public static func buildRoleBasedView(with session: UserSessionProtocol, client: AvilaPlatformsClient) -> some View {
        switch session.userRole {
        case "BARBER", "CAMPUS_MANAGER", "ADMIN":
            return AnyView(buildBarberDashboard(with: session, client: client))
        default:
            return AnyView(buildConsumerView(with: session, client: client))
        }
    }

    // MARK: - Legacy convenience (no production safety / default client)

    @MainActor
    public static func build(with session: UserSessionProtocol) -> some View {
        build(with: session, client: AvilaPlatformsClient(session: session))
    }

    @MainActor
    public static func buildBarberDashboard(with session: UserSessionProtocol) -> some View {
        buildBarberDashboard(with: session, client: AvilaPlatformsClient(session: session))
    }

    @MainActor
    public static func buildConsumerView(with session: UserSessionProtocol) -> some View {
        buildConsumerView(with: session, client: AvilaPlatformsClient(session: session))
    }

    @MainActor
    public static func buildRoleBasedView(with session: UserSessionProtocol) -> some View {
        buildRoleBasedView(with: session, client: AvilaPlatformsClient(session: session))
    }
}
