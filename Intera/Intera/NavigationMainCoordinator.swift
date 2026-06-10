//
//  MainCoordinator.swift
//  Intera
//
//  Created by Liam McKeown on 3/8/26.
//

import SwiftUI
import Observation

/// The "Traffic Controller" - Manages navigation flow based on authentication state
@Observable
@MainActor
final class MainCoordinator {
    
    // MARK: - Properties
    
    private let sessionManager: AppSessionManager
    private let environment: AppEnvironment
    
    /// Current navigation path for deep linking
    var navigationPath = NavigationPath()
    
    /// Selected tab in the main interface
    var selectedTab: AppTab = .home
    
    /// Sheet presentation state
    var presentedSheet: SheetDestination?
    
    /// Selected service (Beauty or Haircuts)
    var selectedService: Service?
    
    // MARK: - Initialization
    
    init(
        sessionManager: AppSessionManager,
        environment: AppEnvironment = .development
    ) {
        self.sessionManager = sessionManager
        self.environment = environment
    }
    
    // MARK: - Navigation Methods
    
    /// Switch to a specific tab
    func navigateToTab(_ tab: AppTab) {
        withAnimation(.none) {
            selectedTab = tab
        }
    }
    
    /// Present a sheet
    func presentSheet(_ sheet: SheetDestination) {
        presentedSheet = sheet
    }
    
    /// Dismiss the current sheet
    func dismissSheet() {
        presentedSheet = nil
    }
    
    /// Navigate to a specific route
    func navigate(to route: AppRoute) {
        navigationPath.append(route)
    }
    
    /// Pop to root
    func popToRoot() {
        navigationPath = NavigationPath()
    }
    
    /// Handle deep link
    func handleDeepLink(_ url: URL) {
        // TODO: Implement deep link parsing
        // Example: campuscuts://booking/123
        print("Handling deep link: \(url)")
    }
    
    // MARK: - Service Selection
    
    /// Select a service (Beauty or Haircuts)
    func selectService(_ service: Service) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = .none
        
        withTransaction(transaction) {
            selectedService = service
        }
        print("Selected service: \(service.name)")
    }
    
    /// Clear service selection and go back
    func clearServiceSelection() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = .none
        
        withTransaction(transaction) {
            selectedService = nil
        }
    }
    
    // MARK: - External Module Navigation
    
    /// Navigate to the CampusCuts module
    /// When you add the CampusCuts package, uncomment and use this:
    /*
    func showCampusCutsModule() {
        guard let session = sessionManager.currentSession else { return }
        
        // This will be called when CampusCutsModuleBuilder is available
        // let moduleView = CampusCutsModuleBuilder.build(with: session)
        // navigationPath.append(moduleView)
        
        // For now, navigate to marketplace tab
        navigateToTab(.marketplace)
    }
    */
    
    /// Navigate to a specific booking (deep link support)
    func showBooking(id: String) {
        navigate(to: .bookingDetail(id))
    }
    
    /// Navigate to a specific barber profile
    func showBarberProfile(id: String) {
        navigate(to: .barberProfile(id))
    }
    
    // MARK: - Feature Providers
    
    /// Create a feature provider with the current session
    func createFeatureProvider() -> FeatureProvider? {
        guard let session = sessionManager.currentSession else {
            return nil
        }
        
        return DefaultFeatureProvider(
            session: session,
            sessionManager: sessionManager,
            environment: environment
        )
    }
}

// MARK: - Navigation Types

/// Main tabs in the app
enum AppTab: Int, CaseIterable, Identifiable {
    case home
    case marketplace
    case bookings
    case messages
    case profile
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .marketplace: return "Marketplace"
        case .bookings: return "Bookings"
        case .messages: return "Messages"
        case .profile: return "Profile"
        }
    }
    
    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .marketplace: return "cart.fill"
        case .bookings: return "calendar"
        case .messages: return "message.fill"
        case .profile: return "person.fill"
        }
    }
}

/// Deep navigation routes
enum AppRoute: Hashable {
    case barberProfile(String)
    case bookingDetail(String)
    case productDetail(String)
    case chat(String)
}

/// Sheet destinations
enum SheetDestination: Identifiable {
    case settings
    case editProfile
    case createBooking
    case payment
    
    var id: String {
        switch self {
        case .settings: return "settings"
        case .editProfile: return "editProfile"
        case .createBooking: return "createBooking"
        case .payment: return "payment"
        }
    }
}
