# 🏗️ OnCuts Architecture Overview

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         InteraApp.swift                          │
│                      (App Entry Point)                           │
│                                                                   │
│  ┌────────────────────┐         ┌─────────────────────┐         │
│  │  AppSessionManager │◄────────┤  MainCoordinator    │         │
│  │  (@Observable)     │         │  (Navigation)       │         │
│  │                    │         │                     │         │
│  │  • currentSession  │         │  • selectedTab      │         │
│  │  • isAuthenticated │         │  • navigationPath   │         │
│  │  • login()         │         │  • presentSheet()   │         │
│  │  • logout()        │         │  • navigate()       │         │
│  └────────────────────┘         └─────────────────────┘         │
│           │                               │                      │
│           │                               │                      │
└───────────┼───────────────────────────────┼──────────────────────┘
            │                               │
            ▼                               ▼
┌───────────────────────────────────────────────────────────────────┐
│                          RootView.swift                            │
│                      (Root Orchestrator)                           │
│                                                                    │
│   if sessionManager.isAuthenticated {                              │
│       MainTabView()         ◄── Authenticated State               │
│   } else {                                                         │
│       LoginView()           ◄── Unauthenticated State             │
│   }                                                                │
└───────────────────────────────────────────────────────────────────┘
            │                               │
            │                               │
    ┌───────┴────────┐             ┌───────┴──────────────────────┐
    │   LoginView    │             │      MainTabView             │
    │                │             │                              │
    │  [Email]       │             │  ┌──────┬──────┬──────┐     │
    │  [Password]    │             │  │ Home │Market│Book. │ ... │
    │  [Sign In]     │             │  └───┬──┴──┬───┴──┬───┘     │
    │                │             │      │     │      │          │
    └────────────────┘             │  ┌───▼─────▼──────▼───┐     │
                                   │  │  Feature Modules    │     │
                                   │  │  (with injection)   │     │
                                   │  └─────────────────────┘     │
                                   └──────────────────────────────┘
                                              │
                        ┌─────────────────────┼─────────────────────┐
                        │                     │                     │
                        ▼                     ▼                     ▼
            ┌────────────────────┐  ┌──────────────────┐  ┌─────────────────┐
            │ MarketplaceModule  │  │  BookingModule   │  │  MessageModule  │
            │  (External Repo)   │  │ (External Repo)  │  │ (External Repo) │
            │                    │  │                  │  │                 │
            │  init(provider:    │  │  init(provider:  │  │  init(provider: │
            │    FeatureProvider)│  │    FeatureProvider│  │    FeatureProvider
            │                    │  │                  │  │                 │
            │  ✓ Has UserSession │  │  ✓ Has Token     │  │  ✓ Has API URL  │
            │  ✓ Has API Client  │  │  ✓ Independent   │  │  ✓ Modular      │
            └────────────────────┘  └──────────────────┘  └─────────────────┘
```

## Data Flow Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                     Authentication Flow                               │
└──────────────────────────────────────────────────────────────────────┘

1. User enters credentials in LoginView
                │
                ▼
2. LoginView calls sessionManager.login(session: UserSession)
                │
                ▼
3. AppSessionManager updates @Observable state
                │
                ▼
4. RootView observes change → switches to MainTabView
                │
                ▼
5. MainCoordinator creates FeatureProvider with session
                │
                ▼
6. Feature modules receive authenticated session via injection
                │
                ▼
7. Modules make API calls using injected token


┌──────────────────────────────────────────────────────────────────────┐
│                     Session Expiration Flow                           │
└──────────────────────────────────────────────────────────────────────┘

1. AppSessionManager runs background validation task
                │
                ▼
2. Detects session.expiresAt < Date()
                │
                ▼
3. Calls sessionManager.logout()
                │
                ▼
4. RootView observes change → switches to LoginView
                │
                ▼
5. User must re-authenticate
```

## Dependency Injection Pattern

```swift
┌─────────────────────────────────────────────────────────────────┐
│                    The "Plug" Pattern                            │
└─────────────────────────────────────────────────────────────────┘

// Shell App creates the provider
let provider = DefaultFeatureProvider(
    session: UserSession(userId: "123", token: "abc", ...),
    sessionManager: AppSessionManager(),
    environment: .production
)

// Feature module receives the provider
MarketplaceModule(provider: provider)
    │
    ├── provider.session.userId       → "123"
    ├── provider.session.token         → "abc"
    ├── provider.apiBaseURL            → "https://api.campuscuts.com"
    └── provider.sessionManager.logout() → Call from module
```

## File Organization

```
Intera/
│
├── 📱 InteraApp.swift                 ← App entry point
├── 🎯 RootView.swift                  ← Auth state router
├── 📄 ContentView.swift               ← (Legacy - can be removed)
│
├── 📁 Core/
│   ├── UserSession.swift              ← Data model
│   ├── AppSessionManager.swift        ← State management
│   └── FeatureProvider.swift          ← DI protocol
│
├── 📁 Navigation/
│   └── MainCoordinator.swift          ← Navigation logic
│
├── 📁 UI/
│   ├── LoginView.swift                ← Auth screen
│   └── MainTabView.swift              ← Main interface
│
└── 📁 Features/
    ├── FeaturePlaceholders.swift      ← Temporary views
    └── FeatureModuleTemplate.swift    ← Template for new modules
```

## Module Communication

```
┌──────────────────────────────────────────────────────────────────┐
│        How Modules Talk to Each Other (The Right Way)            │
└──────────────────────────────────────────────────────────────────┘

❌ DON'T DO THIS:
   MarketplaceModule → BookingModule
   (Direct coupling - BAD!)

✅ DO THIS:
   MarketplaceModule → MainCoordinator → BookingModule
   
   Example:
   // In MarketplaceModule
   coordinator.navigate(to: .bookingDetail("123"))
   
   // MainCoordinator handles the routing
   case .bookingDetail(let id):
       BookingModule(provider: provider).detailView(id)
```

## State Management Strategy

```
┌──────────────────────────────────────────────────────────────────┐
│                   @Observable State Tree                          │
└──────────────────────────────────────────────────────────────────┘

AppSessionManager (@Observable)          ← Global auth state
    │
    ├── currentSession: UserSession?     ← Drives entire app
    └── isAuthenticated: Bool            ← Computed property
        │
        └── Observed by: RootView
            │
            ├── if true  → MainTabView
            │               │
            │               └── Each module gets provider
            │                   │
            │                   └── Module ViewModels (@Observable)
            │                       ├── Local state
            │                       └── API data
            │
            └── if false → LoginView
```

## Security Layers

```
┌──────────────────────────────────────────────────────────────────┐
│                      Security Architecture                        │
└──────────────────────────────────────────────────────────────────┘

Layer 1: Authentication
    ├── AWS Cognito (User Pool)
    ├── JWT Token (stored in Keychain)
    └── Biometric (Face ID / Touch ID)

Layer 2: Session Management
    ├── AppSessionManager validates expiration
    ├── Auto-refresh before expiry
    └── Auto-logout on expire

Layer 3: Network Security
    ├── HTTPS only (App Transport Security)
    ├── Certificate pinning
    └── Bearer token in headers

Layer 4: Data Protection
    ├── Keychain for tokens
    ├── Encrypted local storage
    └── Secure enclave for sensitive data
```

## Scalability Model

```
┌──────────────────────────────────────────────────────────────────┐
│                    How This Scales                                │
└──────────────────────────────────────────────────────────────────┘

Team Structure:
    Shell Team (2 devs)
        │
        ├── Maintains: Auth, Navigation, Core
        └── Reviews: Module integration PRs
    
    Feature Teams (2-3 devs each)
        │
        ├── Marketplace Team → Own repository
        ├── Booking Team → Own repository  
        ├── Messages Team → Own repository
        └── Analytics Team → Own repository

Development Flow:
    1. Feature team builds in their repo
    2. They test with mock FeatureProvider
    3. Submit PR to Shell team
    4. Shell team updates package dependency
    5. Integration tested in Shell app
    6. Released together or independently

Version Management:
    Shell App: v1.2.0
        ├── MarketplaceModule: v2.1.0
        ├── BookingModule: v1.5.0
        └── MessagesModule: v3.0.0
    
    Each module can be updated independently!
```

## Performance Considerations

```
┌──────────────────────────────────────────────────────────────────┐
│                    Performance Strategy                           │
└──────────────────────────────────────────────────────────────────┘

Module Loading:
    ✓ Lazy initialization (only load when tab is tapped)
    ✓ Swift Packages compile separately
    ✓ Can use dynamic frameworks for larger modules

Memory Management:
    ✓ Each tab has independent NavigationStack
    ✓ ViewModels are deallocated when tab is inactive
    ✓ @Observable provides efficient observation

Network Optimization:
    ✓ Shared URLSession with configuration
    ✓ Request caching
    ✓ Background fetch for critical data

Startup Time:
    ✓ Minimal Shell app size
    ✓ Session loads from Keychain quickly
    ✓ Modules load on-demand
```

## Testing Strategy

```
┌──────────────────────────────────────────────────────────────────┐
│                    Test Pyramid                                   │
└──────────────────────────────────────────────────────────────────┘

        ┌──────────────┐
        │   E2E Tests  │  ← Few (Complete user flows)
        │   (XCUITest) │
        └──────────────┘
       ┌────────────────┐
       │ Integration    │  ← Some (Module ↔ Shell)
       │ Tests          │
       └────────────────┘
      ┌──────────────────┐
      │  Unit Tests      │  ← Many (ViewModels, Managers)
      │  (Swift Testing) │
      └──────────────────┘

Test Coverage Goals:
    ├── Shell Core: 90%+ (Critical path)
    ├── Feature Modules: 80%+ (Business logic)
    └── UI Views: 50%+ (Key flows only)
```

## Deployment Pipeline

```
┌──────────────────────────────────────────────────────────────────┐
│                    CI/CD Pipeline                                 │
└──────────────────────────────────────────────────────────────────┘

On PR to Shell Repository:
    1. Lint Swift code
    2. Run unit tests
    3. Build Shell app
    4. Run integration tests
    5. Archive for TestFlight
    6. Generate code coverage report

On Module Repository Update:
    1. Module team runs their tests
    2. Creates release tag (e.g., v2.1.0)
    3. Shell team updates Package.swift
    4. Full integration test runs
    5. Deploy to TestFlight

Production Release:
    1. Switch to .production environment
    2. Full regression test suite
    3. App Store submission
    4. Gradual rollout (10% → 50% → 100%)
```

---

## Quick Reference

### Key Files to Modify

| What You Need | File to Edit |
|---------------|--------------|
| Add new tab | `Navigation/MainCoordinator.swift` (AppTab enum) |
| Change API URL | `Core/FeatureProvider.swift` (AppEnvironment) |
| Modify login UI | `UI/LoginView.swift` |
| Add deep link | `Navigation/MainCoordinator.swift` (handleDeepLink) |
| Update session model | `Core/UserSession.swift` |

### Key Concepts

| Term | Meaning |
|------|---------|
| Shell | Main app that handles auth and navigation |
| Module | External Swift Package with a feature |
| Provider | Dependency injection container |
| Coordinator | Navigation manager |
| Session | Authenticated user data and token |

### Common Commands

```bash
# Update package dependencies
File → Packages → Update to Latest Package Versions

# Reset package cache
File → Packages → Reset Package Cache

# Clean build folder
Shift + Cmd + K

# Archive for TestFlight
Product → Archive
```

---

**Last Updated:** March 8, 2026  
**Architecture Version:** 1.0.0  
**Minimum iOS Version:** 17.0  
**Swift Version:** 6.0
