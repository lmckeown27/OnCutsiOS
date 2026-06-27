# Multi-Service Platform Architecture

This document outlines how the Intera app supports multiple service platforms (CampusCuts for haircuts, BeautyPlatform for beauty services, etc.) with each pulling from different packages/backends.

## Overview

The app uses a **platform-agnostic frontend** with **service-specific backends**:

```
┌─────────────────────────────────────────────────────┐
│              Intera App (Shell)                      │
│  Platform-agnostic UI & Service Selection            │
└─────────────────────────────────────────────────────┘
                      │
        ┌─────────────┴─────────────┐
        ▼                           ▼
┌───────────────┐          ┌────────────────┐
│  CampusCuts   │          │ Beauty Platform│
│   Package     │          │    Package     │
│               │          │                │
│ - Barber API  │          │ - Stylist API  │
│ - Models      │          │ - Models       │
│ - Services    │          │ - Services     │
└───────────────┘          └────────────────┘
```

## Architecture Layers

### 1. **Core Layer** (Shared)
Platform-agnostic types and protocols that all services conform to.

**File**: `CoreServiceProvider.swift`

```swift
// Generic service provider protocol that all platforms implement
protocol ServiceProviderProtocol: Identifiable, Codable {
    var id: String { get }
    var userId: String { get }
    var businessName: String { get }
    var bio: String? { get }
    var profileImageUrl: String? { get }
    var rating: Double? { get }
    var isAvailableNow: Bool? { get }
}
```

### 2. **Service Adapters**
Convert platform-specific models to the unified `ServiceProvider` type.

**Files**:
- `CampusCutsAdapter.swift` - Converts `Barber` → `ServiceProvider`
- `BeautyPlatformAdapter.swift` - Converts `BeautySpecialist` → `ServiceProvider`

### 3. **Service Registry**
Manages which platforms are active and routes requests appropriately.

**File**: `ServiceRegistry.swift`

```swift
enum ServicePlatform: String, CaseIterable {
    case campusCuts = "haircuts"
    case beautyPlatform = "beauty"
    case wellness = "wellness"
    
    var displayName: String {
        switch self {
        case .campusCuts: return "Haircuts"
        case .beautyPlatform: return "Beauty"
        case .wellness: return "Wellness"
        }
    }
    
    var packageName: String {
        switch self {
        case .campusCuts: return "CampusCutsModule"
        case .beautyPlatform: return "BeautyPlatformModule"
        case .wellness: return "WellnessModule"
        }
    }
}
```

## Implementation Strategy

### Option 1: Unified Model with Adapter Pattern (Recommended)

Keep `ServiceProvider` as the unified UI model, but create adapters for each platform:

```swift
// CampusCutsAdapter.swift
extension Barber {
    func toServiceProvider() -> ServiceProvider {
        ServiceProvider(
            id: self.id,
            userId: self.userId,
            businessName: self.fullName,
            bio: self.bio,
            instagramHandle: nil, // Not in Barber model
            profileImageUrl: self.profileImageUrl,
            rating: self.averageRating,
            reviewCount: nil,
            completedBookings: self.totalBookings,
            isAvailableNow: self.instantBook,
            priceRange: extractPriceRange()
        )
    }
    
    private func extractPriceRange() -> ServiceProvider.PriceRange? {
        guard !pricing.isEmpty else { return nil }
        let prices = pricing.values.sorted()
        return ServiceProvider.PriceRange(
            min: Int(prices.first ?? 0),
            max: Int(prices.last ?? 0)
        )
    }
}

// BeautySpecialist would have similar extension
extension BeautySpecialist {
    func toServiceProvider() -> ServiceProvider {
        // Convert BeautySpecialist to ServiceProvider
    }
}
```

### Option 2: Protocol-Based Approach

Define a protocol that both platforms implement:

```swift
protocol ServiceProviderSource {
    var providerType: ServicePlatform { get }
    func fetchProviders() async throws -> [ServiceProvider]
    func fetchProvider(id: String) async throws -> ServiceProvider
    func createBooking(_ booking: BookingRequest) async throws -> Booking
}

class CampusCutsService: ServiceProviderSource {
    let providerType: ServicePlatform = .campusCuts
    
    func fetchProviders() async throws -> [ServiceProvider] {
        // Call CampusCuts API
        let barbers = try await CampusCutsAPI.fetchBarbers()
        return barbers.map { $0.toServiceProvider() }
    }
}

class BeautyPlatformService: ServiceProviderSource {
    let providerType: ServicePlatform = .beautyPlatform
    
    func fetchProviders() async throws -> [ServiceProvider] {
        // Call Beauty Platform API
        let specialists = try await BeautyAPI.fetchSpecialists()
        return specialists.map { $0.toServiceProvider() }
    }
}
```

## Data Flow Example

### User selects "Haircuts" service:

```
1. User taps "Haircuts" in ServiceSelectionScreen
   ↓
2. MainCoordinator sets selectedService = .campusCuts
   ↓
3. ConsumerHomeScreen loads
   ↓
4. ServiceRegistry returns CampusCutsService
   ↓
5. CampusCutsService.fetchProviders() called
   ↓
6. CampusCuts API returns [Barber]
   ↓
7. Adapter converts [Barber] → [ServiceProvider]
   ↓
8. UI displays providers using ServiceProviderCard
```

### User selects "Beauty" service:

```
1. User taps "Beauty" in ServiceSelectionScreen
   ↓
2. MainCoordinator sets selectedService = .beautyPlatform
   ↓
3. ConsumerHomeScreen loads
   ↓
4. ServiceRegistry returns BeautyPlatformService
   ↓
5. BeautyPlatformService.fetchProviders() called
   ↓
6. Beauty API returns [BeautySpecialist]
   ↓
7. Adapter converts [BeautySpecialist] → [ServiceProvider]
   ↓
8. UI displays providers using ServiceProviderCard
```

## File Structure

```
Intera/
├── Core/
│   ├── Models/
│   │   ├── ServiceProvider.swift         # Unified UI model
│   │   ├── Booking.swift                 # Unified booking model
│   │   └── ServiceProviderProtocol.swift # Protocol all platforms implement
│   │
│   ├── Services/
│   │   ├── ServiceRegistry.swift         # Platform management
│   │   └── ServiceProviderSource.swift   # Protocol for platform services
│   │
│   └── Adapters/
│       ├── CampusCutsAdapter.swift       # Barber → ServiceProvider
│       └── BeautyPlatformAdapter.swift   # BeautySpecialist → ServiceProvider
│
├── Packages/
│   ├── CampusCutsModule/
│   │   ├── Models/
│   │   │   └── Barber.swift              # CampusCuts-specific model
│   │   ├── Services/
│   │   │   └── CampusCutsAPI.swift
│   │   └── CampusCutsService.swift
│   │
│   └── BeautyPlatformModule/
│       ├── Models/
│       │   └── BeautySpecialist.swift    # Beauty-specific model
│       ├── Services/
│       │   └── BeautyAPI.swift
│       └── BeautyPlatformService.swift
│
├── UI/
│   ├── Components/
│   │   ├── ServiceProviderCard.swift     # Platform-agnostic card
│   │   └── BookingCard.swift             # Platform-agnostic booking
│   │
│   └── Screens/
│       ├── ServiceSelectionScreen.swift  # Choose platform
│       └── ConsumerHomeScreen.swift      # Shows providers from selected platform
│
└── Coordination/
    └── MainCoordinator.swift             # Manages navigation & platform selection
```

## Benefits of This Architecture

### ✅ Separation of Concerns
- Each platform package is independent
- Can update CampusCuts without affecting Beauty platform
- Easy to add new service platforms

### ✅ Reusable UI
- Single `ServiceProviderCard` works for all platforms
- Consistent user experience across services
- Reduce code duplication

### ✅ Flexible Backend Integration
- CampusCuts can use AWS Cognito + Stripe
- Beauty platform can use different auth/payment
- Each platform can have different API structures

### ✅ Easy Testing
- Mock each platform service independently
- Test adapters separately from UI
- Can disable platforms for testing

### ✅ Scalability
- Add new platforms by:
  1. Creating new package (e.g., `WellnessModule`)
  2. Creating adapter
  3. Adding to `ServicePlatform` enum
  4. No changes to UI needed!

## Migration Path

### Phase 1: Create Core Models ✅
- [x] Create unified `ServiceProvider` model
- [x] Create unified `Booking` model

### Phase 2: Create Adapters
- [ ] Create `CampusCutsAdapter` to convert `Barber` → `ServiceProvider`
- [ ] Create `BeautyPlatformAdapter` (if/when Beauty has its own API)
- [ ] Add mock data adapters

### Phase 3: Service Registry
- [ ] Create `ServiceRegistry` to manage platforms
- [ ] Update `MainCoordinator` to work with registry
- [ ] Update screens to use appropriate service based on selection

### Phase 4: Package Separation
- [ ] Move CampusCuts-specific code to module
- [ ] Create Beauty platform module
- [ ] Configure SPM or separate framework targets

## Mock Data Strategy

For development, each platform has mock data:

```swift
// CampusCuts mocks (existing)
extension Barber {
    static let mocks: [Barber] = [...]
}

// Beauty platform mocks
extension BeautySpecialist {
    static let mocks: [BeautySpecialist] = [...]
}

// Unified mocks for UI development
extension ServiceProvider {
    static let campusCutsMocks = Barber.mocks.map { $0.toServiceProvider() }
    static let beautyMocks = BeautySpecialist.mocks.map { $0.toServiceProvider() }
    static let allMocks = campusCutsMocks + beautyMocks
}
```

## Next Steps

1. **Keep existing `Barber.swift`** - This is from CampusCuts package
2. **Keep `ServiceProvider`** - This is the unified UI model
3. **Create adapter** - Convert between them
4. **Remove duplicate `Barber` typealias** - Causes conflicts
5. **Implement `ServiceRegistry`** - Route to correct platform based on selection

Would you like me to implement this architecture?
