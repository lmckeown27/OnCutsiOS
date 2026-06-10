# 🚀 CampusCuts - Getting Started Guide

## What You Just Built

Congratulations! You now have a **production-ready Shell App** architecture with:

✅ **Authentication System** - Complete login/logout with session management  
✅ **Dependency Injection** - Clean pattern for sharing auth between modules  
✅ **Navigation Coordinator** - Centralized routing and deep linking support  
✅ **Modular Architecture** - Ready to plug in external feature repositories  
✅ **Modern Swift 6** - Using `@Observable`, async/await, and Swift Concurrency  

## 🎯 Your Next Steps

### Step 1: Test the Shell App (5 minutes)

1. Build and run the app in Xcode (⌘R)
2. You'll see the **LoginView** with the CampusCuts logo
3. In DEBUG mode, tap the **"Student"** or **"Barber"** quick login button
4. You should be taken to the **MainTabView** with 5 tabs
5. Navigate between tabs - notice session info is available everywhere
6. Go to **Profile** tab and tap **"Sign Out"**
7. You should be taken back to the login screen

**✨ If this works, your Shell is ready!**

### Step 2: Create Your First Feature Module (30 minutes)

Let's create the **Marketplace** as a separate Swift Package:

#### A. Create the Repository

```bash
# In Terminal, outside your main project
mkdir CampusCutsMarketplace
cd CampusCutsMarketplace
git init

# Create Swift Package structure
mkdir -p Sources/MarketplaceModule
mkdir -p Tests/MarketplaceModuleTests
```

#### B. Create Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarketplaceModule",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "MarketplaceModule",
            targets: ["MarketplaceModule"]
        ),
    ],
    targets: [
        .target(
            name: "MarketplaceModule",
            dependencies: []
        ),
        .testTarget(
            name: "MarketplaceModuleTests",
            dependencies: ["MarketplaceModule"]
        )
    ]
)
```

#### C. Copy Required Types

You need to copy these types from the Shell into your module (or better yet, create a shared "Core" package):

```swift
// Sources/MarketplaceModule/SharedTypes.swift

// Copy UserSession, UserRole, FeatureProvider from the Shell
// These should eventually live in a shared package
```

#### D. Create Your Module

```swift
// Sources/MarketplaceModule/MarketplaceModule.swift

import SwiftUI

public struct MarketplaceModule {
    let provider: FeatureProvider
    
    public init(provider: FeatureProvider) {
        self.provider = provider
    }
    
    public func createView() -> some View {
        MarketplaceView(
            session: provider.session,
            apiClient: MarketplaceAPIClient(
                baseURL: provider.apiBaseURL,
                token: provider.session.token
            )
        )
    }
}

struct MarketplaceView: View {
    let session: UserSession
    let apiClient: MarketplaceAPIClient
    
    var body: some View {
        List {
            Section {
                Text("Welcome, \(session.displayName)!")
            }
            
            Section("Products") {
                // Your marketplace items here
                ForEach(1..<10) { i in
                    HStack {
                        Image(systemName: "bag.fill")
                        Text("Product \(i)")
                        Spacer()
                        Text("$\(i * 5)")
                    }
                }
            }
        }
        .navigationTitle("Marketplace")
    }
}

final class MarketplaceAPIClient {
    let baseURL: URL
    let token: String
    
    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }
}
```

#### E. Push to GitHub

```bash
git add .
git commit -m "Initial marketplace module"
git remote add origin https://github.com/YOUR_USERNAME/CampusCutsMarketplace.git
git push -u origin main
```

#### F. Add to Your Shell App

1. In Xcode, open your Intera project
2. Go to **Project Settings → Package Dependencies**
3. Click **+** button
4. Enter your GitHub URL: `https://github.com/YOUR_USERNAME/CampusCutsMarketplace.git`
5. Click **Add Package**

#### G. Update MainTabView.swift

```swift
import MarketplaceModule

// In viewForTab(_:)
case .marketplace:
    if let provider = coordinator.createFeatureProvider() {
        MarketplaceModule(provider: provider)
            .createView()
    }
```

**🎉 Your marketplace module is now live!**

### Step 3: Connect to Your AWS Backend (1 hour)

Replace the mock login with real authentication:

#### A. Install AWS Amplify (if using Cognito)

Add to your Shell app via SPM:
```
https://github.com/aws-amplify/amplify-swift
```

#### B. Update LoginView.swift

```swift
import Amplify

private func performLogin() async {
    isLoading = true
    errorMessage = nil
    
    do {
        // Sign in with Cognito
        let signInResult = try await Amplify.Auth.signIn(
            username: email,
            password: password
        )
        
        if signInResult.isSignedIn {
            // Get the session
            let session = try await Amplify.Auth.fetchAuthSession()
            
            // Get user attributes
            let user = try await Amplify.Auth.getCurrentUser()
            
            // Create UserSession
            let userSession = UserSession(
                userId: user.userId,
                token: session.tokens?.idToken ?? "",
                email: email,
                displayName: user.username,
                role: .student, // Get from user attributes
                stripeCustomerId: nil, // Fetch from your backend
                profileImageURL: nil,
                expiresAt: session.tokens?.expiration ?? Date().addingTimeInterval(3600)
            )
            
            sessionManager.login(session: userSession)
        }
        
    } catch {
        errorMessage = "Login failed: \(error.localizedDescription)"
    }
    
    isLoading = false
}
```

#### C. Add Session Refresh

```swift
// In AppSessionManager.swift
func refreshSession() async throws {
    let session = try await Amplify.Auth.fetchAuthSession()
    
    if let tokens = session.tokens {
        let refreshedSession = UserSession(
            userId: currentSession!.userId,
            token: tokens.idToken,
            email: currentSession!.email,
            displayName: currentSession!.displayName,
            role: currentSession!.role,
            stripeCustomerId: currentSession!.stripeCustomerId,
            profileImageURL: currentSession!.profileImageURL,
            expiresAt: tokens.expiration
        )
        
        self.currentSession = refreshedSession
        saveSessionToKeychain()
    }
}
```

### Step 4: Add Stripe Integration (45 minutes)

Create a separate **PaymentModule** package:

```swift
// PaymentModule.swift
import StripePaymentSheet

public struct PaymentModule {
    let provider: FeatureProvider
    
    public init(provider: FeatureProvider) {
        self.provider = provider
    }
    
    public func createPaymentSheet(
        amount: Int,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) -> some View {
        PaymentSheetView(
            customerId: provider.session.stripeCustomerId,
            amount: amount,
            onComplete: onComplete
        )
    }
}
```

### Step 5: Create Additional Modules

Following the same pattern, create:

1. **BookingModule** - Handle appointment scheduling
2. **MessagesModule** - Chat functionality  
3. **ProfileModule** - User profile management
4. **AnalyticsModule** - Business analytics for barbers

## 🔐 Security Checklist

Before going to production:

- [ ] Replace UserDefaults with **Keychain** for token storage
- [ ] Implement certificate pinning for API calls
- [ ] Add biometric authentication (Face ID / Touch ID)
- [ ] Implement token rotation
- [ ] Add rate limiting on login attempts
- [ ] Implement secure logout (invalidate server session)
- [ ] Add jailbreak detection
- [ ] Obfuscate sensitive strings
- [ ] Enable App Transport Security
- [ ] Add SSL certificate validation

## 📊 Recommended Architecture

Your final repository structure:

```
CampusCuts-Shell/           (This project - the hub)
├── Core/
├── Navigation/
├── UI/
└── Features/

CampusCuts-Core/            (Shared types - NEW)
├── UserSession.swift
├── FeatureProvider.swift
└── Networking/

CampusCuts-Marketplace/     (Feature - NEW)
CampusCuts-Booking/         (Feature - NEW)
CampusCuts-Messages/        (Feature - NEW)
CampusCuts-Profile/         (Feature - NEW)
CampusCuts-Analytics/       (Feature - NEW)
```

## 🧪 Testing Strategy

### Unit Tests
- Test each ViewModel in isolation
- Test API clients with mock data
- Test session management logic

### Integration Tests
- Test Shell → Module communication
- Test session injection
- Test navigation flows

### UI Tests
- Test complete user flows
- Test login/logout
- Test tab navigation

Example:

```swift
import Testing

@Suite("End-to-End Tests")
struct E2ETests {
    
    @Test("Complete booking flow")
    @MainActor
    func bookingFlow() async throws {
        let sessionManager = AppSessionManager()
        sessionManager.mockLogin()
        
        let coordinator = MainCoordinator(sessionManager: sessionManager)
        
        // Navigate to bookings
        coordinator.navigateToTab(.bookings)
        #expect(coordinator.selectedTab == .bookings)
        
        // Create booking
        coordinator.presentSheet(.createBooking)
        #expect(coordinator.presentedSheet == .createBooking)
    }
}
```

## 🚢 Deployment

### TestFlight

1. Archive your app (Product → Archive)
2. Distribute to App Store Connect
3. Submit for TestFlight review
4. Invite beta testers

### Production

1. Switch environment to `.production` in `InteraApp.swift`
2. Update API URLs in `FeatureProvider.swift`
3. Enable production Stripe keys
4. Submit for App Store review

## 💡 Pro Tips

1. **Keep the Shell Thin** - Business logic goes in feature modules
2. **Share Common Code** - Create a "Core" package for shared types
3. **Version Your Modules** - Use semantic versioning for feature packages
4. **Document Interfaces** - Clear contracts between Shell and modules
5. **Monitor Performance** - Use Instruments to check module loading times

## 🆘 Common Issues

### "Cannot find type 'FeatureProvider'"
→ Make sure you've copied or imported the shared types into your module

### "Session not injected"
→ Check that you're calling `coordinator.createFeatureProvider()` before initializing the module

### "Module not updating"
→ In Xcode: File → Packages → Reset Package Cache

### "Build fails after adding package"
→ Clean build folder (Shift + Cmd + K) and rebuild

## 📚 Additional Resources

- [Swift Package Manager Docs](https://swift.org/package-manager/)
- [AWS Amplify for iOS](https://docs.amplify.aws/start/q/integration/ios/)
- [Stripe iOS SDK](https://stripe.com/docs/mobile/ios)
- [SwiftUI Navigation](https://developer.apple.com/documentation/swiftui/navigation)

---

## 🎓 What You Learned

✅ MVVM-C architecture pattern  
✅ Dependency injection in SwiftUI  
✅ Coordinator-based navigation  
✅ Modular app design with Swift Packages  
✅ Session management and authentication flow  
✅ Modern Swift concurrency patterns  

**You're ready to build CampusCuts! 🚀**

---

*Created: March 8, 2026*  
*Shell Version: 1.0.0*  
*Swift Version: 6.0*
