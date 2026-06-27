//
//  CampusCutsSessionSync.swift
//  Intera
//

import Foundation

@MainActor
enum CampusCutsSessionSync {
    static var appSessionManager: AppSessionManager? {
        get { CampusCutsIntegration.sessionManager }
        set { CampusCutsIntegration.sessionManager = newValue }
    }
}
