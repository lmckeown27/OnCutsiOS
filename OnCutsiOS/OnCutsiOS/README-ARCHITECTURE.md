# OnCuts Shell App Architecture

## 🏗️ Overview

This is the **Shell App** (Main Repository) for OnCuts using a modular **MVVM-C** (Model-View-ViewModel with Coordinators) architecture. The Shell acts as a hub that manages authentication and injects session data into external feature modules.

## 📂 Project Structure

```
Intera/
├── Core/                           # Core business logic
│   ├── UserSession.swift          # User session data model
│   ├── AppSessionManager.swift    # Session state management (@Observable)
│   └── FeatureProvider.swift      # Dependency injection protocol
│
├── Navigation/                     # Navigation and coordination
│   └── MainCoordinator.swift      # Main navigation coordinator
│
├── UI/                            # Main UI views
│   ├── LoginView.swift            # Authentication screen
│   └── MainTabView.swift          # Main tab bar interface
│
├── Features/                       # Feature module placeholders
│   └── FeaturePlaceholders.swift  # Temporary views (will be replaced)
│
├── RootView.swift                 # Root orchestrator view
└── InteraApp.swift                # App entry point
```

## 🔑 Key Components

### 1. AppSessionManager (The "Brain")
- **Location:** `Core/AppSessionManager.swift`
- **Purpose:** Tracks authentication state and manages user sessions
- **Features:**
  - Automatic session validation
  - Secure token storage (TODO: move to Keychain)
  - Session refresh capability
  - Observable state for reactive UI updates

```swift
let sessionManager = AppSessionManager()
sessionManager.login(session: userSession)
```

### 2. MainCoordinator (The "Traffic Controller")
- **Location:** `Navigation/MainCoordinator.swift`
- **Purpose:** Manages navigation flow and routing
- **Features:**
  - Tab-based navigation
  - Deep linking support
  - Sheet presentation management
  - Creates feature providers for modules

```swift
let coordinator = MainCoordinator(sessionManager: sessionManager)
coordinator.navigateToTab(.marketplace)
coordinator.presentSheet(.settings)
```

### 3. FeatureProvider (The "Plug")
- **Location:** `Core/FeatureProvider.swift`
- **Purpose:** Dependency injection interface for feature modules
- **Features:**
  - Injects authenticated session into external repos
  - Provides access to session manager
  - Configures environment (dev/staging/prod)

```swift
protocol FeatureProvider {
    var session: UserSession { get }
    var sessionManager: AppSessionManager { get }
    var apiBaseURL: URL { get }
    var environment: AppEnvironment { get }
}
```

### 4. RootView (The "Orchestrator")
- **Location:** `RootView.swift`
- **Purpose:** Switches between login and main content based on auth state
- **Features:**
  - Automatic transitions when auth state changes
  - Smooth animations
  - Acts as the single source of truth

## 🔐 Authentication Flow

```
1. App launches → RootView checks sessionManager.isAuthenticated
2. If false → Show LoginView
3. User logs in → sessionManager.login(session:)
4. RootView detects change → Animates to MainTabView
5. Session expires → Auto-logout → Back to LoginView
```

## 🧩 Adding External Feature Modules

### Step 1: Create Your Feature Module Repository

Create a new Swift Package with this structure:

```swift
// Package.swift
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
        )
    ]
)
```

### Step 2: Implement the FeatureModule Protocol

```swift
// In your external repo
public struct MarketplaceModule: FeatureModule {
    let provider: FeatureProvider
    
    public init(provider: FeatureProvider) {
        self.provider = provider
    }
    
    public var rootView: some View {
        MarketplaceRootView(
            userId: provider.session.userId,
            apiClient: APIClient(
                baseURL: provider.apiBaseURL,
                token: provider.session.token
            )
        )
    }
}
```

### Step 3: Add to the Shell App

1. In Xcode, go to **Project Settings → Package Dependencies**
2. Click **+** and add your GitHub repo URL
3. Update `MainTabView.swift`:

```swift
import MarketplaceModule

// Replace the placeholder
case .marketplace:
    if let provider = coordinator.createFeatureProvider() {
        MarketplaceModule(provider: provider).rootView
    }
```

## 🚀 Quick Start

### Running the App

1. Open `Intera.xcodeproj` in Xcode
2. Build and run (⌘R)
3. In debug mode, use the quick login buttons:
   - **Student** - Login as a student user
   - **Barber** - Login as a barber user

### Testing Authentication

```swift
// Mock login for development
sessionManager.mockLogin(as: .student)

// Production login
let session = UserSession(
    userId: "user-123",
    token: "jwt-token-from-backend",
    email: "user@example.com",
    displayName: "John Doe",
    role: .student,
    stripeCustomerId: "cus_xxx",
    profileImageURL: nil,
    expiresAt: Date().addingTimeInterval(3600)
)
sessionManager.login(session: session)
```

## 🔧 Configuration

### Environments

Change environment in `InteraApp.swift`:

```swift
MainCoordinator(
    sessionManager: sessionManager,
    environment: .development // or .staging, .production
)
```

### API URLs

Configure in `Core/FeatureProvider.swift`:

```swift
enum AppEnvironment: String {
    case development
    case staging
    case production
    
    var apiBaseURL: URL {
        switch self {
        case .development:
            return URL(string: "https://dev-api.campuscuts.com")!
        case .staging:
            return URL(string: "https://staging-api.campuscuts.com")!
        case .production:
            return URL(string: "https://api.campuscuts.com")!
        }
    }
}
```

## 📝 TODO: Production Readiness

- [ ] Replace UserDefaults with **Keychain** for secure token storage
- [ ] Implement real AWS Cognito authentication in `LoginView.swift`
- [ ] Add biometric authentication (Face ID / Touch ID)
- [ ] Implement token refresh logic in `AppSessionManager`
- [ ] Add error handling and retry logic
- [ ] Implement analytics and crash reporting
- [ ] Add network reachability monitoring
- [ ] Setup CI/CD pipeline
- [ ] Add comprehensive unit tests
- [ ] Document API contracts for feature modules

## 🧪 Testing

### Manual Testing Checklist

- [ ] Login flow works
- [ ] Session persists across app restarts
- [ ] Logout clears session
- [ ] Tab navigation works
- [ ] Sheet presentation/dismissal works
- [ ] Session expiration triggers logout
- [ ] Feature provider correctly injects session

### Unit Test Example

```swift
import Testing

@Suite("Session Management Tests")
struct SessionTests {
    
    @Test("Session is valid when not expired")
    func sessionValidity() async throws {
        let session = UserSession(
            userId: "test",
            token: "token",
            email: "test@test.com",
            displayName: "Test",
            role: .student,
            stripeCustomerId: nil,
            profileImageURL: nil,
            expiresAt: Date().addingTimeInterval(3600)
        )
        
        #expect(session.isValid == true)
    }
    
    @Test("Login updates session manager state")
    @MainActor
    func loginFlow() async throws {
        let manager = AppSessionManager()
        #expect(manager.isAuthenticated == false)
        
        manager.mockLogin()
        #expect(manager.isAuthenticated == true)
    }
}
```

## 📚 Architecture Benefits

### ✅ Separation of Concerns
- Auth logic is isolated in `AppSessionManager`
- Navigation logic is isolated in `MainCoordinator`
- Feature modules are completely independent

### ✅ Testability
- Each component can be tested in isolation
- Mock sessions for UI testing
- Dependency injection makes testing easy

### ✅ Scalability
- New features = new Swift Packages
- Multiple teams can work on different modules
- Easy to swap out implementations

### ✅ Security
- Session token is injected, not stored in feature modules
- Centralized auth state management
- Easy to implement advanced security features

## 🎯 Next Steps

1. **Test the Shell** - Run the app and verify login/logout flows
2. **Create Your First Module** - Build the Marketplace as a Swift Package
3. **Integrate AWS** - Replace mock login with real Cognito auth
4. **Add Stripe** - Implement payment processing in a dedicated module
5. **Deploy** - Setup CI/CD and TestFlight distribution

---

**Questions?** Check out the inline documentation in each file or reach out to the team.

**Last Updated:** March 8, 2026
