//
//  InteraApp.swift
//  Intera
//
//  Created by Liam McKeown on 3/8/26.
//

import SwiftUI
import SwiftData
#if os(iOS) || os(visionOS)
import Core
import StripePaymentSheet
#endif
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif
#if os(macOS) && !targetEnvironment(macCatalyst)
import FirebaseCore
#endif

@main
struct InteraApp: App {
    // MARK: - Core Dependencies

    #if canImport(UIKit) && !os(watchOS)
    @UIApplicationDelegateAdaptor(InteraAppDelegate.self) private var appDelegate
    #endif
    
    /// Global session manager (the "Brain")
    @State private var sessionManager = AppSessionManager()
    
    /// Global coordinator (the "Traffic Controller")
    @State private var coordinator: MainCoordinator
    
    // MARK: - SwiftData Container (for local persistence)
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    // MARK: - Initialization
    
    init() {
        let sessionManager = AppSessionManager()
        _sessionManager = State(wrappedValue: sessionManager)
        _coordinator = State(wrappedValue: MainCoordinator(
            sessionManager: sessionManager,
            environment: .development // Change to .production for release
        ))
        #if os(macOS) && !targetEnvironment(macCatalyst)
        FirebaseApp.configure()
        GoogleSignInAppSupport.configure()
        #endif
        #if os(iOS) || os(visionOS)
        StripeService.applyPublishableKeyAlignedWithAPIHost(apiRootTrimmed: AppConfiguration.messagingAPIRootTrimmed)
        #endif
        InteraFont.installGlobalAppearanceIfNeeded()
    }

    // MARK: - App Scene
    
    var body: some Scene {
        WindowGroup {
            RootView(
                sessionManager: sessionManager,
                coordinator: coordinator
            )
            // Google Sign-In OAuth redirect (must run before other deep links).
            .onOpenURL { url in
                if GoogleSignInAppSupport.handleURL(url) { return }
                #if os(iOS) || os(visionOS)
                if StripeAPI.handleURLCallback(with: url) { return }
                #endif
                coordinator.handleDeepLink(url)
            }
            .overlay {
                GlassErrorToastOverlay()
            }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .defaultSize(width: 393, height: 852) // iPhone 16 Pro dimensions
        .windowResizability(.contentSize)
        #endif
    }
}
// MARK: - App Configuration

extension InteraApp {
    /// Configure for production vs development
    static func configure(environment: AppEnvironment) {
        // Setup logging, analytics, crash reporting, etc.
        print("🚀 Intera starting in \(environment.rawValue) mode")
        
        #if DEBUG
        print("📱 Debug mode enabled")
        #endif
    }
}

