//
//  ServiceSelectionScreen.swift
//  Intera
//
//  Service selection screen - user picks Beauty or Haircuts
//

import SwiftUI

struct ServiceSelectionScreen: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    
    @State private var showProfileMenu = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .space4) {
                    // Service Cards
                    ForEach(Service.allServices) { service in
                        ServiceCard(service: service) {
                            navigateToService(service)
                        }
                    }
                }
                .padding(.horizontal, .space4)
                .padding(.vertical, .space6)
            }
            .background(Color.neutral50.ignoresSafeArea())
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Only show profile if logged in
                if sessionManager.isAuthenticated {
                    profileToolbarItem
                }
            }
            .sheet(isPresented: $showProfileMenu) {
                ProfileMenuSheet(
                    sessionManager: sessionManager,
                    coordinator: coordinator
                )
            }
        }
    }
    
    // MARK: - Toolbar
    
    private var profileToolbarItem: some ToolbarContent {
        ToolbarItem(placement: {
            #if os(iOS)
            return .topBarTrailing
            #else
            return .automatic
            #endif
        }()) {
            Button {
                showProfileMenu = true
            } label: {
                AvatarView(
                    imageUrl: sessionManager.currentSession?.profileImageURL,
                    name: sessionManager.currentSession?.displayName ?? "User",
                    size: 32
                )
            }
        }
    }
    
    // MARK: - Actions
    
    private func navigateToService(_ service: Service) {
        coordinator.selectService(service)
    }
}

// MARK: - Service Card

struct ServiceCard: View {
    let service: Service
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: .space4) {
                // Icon
                ZStack {
                    Circle()
                        .fill(service.color.opacity(0.15))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: service.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(service.color)
                }
                
                // Info
                VStack(alignment: .leading, spacing: .space1) {
                    Text(service.name)
                        .font(.headlineMedium)
                        .foregroundStyle(Color.neutral800)
                    
                    Text(service.description)
                        .font(.bodySmall)
                        .foregroundStyle(Color.neutral500)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Arrow
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(Color.neutral400)
            }
            .padding(.space5)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: .radiusXL))
            .cardShadow()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Service Model

struct Service: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let icon: String
    var colorHex: String
    
    var color: Color {
        Color(hex: colorHex)
    }
    
    static let haircuts = Service(
        id: "haircuts",
        name: "Haircuts",
        description: "Professional haircuts, fades, and styling",
        icon: "scissors",
        colorHex: "5A7268" // Brand olive green
    )
    
    static let beauty = Service(
        id: "beauty",
        name: "Beauty",
        description: "Makeup, nails, skincare, and more",
        icon: "sparkles",
        colorHex: "C891C8" // Purple/pink
    )
    
    static let allServices: [Service] = [haircuts, beauty]
}

// MARK: - Preview

#Preview {
    let manager = AppSessionManager()
    manager.mockLogin(as: .student)
    
    return ServiceSelectionScreen(
        sessionManager: manager,
        coordinator: MainCoordinator(sessionManager: manager)
    )
}
