# OnCuts Module Integration Guide

## Overview

This guide explains how to integrate the **OnCuts Feature Module** into your **Intera Shell** app.

## Architecture Summary

Your Intera Shell uses a **Contract-First Architecture**:

```
┌─────────────────────────────────────┐
│      Intera Shell App               │
│  ┌──────────────────────────────┐   │
│  │   AppSessionManager          │   │  Manages authentication
│  │   (Observable, MainActor)    │   │
│  └──────────────────────────────┘   │
│              ↓                       │
│  ┌──────────────────────────────┐   │
│  │   UserSession                │   │  Conforms to protocol
│  │   → UserSessionProtocol      │   │
│  └──────────────────────────────┘   │
│              ↓                       │
│  ┌──────────────────────────────┐   │
│  │   MainCoordinator            │   │  Manages navigation
│  └──────────────────────────────┘   │
│              ↓                       │
│  ┌──────────────────────────────┐   │
│  │   RootView                   │   │  Auth-based routing
│  │   → LoginView                │   │
│  │   → MainTabView              │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│   OnCuts Feature Module         │
│   (Pulled as Package Dependency)    │
│  ┌──────────────────────────────┐   │
│  │  OnCutsModuleBuilder     │   │
│  │  .build(with: session)       │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

## Step-by-Step Integration

### 1. Add the OnCuts Package

#### Option A: Remote Package (Production)
1. In Xcode: File → Add Package Dependencies
2. Enter repository URL: `https://github.com/YourOrg/OnCuts.git`
3. Select version/branch
4. Add to Intera target

#### Option B: Local Package (Development)
1. Clone OnCuts repo locally
2. In Xcode: File → Add Package Dependencies → Add Local...
3. Select the OnCuts folder
4. This creates a **development override** so changes appear immediately

**Git Setup for Local Development:**
```bash
# In your Intera project
git add Package.swift
git commit -m "Add OnCuts dependency"

# When working on OnCuts locally:
cd /path/to/OnCuts
# Make changes
git commit -m "Update feature"

# Changes appear in Intera immediately (Xcode uses local override)
# When ready, push OnCuts changes:
git push origin main

# Then update Intera's Package.resolved:
cd /path/to/Intera
# File → Packages → Update to Latest Package Versions
```

### 2. Verify the Contract

The **OnCuts module** expects a session object that conforms to `UserSessionProtocol`.

**Check that your `UserSession` includes:**
- ✅ `userId: String`
- ✅ `accessToken: String` (mapped from `token`)
- ✅ `email: String`
- ✅ `displayName: String`
- ✅ `userRole: String` (mapped from `role.rawValue`)
- ✅ `stripeCustomerId: String?`
- ✅ `profileImageURL: String?`
- ✅ `isValid: Bool`
- ✅ `refreshAccessToken() async throws -> String`

**Your current implementation already has all of these** via the protocol extension in `CoreUserSessionProtocol.swift`.

### 3. Update MainCoordinator

Once the package is added, update `NavigationMainCoordinator.swift`:

```swift
import OnCuts // Import the module

// Inside MainCoordinator class:

/// Navigate to the OnCuts marketplace
func showOnCutsMarketplace() {
    guard let session = sessionManager.currentSession else { return }
    
    // Use the module's builder to create the view
    let marketplaceView = OnCutsModuleBuilder.buildMarketplace(with: session)
    
    // Either push it:
    navigationPath.append(marketplaceView)
    
    // Or switch to the marketplace tab if it's integrated there
    navigateToTab(.marketplace)
}

/// Handle deep links into OnCuts features
func handleOnCutsDeepLink(bookingId: String) {
    guard let session = sessionManager.currentSession else { return }
    
    let bookingView = OnCutsModuleBuilder.buildBookingDetail(
        bookingId: bookingId,
        session: session
    )
    
    navigationPath.append(bookingView)
}
```

### 4. Update MainTabView

Replace the placeholder marketplace view with the real OnCuts module:

```swift
// In UIMainTabView.swift

import OnCuts

private func viewForTab(_ tab: AppTab) -> some View {
    switch tab {
    case .marketplace:
        // Replace the placeholder with the real module
        if let session = sessionManager.currentSession {
            OnCutsModuleBuilder.buildMarketplace(with: session)
        } else {
            Text("Please log in to access the marketplace")
        }
    
    // ... other cases
    }
}
```

### 5. Handle Module Callbacks

If the OnCuts module needs to communicate back to the Shell (e.g., "user logged out from settings"), create a delegate:

```swift
// In your OnCuts integration
extension MainCoordinator: OnCutsModuleDelegate {
    func onCutsDidRequestLogout() {
        sessionManager.logout()
        popToRoot()
    }
    
    func onCutsDidCompleteBooking(id: String) {
        // Navigate to bookings tab
        navigateToTab(.bookings)
        navigate(to: .bookingDetail(id))
    }
}
```

## Deep Linking Support

### URL Scheme Setup

1. In Xcode target settings: Info → URL Types
2. Add URL Scheme: `campuscuts`

### Handle Deep Links

Update `MainCoordinator.handleDeepLink`:

```swift
func handleDeepLink(_ url: URL) {
    // Parse URL like: campuscuts://booking/abc123
    
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    guard let host = components?.host else { return }
    
    switch host {
    case "booking":
        if let bookingId = components?.path.components(separatedBy: "/").last {
            handleOnCutsDeepLink(bookingId: bookingId)
        }
    
    case "barber":
        if let barberId = components?.path.components(separatedBy: "/").last {
            navigate(to: .barberProfile(barberId))
        }
    
    default:
        break
    }
}
```

### In SceneDelegate or App file:

```swift
// In InteraApp.swift
.onOpenURL { url in
    coordinator.handleDeepLink(url)
}
```

## Testing the Integration

### 1. Unit Tests

```swift
import Testing
@testable import Intera
@testable import OnCuts

@Suite("OnCuts Integration Tests")
struct OnCutsIntegrationTests {
    
    @Test("UserSession conforms to protocol")
    func testSessionProtocolConformance() async throws {
        let session = UserSession.mock
        
        // Verify protocol requirements
        #expect(session.userId == "mock-user-123")
        #expect(session.accessToken == "mock-jwt-token")
        #expect(session.isValid == true)
    }
    
    @Test("Module can be built with session")
    func testModuleBuilding() async throws {
        let session = UserSession.mock
        
        // This should compile if the contract is correct
        let view = OnCutsModuleBuilder.buildMarketplace(with: session)
        
        #expect(view != nil)
    }
}
```

### 2. Manual Testing

1. Run the app
2. Use dev login buttons to authenticate
3. Navigate to Marketplace tab
4. Verify OnCuts content loads
5. Test deep link: `campuscuts://booking/test123`

## Troubleshooting

### "Module not found"
- Verify package is added in Project → Package Dependencies
- Clean build folder (Cmd+Shift+K)
- File → Packages → Reset Package Caches

### "Type does not conform to protocol"
- Check that `UserSession` has all required properties
- Verify the protocol extension in `CoreUserSessionProtocol.swift`

### "Cannot find 'OnCutsModuleBuilder' in scope"
- Add `import OnCuts` at the top of the file
- Verify the module target is linked in Build Phases

### Local package not updating
- File → Packages → Reset Package Caches
- Close and reopen Xcode
- Verify the package path in File Inspector

## Production Checklist

Before shipping:

- [ ] Replace UserDefaults with actual Keychain for token storage
- [ ] Implement real AWS Cognito refresh token flow
- [ ] Add error handling for module loading failures
- [ ] Test all deep link scenarios
- [ ] Add analytics for module navigation
- [ ] Test with real user data
- [ ] Verify Stripe integration works in module
- [ ] Test logout/login flow clears module state
- [ ] Add loading states when launching modules
- [ ] Handle session expiration gracefully

## Next Steps

1. **Pull the OnCuts repository** and add it as a package
2. **Verify the builder interface** matches what's documented here
3. **Replace placeholder views** with real module views
4. **Test the integration** with mock data
5. **Connect to AWS backend** when ready

---

**Questions?** Check the main `README-ARCHITECTURE.md` or review the code in:
- `CoreUserSessionProtocol.swift` - Protocol definitions
- `NavigationMainCoordinator.swift` - Navigation logic
- `CoreAppSessionManager.swift` - Session management
