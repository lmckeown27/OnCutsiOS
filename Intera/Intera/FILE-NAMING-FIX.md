# File Naming Fix: Platform-Agnostic Shell App

## The Problem

The file `ComponentsBarberCard.swift` contains platform-agnostic code but has a platform-specific name. This violates the shell app architecture where the core UI should be neutral.

## The Solution

### ✅ Created New File: `ServiceProviderCard.swift`

This file is now properly named to reflect its purpose:
- **Platform-agnostic** - works for ANY service platform
- **Generic naming** - no reference to specific services
- **Shell app layer** - part of the unified UI

### Changes Made

1. **Renamed `mocks` → `haircutMocks`** for clarity
2. **Added better documentation** explaining the architecture
3. **Added preview for each platform** (haircuts, beauty, all)
4. **Added architecture notes** at the bottom of the file

### What to Do

1. **Add `ServiceProviderCard.swift` to your Xcode project**
2. **Delete these old files**:
   - `ComponentsBarberCard.swift` 
   - `MockBeautySpecialists 2.swift`
   - `MockBeautySpecialists.swift` (if it exists)
3. **Clean build folder**: Product → Clean Build Folder
4. **Build**: Product → Build

## Correct Architecture

```
Shell App (Platform-Agnostic)
├── ServiceProviderCard.swift          ← Generic UI component
├── ServiceProviderDetailSheet         ← Generic detail view
├── BookingCard.swift                  ← Generic booking view
└── ConsumerHomeScreen.swift           ← Generic consumer screen

Platform-Specific Packages
├── CampusCuts Package
│   ├── Barber.swift                   ← Haircut-specific model
│   ├── CampusCutsAPI.swift           ← Haircut API
│   └── CampusCutsAdapter.swift       ← Converts Barber → ServiceProvider
│
├── Beauty Platform Package (future)
│   ├── BeautySpecialist.swift        ← Beauty-specific model
│   ├── BeautyAPI.swift               ← Beauty API
│   └── BeautyAdapter.swift           ← Converts BeautySpecialist → ServiceProvider
│
└── Wellness Platform Package (future)
    ├── WellnessProvider.swift        ← Wellness-specific model
    ├── WellnessAPI.swift             ← Wellness API
    └── WellnessAdapter.swift         ← Converts WellnessProvider → ServiceProvider
```

## File Naming Principles

### ✅ Shell App Files (Platform-Agnostic)
- `ServiceProviderCard.swift`
- `ServiceProviderDetailSheet.swift`
- `BookingCard.swift`
- `ServiceRegistry.swift`
- `MainCoordinator.swift`

### ✅ Platform Package Files (Platform-Specific)
- `Barber.swift` (in CampusCuts package)
- `BeautySpecialist.swift` (in Beauty package)
- `WellnessProvider.swift` (in Wellness package)

### ❌ Avoid These Names in Shell App
- ~~`BarberCard.swift`~~ - implies only for barbers
- ~~`BeautyCard.swift`~~ - implies only for beauty
- ~~`HaircutScreen.swift`~~ - implies only for haircuts

## Mock Data Organization

### In `ServiceProviderCard.swift`

```swift
// Platform-specific mocks for development/testing
static let haircutMocks: [ServiceProvider]  // Simulates CampusCuts data
static let beautyMocks: [ServiceProvider]   // Simulates Beauty platform data
static let wellnessMocks: [ServiceProvider] // Future: Simulates Wellness data

// Convenience collections
static let mocks = haircutMocks            // For backward compatibility
static let allMocks = haircutMocks + beautyMocks + wellnessMocks
```

### Usage

```swift
// In development - simulate different platforms
@State private var providers = ServiceProvider.haircutMocks  // Test haircuts
@State private var providers = ServiceProvider.beautyMocks   // Test beauty
@State private var providers = ServiceProvider.allMocks      // Test all

// In production - fetch from appropriate platform
let platform = selectedService.platform
switch platform {
case .campusCuts:
    let barbers = try await CampusCutsAPI.fetchBarbers()
    providers = barbers.map { $0.toServiceProvider() }
    
case .beauty:
    let specialists = try await BeautyAPI.fetchSpecialists()
    providers = specialists.map { $0.toServiceProvider() }
    
case .wellness:
    let providers = try await WellnessAPI.fetchProviders()
    providers = providers.map { $0.toServiceProvider() }
}
```

## Benefits of Proper Naming

### ✅ Clarity
- File name immediately tells you its purpose
- No confusion about what can use this code
- Easy for new developers to understand

### ✅ Scalability
- Adding new platform doesn't require renaming core files
- Platform-specific code stays in packages
- Shell app remains generic

### ✅ Maintainability
- Clear separation of concerns
- Platform changes don't affect shell app
- Can work on platforms independently

### ✅ Testability
- Easy to test with mock data from any platform
- Can test shell app without platform packages
- Platform packages can be tested independently

## Migration Checklist

- [x] Create `ServiceProviderCard.swift` with proper naming
- [ ] Add new file to Xcode project
- [ ] Delete `ComponentsBarberCard.swift` from Xcode
- [ ] Delete `MockBeautySpecialists 2.swift` from Xcode
- [ ] Delete `MockBeautySpecialists.swift` if it exists
- [ ] Clean build folder
- [ ] Build project
- [ ] Verify no compilation errors
- [ ] Test with different mock data sets

## After Migration

Your file structure will look like:

```
Intera/
├── Core/                              (Shell App)
│   ├── Models/
│   │   ├── ServiceProvider.swift      ← in ServiceProviderCard.swift
│   │   └── Booking.swift              ← in BookingCard.swift
│   │
│   ├── Components/
│   │   ├── ServiceProviderCard.swift  ✅ Platform-agnostic
│   │   └── BookingCard.swift          ✅ Platform-agnostic
│   │
│   └── Screens/
│       └── ConsumerHomeScreen.swift   ✅ Platform-agnostic
│
└── Packages/
    └── CampusCuts/
        ├── Models/
        │   └── Barber.swift           ✅ Platform-specific
        │
        └── Adapters/
            └── CampusCutsAdapter.swift ✅ Converts to ServiceProvider
```

## Questions?

**Q: Why keep platform-specific mocks in shell app?**
A: For development/testing purposes. In production, data comes from actual platform packages. The mocks simulate what those packages would return.

**Q: Should I rename other files too?**
A: Yes! Any file in the shell app that has platform-specific naming should be made generic:
- Detail sheets
- List views
- Navigation screens
- Coordinator logic

**Q: What about the CampusCuts `Barber.swift` file?**
A: Keep it! That's in the CampusCuts package and should be platform-specific. Only shell app files need generic naming.

## Success!

After this migration, your app will have:
- ✅ Clear separation between shell app and platforms
- ✅ Proper naming that reflects architecture
- ✅ Easy scalability for new platforms
- ✅ No confusion about what code belongs where
