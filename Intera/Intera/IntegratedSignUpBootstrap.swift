//
//  IntegratedSignUpBootstrap.swift
//  Intera
//
//  Wires default package-provided sign-up flows. Call additional `register` hooks when new SPMs ship.
//

import CampusCutsModule
import SwiftUI

@MainActor
enum IntegratedSignUpBootstrap {
    private static var didInstall = false

    /// Run once early in app startup (e.g. `RootView.onAppear`).
    ///
    /// To add another SPM later, call `IntegratedSignUpFlowRegistry.register(IntegratedSignUpFlow(...))`
    /// from the same method (or from that package’s shell adapter) with a unique `id`.
    static func installDefaultFlowsIfNeeded() {
        guard !didInstall else { return }
        didInstall = true

        IntegratedSignUpFlowRegistry.register(
            IntegratedSignUpFlow(
                id: "campuscuts.email",
                title: AppBranding.displayName,
                subtitle: "Liquid Glass onboarding — verify email + profile."
            ) { sessionManager, onFinished in
                if #available(iOS 17.0, macOS 14.0, *) {
                    LiquidGlassSignupFlowView(
                        apiV1BaseTrimmed: AppConfiguration.messagingAPIRootTrimmed,
                        sessionManager: sessionManager,
                        onFinished: onFinished
                    )
                } else {
                    CampusCutsSignUpView(apiV1BaseTrimmed: AppConfiguration.messagingAPIRootTrimmed) { verified in
                        sessionManager.login(session: UserSession(campusCutsVerified: verified))
                        onFinished()
                    }
                }
            }
        )
    }
}
