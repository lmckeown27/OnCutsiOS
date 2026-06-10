# Beauty Specialist Mock Data

This document describes the mock beauty specialist data created for the Intera/CampusCuts app.

## Overview

I've created comprehensive mock data for beauty service providers to expand beyond just barbers. The data is organized in `MockBeautySpecialists.swift`.

## Beauty Specialists Included

### 1. **Glam by Maya** (ID: 201)
- **Service**: Makeup Artist
- **Specialty**: Bridal, special events, photo shoots
- **Rating**: 4.9 ⭐ (87 reviews)
- **Status**: Available Now ✅
- **Completed Bookings**: 156

### 2. **Salon Sophia** (ID: 202)
- **Service**: Hair Stylist (Women's)
- **Specialty**: Cuts, color, balayage, extensions
- **Rating**: 4.8 ⭐ (142 reviews)
- **Status**: Busy
- **Completed Bookings**: 289

### 3. **Nailed It by Jasmine** (ID: 203)
- **Service**: Nail Technician
- **Specialty**: Manicures, pedicures, gel nails, nail art
- **Rating**: 4.7 ⭐ (98 reviews)
- **Status**: Available Now ✅
- **Completed Bookings**: 203

### 4. **Clear Skin Co.** (ID: 204)
- **Service**: Esthetician
- **Specialty**: Facials, chemical peels, skincare consultations
- **Rating**: 5.0 ⭐ (64 reviews)
- **Status**: Busy
- **Completed Bookings**: 112

### 5. **Perfect Brows by Nina** (ID: 205)
- **Service**: Brow Specialist
- **Specialty**: Shaping, tinting, lamination, microblading
- **Rating**: 4.9 ⭐ (76 reviews)
- **Status**: Available Now ✅
- **Completed Bookings**: 134

### 6. **Lash Luxe** (ID: 206)
- **Service**: Lash Extension Artist
- **Specialty**: Classic, hybrid, volume sets, lash lifts
- **Rating**: 4.8 ⭐ (91 reviews)
- **Status**: Available Now ✅
- **Completed Bookings**: 187

### 7. **Smooth Skin Studio** (ID: 207)
- **Service**: Waxing Specialist
- **Specialty**: Full body waxing, Brazilian specialist
- **Rating**: 4.6 ⭐ (54 reviews)
- **Status**: Busy
- **Completed Bookings**: 97

### 8. **Zen Touch Massage** (ID: 208)
- **Service**: Massage Therapist
- **Specialty**: Deep tissue, Swedish, sports massage
- **Rating**: 4.9 ⭐ (118 reviews)
- **Status**: Busy
- **Completed Bookings**: 245

### 9. **Braids by Keisha** (ID: 209)
- **Service**: Hair Braiding Specialist
- **Specialty**: Box braids, cornrows, protective styles
- **Rating**: 5.0 ⭐ (143 reviews)
- **Status**: Available Now ✅
- **Completed Bookings**: 221

### 10. **Beauty Bar by Alex** (ID: 210)
- **Service**: Multi-Service Beauty Pro
- **Specialty**: Hair, makeup, nails, and brows
- **Rating**: 4.7 ⭐ (109 reviews)
- **Status**: Available Now ✅
- **Completed Bookings**: 178

## Mock Services

The file includes 22 different beauty services covering:

- **Makeup**: Event makeup, natural glam
- **Hair Styling**: Cuts, coloring, balayage
- **Nails**: Gel manicures, spa pedicures, nail art
- **Skincare**: Custom facials, acne treatments
- **Brows**: Shaping, tinting, lamination
- **Lashes**: Classic sets, volume sets, lifts
- **Waxing**: Brazilian, facial waxing
- **Massage**: Deep tissue, Swedish
- **Braiding**: Knotless box braids, cornrows, feed-in braids
- **Packages**: Event packages, bridal packages

Price range: $35 - $350
Duration range: 30 minutes - 6 hours

## Mock Bookings

Includes 4 sample beauty service bookings:
1. Upcoming event makeup appointment
2. Upcoming lash extension appointment  
3. Completed gel manicure
4. Completed braiding service

## Usage

### In Your Code

```swift
// Show only beauty specialists
@State private var providers: [Barber] = Barber.beautyMocks

// Show only original barbers
@State private var providers: [Barber] = Barber.mocks

// Show all service providers (barbers + beauty)
@State private var providers: [Barber] = Barber.allMocks
```

### Current Implementation

Both `ConsumerHomeScreen` and `UnifiedProviderHomeScreen` in `ScreensConsumerHome.swift` have been updated to use `Barber.beautyMocks` by default.

## Data Structure

All mock data follows the existing `Barber` model structure:
- Uses realistic IDs (200+ range to avoid conflicts)
- Includes profile images from pravatar.cc (placeholder service)
- Has varied ratings, review counts, and availability status
- All linked to State University (campusId: 1)

## Benefits

1. **Diverse Testing**: Test UI with different service types
2. **Realistic Data**: Names, bios, and services feel authentic
3. **Category Testing**: When implementing category filters
4. **Pricing Variety**: Services range from quick/cheap to long/premium
5. **Availability Mix**: Some available now, some busy
6. **Rating Variety**: Mix of ratings from 4.6 to 5.0 stars

## Future Enhancements

Consider adding:
- Category/service type field to the Barber model
- Portfolio images for beauty specialists
- Service packages and bundles
- Time-based availability schedules
- Location/address information
- Specialty tags or badges
