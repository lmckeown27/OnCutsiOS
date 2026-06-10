# Intera (consumer) — product, UI/UX, and CampusCutsPackage integration

This document describes the **shipping Intera iOS app** today: purpose, major flows, UI/UX patterns, backend contracts, and how **`CampusCutsPackage`** (`CampusCutsModule` + `Core`) fits in. Use it as direction for a **Provider (barber) companion app** that shares the same **CampusCuts** backend and optionally the same Swift packages.

---

## 1. What Intera is

**Intera** is a **consumer-facing** iOS app for **requesting and managing on-site services** (hair, nails, etc.) from **providers** listed on the **CampusCuts** platform. It is not the barber dashboard; it is the **student / consumer** shell.

**Primary jobs-to-be-done**

1. **Discover** providers near the user (or full list), filter by service category, search by name.
2. **Book** a service (intake → confirmation) against the CampusCuts **`bookings-simple`** API.
3. **Message** providers in a booking-linked chat; real-time updates via **Socket.IO**.
4. **Track bookings** on a unified timeline (pending → accepted → completed → paid).
5. **Pay** after the provider marks the booking **completed** (Stripe **PaymentSheet**, optional **Apple Pay**, cash path).
6. **Account**: profile (name, photo, optional platform password), sign-in with **Apple / Google / email**, push notifications.

**Backend / brand context**

- API root is configured as **`https://campuscut.com/api/v1`** (see `AppConfiguration` in the Intera target). Same deployment as the CampusCuts web app (`VITE_API_URL=/api/v1` pattern).
- Intera uses **JWT** (`Authorization: Bearer …`) from CampusCuts auth (`/auth/apple`, `/auth/google`, email login, register).

**Roles (in app today)**

- `RootView` routes **`UserRole.student`** to the **unified consumer home** (`UnifiedProviderHomeScreen` / `ScreensConsumerHome` — naming is legacy; behavior is **consumer**).
- **`UserRole.barber`** and **`.admin`** route to **`MainTabView`** (older shell); most product effort is on the **student** path.

The **Provider app** you build would mirror **barber** workflows (accept/reject, mark complete, earnings, schedule) against the **same** APIs the backend already exposes for barbers—Intera consumer code is the reference for **auth, sockets, messages, bookings-simple, Stripe**.

---

## 2. Architecture (high level)

| Layer | Responsibility |
|--------|----------------|
| **Intera app target** | SwiftUI UI, `AppSessionManager`, coordinators, `ChatViewModel`, booking/messaging/payment API wrappers, OAuth sheets, push, design system (`Color.oliveGreen`, lava background, glass chrome). |
| **`CampusCutsModule`** (SPM) | Shared **models** (`ServiceProvider`), **auth helpers** (`CampusCutsAuthTokenStore`, sign-up flows), **messaging** (`CampusCutsChatManager`), **legal**, **ServiceType** filter enum, **live-data banner**, sample **CampusCutsHomeView** / **BarberDashboardView** (shell demos—not the main Intera consumer UI). |
| **`Core`** (SPM) | **Stripe** integration: `CheckoutViewModel`, `BookingCheckoutViewModel`, `StripeManager`, `Bundle+StripeConfig`, Apple Pay coordinator pieces; depends on **StripePaymentSheet** / **StripeApplePay**. |

**Session bridge**

- `CampusCutsSessionSync.appSessionManager` is set from `RootView` so package code that needs the shell session can reach **`AppSessionManager`** (see `CoreUserSessionProtocol` / `CampusCutsSessionSync.swift`).

---

## 3. UI / UX (consumer Intera)

### 3.1 Visual language

- **Olive green** brand (`Color.oliveGreen`, hex `5A7268` in `DesignSystemColors`) for primary actions, accents, tab selection.
- **“Lava lamp”** animated background on iOS (`InteraLavaLampBackground`) behind main chrome.
- **Glass** materials: ultra-thin material capsules, strokes, cream/off-white text on browse (`BookingSelectorTheme.cream`, hub cream `#F5F5DC`).
- **Hub navigation** (`ConsumerStickyHubBar`): four segments in a **Mercury pill** — **Home** (`house.fill`), **Messages** (`bubble.left.and.bubble.right.fill`), **Bookings** (`calendar.badge.clock`), **Profile** (`person.fill`). Swipeable `TabView` synced to scroll offset for the bubble.
- **iOS 26+** optional liquid-glass-style browse header (`GlassHeaderProviderBrowse`); pre-26 fallback paths exist.

### 3.2 Information architecture (authenticated consumer)

1. **Home** — Provider grid/cards (`ServiceProviderCard`), category tags (`ServiceType`), distance preference, search. Tapping a provider opens booking / detail flows.
2. **Messages** — Inbox + `MessagingConversationView`; threads tied to bookings; Socket for `new-message`.
3. **Bookings** — `ConsumerBookingsHubView`: timeline of **`GET /bookings-simple?role=consumer`** rows; navigation to detail, live booking, cancel, chat.
4. **Profile** — `UserProfileView`: avatar (`LiquidProfileUpload` + `AvatarView`), name/email, integrated account (privacy, terms, sign out), optional password flows.

### 3.3 Auth UX

- Guest / sign-in entry leads to **`OAuthProviderSignInSheet`**: **Sign in with Apple** (Create account vs Sign In confirmation), **Google**, **Continue with Email** → `EmailPasswordSignInView`.
- Apple flows use **`ApplePreflowSignInFlow`** (name → `@icloud.com` email → password → Apple authorization) for create-account guideline alignment; **`AppleSignInAppSupport`** posts identity token to **`POST /auth/apple`**.
- Integrated email sign-up can be launched from **`IntegratedSignUpBootstrap`** / `LiquidGlassSignupFlow` (package-driven registry).

### 3.4 Payments UX

- When the **provider completes** the service, consumer may receive **`booking-completed`** (Socket) and/or push; **`ChatViewModel.syncPaymentTakeover`** surfaces **`ConsumerPaymentTakeoverView`** (full-screen).
- Takeover: tip presets, **Stripe PaymentSheet** (card), **Apple Pay** (`PKPaymentButton` + `Core.CheckoutViewModel`), **cash** confirm path; server endpoints under **`/bookings-simple/:id/...`**.

### 3.5 Notable UX behaviors

- Hub bar **hidden** while browse search focused, profile name fields focused, or certain navigation stacks deep—avoids keyboard / layout fights.
- **Pull-to-refresh** on browse may use a custom wheel when system spinner is under glass overlays.
- **Haptics** on hub taps and sign-in pills (`SignInPopupPhysicalPressModifier`).

---

## 4. Backend surface (consumer-relevant)

All paths are relative to **`{API_ROOT}/api/v1`** (e.g. `https://campuscut.com/api/v1`).

| Area | Typical endpoints (non-exhaustive) |
|------|-----------------------------------|
| **Auth** | `POST /auth/apple`, `POST /auth/google`, email register/login, `GET /auth/me` (needs platform password flags). |
| **Providers** | `GET /barbers` (lat/lng/maxDistance optional), `GET /barbers/:id`, legacy fallback `GET /providers/list`. |
| **Bookings** | `GET /bookings-simple?role=consumer`, `GET /bookings-simple/:id`, `POST` create, `PUT` updates, `DELETE` cancel, complete → payment intents `…/create-payment-intent`, `…/confirm-payment`, cash `…/pay`. |
| **Stripe config** | `GET …/stripe/client-config` (and alias via bookings-simple path in app). |
| **Messages** | REST for threads/history + **Socket.IO** on **origin** host (not `/api/v1`) for `new-message`, `booking-completed`, etc. |
| **Profile** | User profile APIs, avatar upload, `setInitialPassword` / `auth/me` for platform password. |
| **Push** | `POST /notifications/register-device`, unregister on logout. |

The **Provider app** should use the same root URL, **`role=barber`** (or whatever the backend defines) on **`bookings-simple`**, and barber-specific routes your server already exposes (dashboard, availability—some exist in **`BarberDashboardViewModel`** inside the package as reference).

---

## 5. `CampusCutsPackage` contents (what to reuse)

**Products** (`Package.swift`):

- **`CampusCutsModule`** — no Stripe dependency; safe for UI + auth + models shared with a provider app if you avoid pulling Stripe into that target.
- **`Core`** — Stripe + checkout; link only on targets that pay out or take card.

**`CampusCutsModule` highlights** (`ios-module/Sources/CampusCutsModule/`)

- **`ServiceType`**: public enum for toolbar categories (`.barber`, `.makeup`, …) with `toolbarTitle`, `systemImageName`.
- **`ServiceProvider`**: public model used by Intera cards and `ProviderViewModel` decoders (check `ServiceProviderCard` / decode extensions in Intera).
- **Auth**: `CampusCutsAuthService`, `CampusCutsSignUpView`, `CampusCutsSignUpAPI`, `CampusCutsAuthTokenStore` (keychain-like token storage used with `AppSessionManager`).
- **Messaging**: `CampusCutsChatManager` (Intera also uses bespoke `MessagingView` / `ChatViewModel` wired to same backend).
- **Legal**: `CampusCutsLegal`.
- **Views**: `CampusCutsHomeView`, `ConsumerHomeView`, `BarberDashboardView` — **reference / optional**; Intera’s real consumer shell is **`ScreensConsumerHome`** + hub.

**`Core` highlights** (`ios-module/Sources/Core/`)

- **`CheckoutViewModel`**: builds Stripe **PaymentSheet** with Apple Pay when `Bundle.StripeConfig.applePayMerchantId` is set; uses **`POST …/bookings-simple/:id/create-payment-intent`**.
- **`BookingCheckoutViewModel`**, **`BookingCheckoutView`**, **`StripeManager`**, **`StandaloneBookingApplePayCoordinator`**.
- **`Bundle+StripeConfig`**: reads **`StripePublishableKey`**, **`StripeApplePayMerchantId`**, **`StripeApplePayMerchantCountryCode`** from the **host app Info.plist** (Intera injects these from `GoogleSignInURL.plist` + `StripeKeys.xcconfig`).

For a **Provider app**, you may still need **`Core`** if providers collect **deposits** or **payouts** through the same Stripe Connect story; otherwise you might depend only on **`CampusCutsModule`** plus your own networking.

---

## 6. How Intera wires `CampusCutsModule` and `Core`

**Imports (representative)**

- `import CampusCutsModule` — session, `ServiceType`, `ServiceProvider`, sign-up, legal, chat manager, live banner, `UserRole`-related types, Google/OAuth helpers where bridged.
- `import Core` — `Bundle.StripeConfig`, `CheckoutViewModel` / payment types from **`ConsumerPaymentTakeoverView`**, **`InteraApp`** Stripe bootstrap (`StripeService.applyPublishableKeyAlignedWithAPIHost`), **`AppConfiguration`** (iOS Stripe publishable key).

**Key files to read in-repo**

| File | Purpose |
|------|---------|
| `InteraApp.swift` | Stripe key alignment at launch; deep links (Google, Stripe). |
| `RootView.swift` | Auth gating, role switch, `ChatViewModel`, payment/review full-screen covers, `CampusCutsSessionSync`. |
| `ScreensConsumerHome.swift` | Hub `TabView`, browse, messages, bookings, profile shell. |
| `ProviderViewModel.swift` | Loads providers from `/barbers` + fallback `/providers/list`. |
| `GlassHeaderProviderBrowse.swift` | Collapsing glass header + profile avatar button. |
| `OAuthProviderSignInSheet.swift` | Apple / Google / email entry. |
| `ChatViewModel.swift` | Socket + bookings refresh + payment takeover state. |
| `ConsumerPaymentTakeoverView.swift` | Tips + PaymentSheet + Apple Pay + cash. |
| `AppConfiguration.swift` | API root, URL builders, socket origin. |
| `CampusCutsPackage/Package.swift` | SPM products and Stripe dependency on `Core`. |

---

## 7. Direction for the **Intera Provider** app (Claude / engineering)

1. **Same backend** as Intera consumer: one **`apiV1Root`**, same JWT from same auth endpoints; use **`UserRole.barber`** (or server’s barber user type) consistently.
2. **Reuse `CampusCutsModule`** for **`ServiceType`**, tokens, optional sign-up/legal; consider reusing **`BarberDashboardViewModel`** patterns or replacing with native provider UX.
3. **Reuse `Core`** only if the provider app confirms payments or uses PaymentSheet with the same **`bookings-simple`** Stripe pipeline.
4. **Mirror real-time**: same **Socket.IO** origin + barber-relevant events (new booking, message, status changes).
5. **Parity lists**: `GET /bookings-simple?role=barber` (confirm query param with backend), barber profile endpoints, complete/mark-paid flows your server defines.
6. **Design**: either **match** Intera (olive + glass + hub patterns) for a unified brand, or diverge deliberately—but document tokens if you share marketing.
7. **App Store**: provider app will still need its **own** App Store listing, capabilities (push, Apple Pay if used), and **Review Notes** / demo barber account with seeded bookings + messages.

---

## 8. Glossary

| Term | Meaning |
|------|---------|
| **CampusCuts** | Backend + web brand; hosts `/api/v1` and Socket.IO. |
| **Intera** | Consumer iOS app in this repo. |
| **Provider / barber** | Service seller; Provider app target user. |
| **`bookings-simple`** | Primary booking API surface used by Intera consumer flows. |
| **`UnifiedProviderHomeScreen`** | Misleading name: **consumer** home in current routing. |

---

## 9. Revision

- Document generated from repository layout and key source files as of the workspace snapshot. Update **`AppConfiguration.apiV1RootURLString`** and endpoint tables if you add staging environments.

## 10. Provider build — backend & socket appendix

A **curated** route table, **`users.id` vs `barbers.id`**, **`GET /bookings-simple` role behavior**, **socket room + event catalog** (from `CampusCutsPackage/backend` + Intera `MessagingRealtime.swift`), and **product checklists** live in:

**[`INTERA_PROVIDER_BACKEND_AND_REALTIME_APPENDIX.md`](./INTERA_PROVIDER_BACKEND_AND_REALTIME_APPENDIX.md)**

Paste that file together with this spec for Claude when scaffolding the Provider app.

When pasting into Claude for the Provider app, add: **OpenAPI** (if you publish one) and any **staging URLs** not yet in repo.
