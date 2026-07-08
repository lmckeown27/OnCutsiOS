//
//  UserSession+OnCutsSignUp.swift
//  OnCuts
//
//  Maps `OnCutsModule` email verification session into the shell `UserSession`.
//

import OnCutsModule
import Foundation

extension UserSession {
    init(onCutsVerified s: OnCutsVerifiedSession) {
        let role: UserRole
        switch s.backendRole.uppercased() {
        case "BARBER":
            role = .barber
        case "ADMIN":
            role = .admin
        default:
            role = .student
        }
        let display = "\(s.firstName) \(s.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            userId: s.userId,
            token: s.accessToken,
            email: s.email,
            displayName: display.isEmpty ? s.email : display,
            role: role,
            stripeCustomerId: nil,
            profileImageURL: nil,
            expiresAt: UserSession.preferredAccessExpiration(accessToken: s.accessToken, refreshToken: s.refreshToken),
            refreshToken: s.refreshToken,
            signInProvider: .emailPassword
        )
    }
}
