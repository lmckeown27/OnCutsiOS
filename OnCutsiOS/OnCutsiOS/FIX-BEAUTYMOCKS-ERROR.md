# Fix: Invalid Redeclaration of 'beautyMocks'

## The Problem

You're seeing this error because `beautyMocks` is declared in multiple files:

1. ✅ `ComponentsBarberCard.swift` - Has `ServiceProvider.beautyMocks`
2. ✅ `ComponentsBookingCard.swift` - Has `Booking.beautyMocks`  
3. ❌ `MockBeautySpecialists 2.swift` - Should be deleted (but still exists in your project)
4. ❌ `MockBeautySpecialists.swift` - Might also exist (without the "2")

**These are actually DIFFERENT declarations**:
- `ServiceProvider.beautyMocks` - Array of service providers
- `Booking.beautyMocks` - Array of bookings

They shouldn't conflict, but if the old `MockBeautySpecialists` file(s) exist, they're trying to redeclare them.

## The Solution

### Step 1: Find All MockBeautySpecialists Files

In Xcode's Project Navigator (left sidebar):
1. Look for any files named:
   - `MockBeautySpecialists.swift`
   - `MockBeautySpecialists 2.swift`
   - Any variation with numbers or spaces

### Step 2: Delete Them All

For each file found:
1. Right-click on the file
2. Select **"Delete"**
3. In the dialog that appears, choose **"Move to Trash"** (NOT "Remove Reference")
4. This ensures the file is completely gone from your project

### Step 3: Clean Build Folder

After deleting:
1. In Xcode menu: **Product → Clean Build Folder** (Shift + Cmd + K)
2. Wait for it to complete
3. Then build again: **Product → Build** (Cmd + B)

### Step 4: Verify the Fix

After building, you should see:
- ✅ No more "Invalid redeclaration" errors
- ✅ App compiles successfully
- ✅ Mock data still works (it's now in the component files)

## Understanding the File Structure

Here's where mock data lives NOW (after migration):

```
ComponentsBarberCard.swift
├── ServiceProvider (model)
├── ServiceProviderCard (UI component)
└── Mock Data:
    ├── ServiceProvider.mocks (2 barbers)
    ├── ServiceProvider.beautyMocks (10 beauty specialists) ← HERE
    └── ServiceProvider.allMocks (all 12 combined)

ComponentsBookingCard.swift
├── Booking (model)
├── BookingCard (UI component)
└── Mock Data:
    ├── Booking.mocks (3 barber bookings)
    └── Booking.beautyMocks (4 beauty bookings) ← HERE
```

## Why Two Different beautyMocks?

They're in different types, so they don't conflict:

```swift
// In ComponentsBarberCard.swift
struct ServiceProvider {
    static let beautyMocks: [ServiceProvider] = [...]  // WHO provides services
}

// In ComponentsBookingCard.swift  
struct Booking {
    static let beautyMocks: [Booking] = [...]  // WHEN services happen
}
```

Think of it like this:
- **ServiceProvider.beautyMocks** = List of beauty specialists you can book
- **Booking.beautyMocks** = List of appointments with beauty specialists

## File Comparison Table

| File | Purpose | Contains | Status |
|------|---------|----------|--------|
| `ComponentsBarberCard.swift` | Service provider UI & data | `ServiceProvider` model, `ServiceProviderCard` component, provider mocks | ✅ Keep |
| `ComponentsBookingCard.swift` | Booking UI & data | `Booking` model, `BookingCard` component, booking mocks | ✅ Keep |
| `MockBeautySpecialists 2.swift` | OLD mock data file | Empty placeholder | ❌ Delete |
| `MockBeautySpecialists.swift` | OLD mock data file | Might have duplicate mocks | ❌ Delete if exists |

## Still Seeing Errors?

### Check for Hidden Files

Sometimes Xcode has files that aren't visible in the navigator:

1. In Finder, navigate to your project folder
2. Look in: `YourProject/YourProject/` directory
3. Search for files starting with "Mock"
4. Delete any `MockBeautySpecialists` files you find
5. Return to Xcode and clean build folder

### Nuclear Option: Remove from .pbxproj

If files won't delete:

1. Close Xcode
2. In Finder, right-click on `YourProject.xcodeproj`
3. Select "Show Package Contents"
4. Open `project.pbxproj` in a text editor
5. Search for "MockBeautySpecialists"
6. Delete any lines containing that filename
7. Save and reopen in Xcode

⚠️ **Caution**: Only do this as a last resort, and make a backup first!

## Expected Result

After deletion and clean build:

```swift
// This should work without errors:
let providers = ServiceProvider.beautyMocks  // ✅ 10 beauty specialists
let bookings = Booking.beautyMocks           // ✅ 4 beauty bookings

// Used in UI like this:
ForEach(ServiceProvider.beautyMocks) { provider in
    ServiceProviderCard(provider: provider)
}

ForEach(Booking.beautyMocks) { booking in
    BookingCard(booking: booking)
}
```

## Need More Help?

If you're still seeing the error after deleting the files:
1. Take a screenshot of the error message
2. Take a screenshot of your Project Navigator (showing all files)
3. The error message will tell you exactly which file has the duplicate

The error typically shows as:
```
Invalid redeclaration of 'beautyMocks'
/path/to/YourFile.swift:LineNumber
```

This tells you which specific file is causing the problem.
