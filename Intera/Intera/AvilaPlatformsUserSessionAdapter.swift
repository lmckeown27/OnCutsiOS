//
//  AvilaPlatformsUserSessionAdapter.swift
//  Intera
//
//  Bridges `AppSessionManager` + `UserSession` to `AvilaPlatformsModule.UserSessionProtocol`
//  without colliding with the shell's own `UserSessionProtocol`.
//

import Foundation
import AvilaPlatformsModule

extension UserRole {
    /// Role strings expected by the AvilaPlatforms API module.
    var avilaPlatformsRoleCode: String {
        switch self {
        case .student: return "CONSUMER"
        case .barber: return "BARBER"
        case .admin: return "ADMIN"
        }
    }
}

@MainActor
final class AvilaPlatformsUserSessionAdapter: AvilaPlatformsModule.UserSessionProtocol {
    private weak var manager: AppSessionManager?

    init(manager: AppSessionManager) {
        self.manager = manager
    }

    var accessToken: String { manager?.currentSession?.token ?? "" }
    var userId: String { manager?.currentSession?.userId ?? "" }
    var userEmail: String { manager?.currentSession?.email ?? "" }
    var userName: String { manager?.currentSession?.displayName ?? "" }
    var userRole: String { manager?.currentSession?.role.avilaPlatformsRoleCode ?? "CONSUMER" }
    var refreshToken: String? { manager?.currentSession?.refreshToken }

    func refreshAccessToken() async throws -> String {
        guard let manager else {
            throw SessionError.noActiveSession
        }
        try await manager.refreshSession()
        guard let token = manager.currentSession?.token else {
            throw SessionError.refreshFailed
        }
        return token
    }

    func requestLogout() {
        manager?.logout()
    }
}
