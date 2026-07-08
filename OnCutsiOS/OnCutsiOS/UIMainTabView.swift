//
//  MainTabView.swift
//  Intera
//
//  Created by Liam McKeown on 3/8/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Uses standard `TabView` / `NavigationStack`; tab bars and navigation chrome adopt system
/// Liquid Glass when the app is built with the iOS 26 SDK (no extra modifiers required).
struct MainTabView: View {
    @Bindable var coordinator: MainCoordinator
    let sessionManager: AppSessionManager

    @EnvironmentObject private var chatViewModel: ChatViewModel
    
    var body: some View {
        TabView(selection: Binding(
            get: { coordinator.selectedTab },
            set: { coordinator.navigateToTab($0) }
        )) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: $coordinator.navigationPath) {
                    viewForTab(tab)
                        .navigationDestination(for: AppRoute.self) { route in
                            destinationView(for: route)
                        }
                        #if os(iOS)
                        .interaNavigationShellBackgroundClear()
                        #endif
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.iconName)
                }
                .tag(tab)
                .badge(tab == .messages ? chatViewModel.unreadMessageCount : 0)
            }
        }
        .sheet(item: $coordinator.presentedSheet) { sheet in
            sheetView(for: sheet)
        }
        .onReceive(NotificationCenter.default.publisher(for: .interaOpenMessagingConversation)) { _ in
            coordinator.navigateToTab(.messages)
        }
    }
    
    // MARK: - View Builders
    
    @ViewBuilder
    private func viewForTab(_ tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(
                sessionManager: sessionManager,
                coordinator: coordinator
            )
            
        case .marketplace:
            MarketplaceView(
                coordinator: coordinator,
                featureProvider: coordinator.createFeatureProvider()
            )
            
        case .bookings:
            BookingsView(
                coordinator: coordinator,
                featureProvider: coordinator.createFeatureProvider()
            )
            
        case .messages:
            MessagesView(
                coordinator: coordinator,
                featureProvider: coordinator.createFeatureProvider()
            )
            
        case .profile:
            ProfileView(
                sessionManager: sessionManager,
                coordinator: coordinator
            )
        }
    }
    
    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .barberProfile(let id):
            PlaceholderDetailView(title: "Barber Profile", id: id)
            
        case .bookingDetail(let id):
            PlaceholderDetailView(title: "Booking Detail", id: id)
            
        case .productDetail(let id):
            PlaceholderDetailView(title: "Product Detail", id: id)
            
        case .chat(let id):
            PlaceholderDetailView(title: "Chat", id: id)
        }
    }
    
    @ViewBuilder
    private func sheetView(for sheet: SheetDestination) -> some View {
        NavigationStack {
            switch sheet {
            case .settings:
                SettingsView(coordinator: coordinator)
            case .editProfile:
                EditProfileView(sessionManager: sessionManager, coordinator: coordinator)
            case .createBooking:
                CreateBookingView(coordinator: coordinator)
            case .payment:
                PaymentView(coordinator: coordinator)
            }
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Welcome header
                welcomeHeader
                
                // Quick actions
                quickActionsSection
                
                // Recent activity
                recentActivitySection
            }
            .padding()
        }
        .navigationTitle("Home")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    coordinator.presentSheet(.settings)
                } label: {
                    Image(systemName: "gear")
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button {
                    coordinator.presentSheet(.settings)
                } label: {
                    Image(systemName: "gear")
                }
            }
            #endif
        }
    }
    
    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome back,")
                .font(InteraFont.title3)
                .foregroundStyle(.secondary)
            
            Text(sessionManager.currentSession?.displayName ?? "User")
                .font(InteraFont.system(size: 32, weight: .bold))
            
            if let role = sessionManager.currentSession?.role {
                Text(role.displayName)
                    .font(InteraFont.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .foregroundStyle(.blue)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(InteraFont.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                QuickActionCard(
                    title: "Book Now",
                    icon: "calendar.badge.plus",
                    color: .blue
                ) {
                    coordinator.presentSheet(.createBooking)
                }
                
                QuickActionCard(
                    title: "Marketplace",
                    icon: "cart",
                    color: .green
                ) {
                    coordinator.navigateToTab(.marketplace)
                }
                
                QuickActionCard(
                    title: "Messages",
                    icon: "message",
                    color: .purple
                ) {
                    coordinator.navigateToTab(.messages)
                }
                
                QuickActionCard(
                    title: "Profile",
                    icon: "person",
                    color: .orange
                ) {
                    coordinator.navigateToTab(.profile)
                }
            }
        }
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(InteraFont.headline)
            
            VStack(spacing: 12) {
                ActivityRow(
                    title: "Booking confirmed",
                    subtitle: "Tomorrow at 2:00 PM",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                ActivityRow(
                    title: "New message from Jordan",
                    subtitle: "5 minutes ago",
                    icon: "message.fill",
                    color: .blue
                )
                
                ActivityRow(
                    title: "Payment processed",
                    subtitle: "Yesterday",
                    icon: "dollarsign.circle.fill",
                    color: .purple
                )
            }
        }
    }
}

// MARK: - Supporting Views

struct QuickActionCard: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(InteraFont.system(size: 32))
                    .foregroundStyle(color)
                
                Text(title)
                    .font(InteraFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                #if canImport(UIKit)
                Color(uiColor: .systemBackground)
                #else
                Color(nsColor: .windowBackgroundColor)
                #endif
            }
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        }
    }
}

struct ActivityRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(InteraFont.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(InteraFont.subheadline)
                    .fontWeight(.medium)
                
                Text(subtitle)
                    .font(InteraFont.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background {
            #if canImport(UIKit)
            Color(uiColor: .systemBackground)
            #else
            Color(nsColor: .windowBackgroundColor)
            #endif
        }
        .cornerRadius(12)
    }
}

#Preview("Main Tab View") {
    let sessionManager = AppSessionManager()
    sessionManager.mockLogin()
    
    let coordinator = MainCoordinator(sessionManager: sessionManager)
    
    return MainTabView(
        coordinator: coordinator,
        sessionManager: sessionManager
    )
    .environmentObject(ChatViewModel())
}
