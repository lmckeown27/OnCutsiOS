//
//  OnCutsSessionSync.swift
//  OnCuts
//

import Foundation

@MainActor
enum OnCutsSessionSync {
    static var appSessionManager: AppSessionManager? {
        get { OnCutsIntegration.sessionManager }
        set { OnCutsIntegration.sessionManager = newValue }
    }
}
