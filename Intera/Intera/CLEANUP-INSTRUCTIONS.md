# CLEANUP INSTRUCTIONS: Remove Duplicate Files

## The Problem

You have duplicate `ServiceProvider` definitions in your project causing "ambiguous type" errors:

1. ✅ **`ServiceProviderCard.swift`** - NEW, properly named, with 5+5 mocks
2. ❌ **`ComponentsBarberCard.swift`** - OLD, incorrectly named, causes conflicts
3. ❌ **`MockBeautySpecialists 2.swift`** - OLD, empty file, not needed
4. ❌ **`MockBeautySpecialists.swift`** - OLD, may still exist, not needed

## What to Delete from Xcode

**Delete these 3 files:**

### 1. Delete `ComponentsBarberCard.swift`
- This is the old file with improper naming
- Contains duplicate `ServiceProvider` definition
- Has been replaced by `ServiceProviderCard.swift`

### 2. Delete `MockBeautySpecialists 2.swift`
- Empty placeholder file
- Mock data now in `ServiceProviderCard.swift`
- Not needed anymore

### 3. Delete `MockBeautySpecialists.swift` (if it exists)
- Another old mock data file
- Mock data now in `ServiceProviderCard.swift`  
- Not needed anymore

## How to Delete

For EACH file above:

1. Find the file in Xcode's Project Navigator (left sidebar)
2. Right-click on the file
3. Select **"Delete"**
4. In the dialog, choose **"Move to Trash"** (NOT "Remove Reference")
5. Click Delete

## After Deletion

1. **Clean Build Folder**: Product → Clean Build Folder (Shift + Cmd + K)
2. **Build**: Product → Build (Cmd + B)
3. **Verify**: All errors should be gone

## What You Should Have

### ✅ Keep These Files

**`ServiceProviderCard.swift`** - Contains:
- `ServiceProviderCard` (UI component)
- `ServiceProvider` (model)
- 5 haircut provider mocks
- 5 beauty specialist mocks
- Total: 10 mock providers

**Mock Providers:**

**Haircut Providers (5):**
1. Jordan's Cuts
2. Alex's Barbershop  
3. Elite Cuts by Marcus
4. Fresh Fades Studio
5. The Gentleman's Cut

**Beauty Specialists (5):**
1. Maya Chen (Makeup Artist)
2. Sophia Rodriguez (Hair Stylist)
3. Jasmine Torres (Nail Technician)
4. Victoria Lee (Lash Specialist)
5. Keisha Washington (Braiding Specialist)

### Mock Data Usage

```swift
// Haircut providers
ServiceProvider.haircutMocks  // 5 providers

// Beauty specialists
ServiceProvider.beautyMocks   // 5 providers

// All providers
ServiceProvider.allMocks      // 10 providers total

// For backward compatibility
ServiceProvider.mocks         // Same as haircutMocks
```

## Expected Results

After cleanup:

✅ No more "ServiceProvider is ambiguous" errors  
✅ No more "Invalid redeclaration" errors  
✅ App builds successfully  
✅ 5 haircut + 5 beauty = 10 total mock providers  
✅ Clean, maintainable codebase  

## File Structure After Cleanup

```
Intera/
├── Core/
│   └── Components/
│       ├── ServiceProviderCard.swift        ✅ KEEP
│       └── BookingCard.swift                ✅ KEEP
│
├── Screens/
│   └── ConsumerHomeScreen.swift             ✅ KEEP
│
├── Adapters/
│   └── CampusCutsAdapter.swift             ✅ KEEP
│
└── Packages/
    └── CampusCuts/
        └── Barber.swift                     ✅ KEEP (different model)
```

## Verification Checklist

After deleting files and building:

- [ ] `ComponentsBarberCard.swift` deleted
- [ ] `MockBeautySpecialists 2.swift` deleted  
- [ ] `MockBeautySpecialists.swift` deleted (if it existed)
- [ ] Clean build folder completed
- [ ] Project builds without errors
- [ ] `ServiceProviderCard.swift` exists and compiles
- [ ] Can see 5 haircut mocks in code
- [ ] Can see 5 beauty mocks in code
- [ ] Previews work in Xcode

## If You Still See Errors

### "Cannot find ServiceProvider"
- Make sure `ServiceProviderCard.swift` is added to your target
- Check that the file is in your Xcode project (not just Finder)

### "ServiceProvider is ambiguous"
- A duplicate file still exists
- Search your project for "struct ServiceProvider"
- Delete any files other than `ServiceProviderCard.swift` that define it

### "Invalid redeclaration of beautyMocks"
- `MockBeautySpecialists` files still exist
- Search project for "beautyMocks"
- Delete old mock files

## Still Stuck?

1. Close Xcode
2. In Finder, go to your project folder
3. Search for files containing "ServiceProvider"
4. Delete any duplicates manually
5. Reopen Xcode
6. Clean build folder
7. Build

---

## Summary

**Delete:** 3 old files  
**Keep:** 1 new file (`ServiceProviderCard.swift`)  
**Result:** Clean architecture with 5+5 mock providers  

Once you delete the old files and build, everything should work perfectly! 🎉
