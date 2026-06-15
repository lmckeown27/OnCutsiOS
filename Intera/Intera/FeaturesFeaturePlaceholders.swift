//
//  FeaturePlaceholders.swift
//  Intera
//
//  Created by Liam McKeown on 3/8/26.
//

import SwiftUI

// MARK: - These are placeholders where your external GitHub repos will be imported

// MARK: - Marketplace Feature

struct MarketplaceView: View {
    let coordinator: MainCoordinator
    let featureProvider: FeatureProvider?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cart.fill")
                .font(InteraFont.system(size: 60))
                .foregroundStyle(.green)
            
            Text("Marketplace Module")
                .font(InteraFont.title)
                .fontWeight(.bold)
            
            if let provider = featureProvider {
                VStack(spacing: 8) {
                    Text("✅ Session Injected")
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)
                    
                    Text("User: \(provider.session.displayName)")
                        .font(InteraFont.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Token: \(provider.session.token.prefix(20))...")
                        .font(InteraFont.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            
            Text("This will be replaced with:")
                .font(InteraFont.subheadline)
                .foregroundStyle(.secondary)
            
            Text("import MarketplaceModule")
                .font(InteraFont.system(.caption, design: .monospaced))
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                }
        }
        .padding()
        .navigationTitle("Marketplace")
    }
}

// MARK: - Bookings Feature

struct BookingsView: View {
    let coordinator: MainCoordinator
    let featureProvider: FeatureProvider?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar")
                .font(InteraFont.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Bookings Module")
                .font(InteraFont.title)
                .fontWeight(.bold)
            
            if let provider = featureProvider {
                VStack(spacing: 8) {
                    Text("✅ Session Injected")
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)
                    
                    Text("User ID: \(provider.session.userId)")
                        .font(InteraFont.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            
            Button {
                coordinator.presentSheet(.createBooking)
            } label: {
                Label("Create Booking", systemImage: "plus.circle.fill")
                    .font(InteraFont.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
        .padding()
        .navigationTitle("My Bookings")
    }
}

// MARK: - Messages Feature

struct MessagesView: View {
    let coordinator: MainCoordinator
    let featureProvider: FeatureProvider?

    @EnvironmentObject private var chatViewModel: ChatViewModel

    var body: some View {
        Group {
            if let provider = featureProvider {
                ConversationListView(sessionManager: provider.sessionManager, coordinator: coordinator)
            } else {
                ContentUnavailableView("Sign in required", systemImage: "message.badge", description: Text("Sign in to use messages."))
            }
        }
    }
}

// MARK: - Profile Feature

/// Single profile surface for the Intera shell: **`UserProfileView`** in `UserProfileView.swift`.
/// There is no second copy in this target; CampusCuts’ standalone `StudentProfileView` / `BarberProfileView`
/// live under `CampusCutsPackage/ios-app/` and are not part of the Intera app target.
struct ProfileView: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator

    var body: some View {
        UserProfileView(sessionManager: sessionManager, coordinator: coordinator)
    }
}

// MARK: - Detail Views

struct PlaceholderDetailView: View {
    let title: String
    let id: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(InteraFont.system(size: 50))
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(InteraFont.title2)
                .fontWeight(.bold)
            
            Text("ID: \(id)")
                .font(InteraFont.caption)
                .foregroundStyle(.secondary)
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                }
        }
        .navigationTitle(title)
    }
}

// MARK: - Sheet Views

struct SettingsView: View {
    let coordinator: MainCoordinator
    
    var body: some View {
        List {
            Section("Preferences") {
                Toggle("Notifications", isOn: .constant(true))
                Toggle("Dark Mode", isOn: .constant(false))
            }
            
            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build", value: "100")
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    coordinator.dismissSheet()
                }
            }
        }
    }
}

/// Same profile experience as the Profile tab / profile menu — use **`UserProfileView`** (gear opens the glass edit flow).
struct EditProfileView: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator

    var body: some View {
        UserProfileView(sessionManager: sessionManager, coordinator: coordinator)
            .navigationTitle("Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        coordinator.dismissSheet()
                    }
                }
            }
    }
}

struct CreateBookingView: View {
    let coordinator: MainCoordinator
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Booking")
                .font(InteraFont.title)
                .fontWeight(.bold)
            
            Text("Booking creation form will go here")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("New Booking")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    coordinator.dismissSheet()
                }
            }
        }
    }
}

struct PaymentView: View {
    let coordinator: MainCoordinator
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard.fill")
                .font(InteraFont.system(size: 60))
                .foregroundStyle(.green)
            
            Text("Payment")
                .font(InteraFont.title)
                .fontWeight(.bold)
            
            Text("Stripe integration will go here")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Payment")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    coordinator.dismissSheet()
                }
            }
        }
    }
}

#Preview("Marketplace") {
    NavigationStack {
        MarketplaceView(
            coordinator: MainCoordinator(sessionManager: AppSessionManager()),
            featureProvider: nil
        )
    }
}

#Preview("Profile") {
    let manager = AppSessionManager()
    manager.mockLogin()
    
    return NavigationStack {
        ProfileView(
            sessionManager: manager,
            coordinator: MainCoordinator(sessionManager: manager)
        )
    }
}
