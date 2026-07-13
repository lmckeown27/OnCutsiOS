//
//  IntegratedSignUpFlowRegistry.swift
//  OnCuts
//
//  Register sign-up flows from integrated packages (OnCutsModule today; more modules later).
//

import SwiftUI

/// Describes one installable sign-up experience (usually backed by an SPM feature package).
struct IntegratedSignUpFlow: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    private let _makeView: (AppSessionManager, String?, @escaping () -> Void) -> AnyView

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping (AppSessionManager, String?, @escaping () -> Void) -> some View
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        _makeView = { sm, handoff, done in AnyView(content(sm, handoff, done)) }
    }

    func hostView(
        sessionManager: AppSessionManager,
        handoffEmail: String? = nil,
        onFinished: @escaping () -> Void
    ) -> AnyView {
        _makeView(sessionManager, handoffEmail, onFinished)
    }
}

@MainActor
enum IntegratedSignUpFlowRegistry {
    private static var flows: [IntegratedSignUpFlow] = []

    /// Idempotent registration — same `id` is ignored on subsequent calls.
    static func register(_ flow: IntegratedSignUpFlow) {
        if flows.contains(where: { $0.id == flow.id }) { return }
        flows.append(flow)
    }

    static var allFlows: [IntegratedSignUpFlow] { flows }

    static func flow(id: String) -> IntegratedSignUpFlow? {
        flows.first { $0.id == id }
    }

    /// Tests / previews only.
    static func resetForTesting() {
        flows.removeAll()
    }
}
