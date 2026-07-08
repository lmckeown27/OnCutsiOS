//
//  FeatureModuleTemplate.swift
//  
//  Template for creating external feature modules
//  Copy this into your new Swift Package repository
//

import SwiftUI

// MARK: - Step 1: Define your module's public interface

/// This is what you'll export from your Swift Package
public struct YourFeatureModule {
    
    // MARK: - Properties
    
    let provider: FeatureProvider
    
    // MARK: - Initialization
    
    public init(provider: FeatureProvider) {
        self.provider = provider
    }
    
    // MARK: - Public Interface
    
    /// The root view of your module
    public func createRootView() -> some View {
        YourFeatureRootView(
            session: provider.session,
            apiClient: createAPIClient()
        )
    }
    
    // MARK: - Private Helpers
    
    private func createAPIClient() -> YourAPIClient {
        YourAPIClient(
            baseURL: provider.apiBaseURL,
            token: provider.session.token
        )
    }
}

// MARK: - Step 2: Create your feature's root view

struct YourFeatureRootView: View {
    let session: UserSession
    let apiClient: YourAPIClient
    
    @State private var viewModel: YourFeatureViewModel
    
    init(session: UserSession, apiClient: YourAPIClient) {
        self.session = session
        self.apiClient = apiClient
        self._viewModel = State(wrappedValue: YourFeatureViewModel(
            userId: session.userId,
            apiClient: apiClient
        ))
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Your Feature Module")
                    .font(OnCutsFont.largeTitle)
                
                Text("Logged in as: \(session.displayName)")
                    .foregroundStyle(.secondary)
                
                // Your feature's UI goes here
            }
            .navigationTitle("Your Feature")
        }
    }
}

// MARK: - Step 3: Create your ViewModel

@Observable
@MainActor
final class YourFeatureViewModel {
    let userId: String
    let apiClient: YourAPIClient
    
    init(userId: String, apiClient: YourAPIClient) {
        self.userId = userId
        self.apiClient = apiClient
    }
    
    // Your feature's business logic goes here
}

// MARK: - Step 4: Create your API Client

final class YourAPIClient {
    let baseURL: URL
    let token: String
    
    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }
    
    // Your API calls go here
    func fetchData() async throws -> [YourDataModel] {
        // Example implementation
        let endpoint = baseURL.appendingPathComponent("/api/your-endpoint")
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([YourDataModel].self, from: data)
    }
}

// MARK: - Step 5: Define your data models

struct YourDataModel: Codable, Identifiable {
    let id: String
    let name: String
    // Add your properties
}

// MARK: - Example Package.swift

/*
 Create this file in the root of your Swift Package:
 
 // swift-tools-version: 6.0
 import PackageDescription

 let package = Package(
     name: "YourFeatureModule",
     platforms: [
         .iOS(.v17),
         .macOS(.v14)
     ],
     products: [
         .library(
             name: "YourFeatureModule",
             targets: ["YourFeatureModule"]
         ),
     ],
     dependencies: [
         // Add any external dependencies here
         // .package(url: "https://github.com/example/package.git", from: "1.0.0")
     ],
     targets: [
         .target(
             name: "YourFeatureModule",
             dependencies: []
         ),
         .testTarget(
             name: "YourFeatureModuleTests",
             dependencies: ["YourFeatureModule"]
         )
     ]
 )
 */

// MARK: - Integration Example

/*
 In your Shell app's MainTabView.swift, replace the placeholder:
 
 import YourFeatureModule
 
 case .yourTab:
     if let provider = coordinator.createFeatureProvider() {
         YourFeatureModule(provider: provider)
             .createRootView()
     } else {
         Text("Not authenticated")
     }
 */

// MARK: - Testing Example

/*
 In your module's test target:
 
 import Testing
 @testable import YourFeatureModule
 
 @Suite("Your Feature Tests")
 struct YourFeatureTests {
     
     @Test("Module initializes correctly")
     func initialization() async throws {
         let mockProvider = MockFeatureProvider()
         let module = YourFeatureModule(provider: mockProvider)
         
         #expect(module.provider.session.userId == mockProvider.session.userId)
     }
 }
 
 // Create a mock provider for testing
 struct MockFeatureProvider: FeatureProvider {
     let session = UserSession.mock
     let sessionManager = AppSessionManager()
     let apiBaseURL = URL(string: "https://mock-api.test")!
     let environment: AppEnvironment = .development
 }
 */
