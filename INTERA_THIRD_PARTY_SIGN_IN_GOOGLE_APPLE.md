# Intera: Google and Apple third-party sign-in

This document describes how **Sign in with Google** and **Sign in with Apple** work in the Intera consumer app: what the user sees, which platform pieces are required, and how the client exchanges provider tokens for a **CampusCuts** session (JWT access token, optional refresh token).

---

## Summary

| Provider | Client SDK / API | Sent to backend | Backend route (under `AppConfiguration` API root) |
|----------|------------------|-----------------|-----------------------------------------------------|
| **Google** | Google Sign-In for iOS (`GIDSignIn`) | Google **ID token** (JWT string) | `POST …/api/v1/auth/google` — body `{ "idToken": "<jwt>" }` |
| **Apple** | `AuthenticationServices` (`ASAuthorizationAppleIDProvider`) | Apple **identity token** (JWT string) | `POST …/api/v1/auth/apple` — body `{ "identityToken": "<jwt>", … }` |

The app **never** uses the Google or Apple JWT as the Bearer token for CampusCuts APIs. After verification, the server returns the **same style of response as email login** (`success`, `data.accessToken`, optional `data.refreshToken`, `data.user`, etc.). The client persists tokens via `CampusCutsAuthTokenStore` and builds an in-app `UserSession` through `AppSessionManager.login`.

---

## Where sign-in starts in the UI

- **`OAuthProviderSignInSheet.swift`** — Root sheet: **Continue with Apple**, **Continue with Google**, **Continue with email**, and optional **Create account**. Apple can branch into a preflow sheet (create-account path), Apple-only sheet (sign-in path), or password follow-up when the backend indicates `needsPlatformPassword`.
- **`EmailPasswordSignInView.swift`** — Email/password path (not third-party, but shares the same session completion pattern).

---

## Google Sign-In

### User experience

1. User taps **Continue with Google**.
2. The Google SDK presents the system / Google account picker (native UI).
3. After success, the app obtains a **Google ID token**, sends it to the CampusCuts backend, then logs the user in with the returned **CampusCuts access token**.

### Configuration and lifecycle

1. **`GoogleService-Info.plist`** must be in the app bundle with a real **`CLIENT_ID`** (iOS OAuth client from Google Cloud / Firebase). Placeholder values such as `YOUR_IOS_CLIENT_ID` are rejected; configuration fails and interactive sign-in throws `GoogleSignInFlowError.missingConfiguration`.
2. **URL scheme** — The reversed client ID must be registered so Google can return control to the app via the OAuth redirect. The project includes **`GoogleSignInURL.plist`** (URL types) for this.
3. **Launch** — `GoogleSignInAppSupport.configure()` runs from:
   - **`InteraAppDelegate.swift`** — `application(_:didFinishLaunchingWithOptions:)` (UIKit / Firebase startup path).
   - **`InteraApp.swift`** — early in the SwiftUI app lifecycle (covers paths where the delegate is not the sole entry).
4. **OAuth redirect** — **`InteraApp.swift`** uses `.onOpenURL`; **`GoogleSignInAppSupport.handleURL(_)`** forwards matching URLs to `GIDSignIn.sharedInstance.handle(url)`.

### Code flow (`GoogleSignInAppSupport.swift`)

- **`configure()`** — Reads `CLIENT_ID` from `GoogleService-Info.plist`, sets `GIDSignIn.sharedInstance.configuration`.
- **`signInInteractively(sessionManager:)`** — Finds a presenting view controller (iOS) or window content VC (macOS), calls `GIDSignIn.sharedInstance.signIn(withPresenting:)`, then **`completeLogin(with:user:)`**.
- **`completeLogin`** — Reads `user.idToken?.tokenString`, calls **`AuthBackendVerification.verifyGoogleIDTokenAndFetchSessionTokens`**, saves tokens, builds **`UserSession(googleUser:backendToken:…)`**, **`sessionManager.login(session:)`**. On backend failure, calls **`GIDSignIn.sharedInstance.signOut()`** so a bad exchange does not leave a half-linked SDK state.
- **`restorePreviousSignIn`** — If the user previously used Google on this device, the SDK can restore; the app then runs the same backend verification path.

### Backend contract (`AuthBackendVerification.swift`)

- **URL:** `AppConfiguration.urlAuthGoogle` → `…/api/v1/auth/google`.
- **Request:** `POST`, `Content-Type: application/json`, body **`{ "idToken": "<string>" }`**.
- **Response:** Parsed like email login: envelope with `data.accessToken` (or `data.token`), optional refresh fields, optional `data.user` (including `id`, `email`, names, `profile_picture_url`, `needsPlatformPassword` when applicable).

---

## Sign in with Apple

### User experience

1. User taps **Continue with Apple**.
2. Depending on context (e.g. create account vs sign in only), the app may show **`ApplePreflowSignInFlow`** (collects supplemental details where needed) or **`AppleSignInOnlySheet`** (Apple UI only).
3. Apple’s system UI completes; the app receives an **`ASAuthorizationAppleIDCredential`** including an **identity token** (JWT).
4. The app **`POST`s the identity token** (and optional name/email) to CampusCuts, then applies the returned session. If the account has no platform password yet, the UI may prompt for a password step before the flow is finished.

### Apple Developer setup

- **`Intera.entitlements`** includes **`com.apple.developer.applesignin`** with capability **Default** (Sign in with Apple).
- Xcode: enable **Sign In with Apple** for the app target; ensure the App ID matches the provisioning profile.

### Code flow

- **`AppleSignInAppSupport.completeLogin`** — Merges credential and optional prefills (`AppleSignInSupplementStore` for names/email when Apple omits them on later sign-ins). Calls **`AuthBackendVerification.verifyAppleIdentityTokenAndFetchSessionTokens`**, validates resolved email, **`CampusCutsAuthTokenStore.save`**, then **`sessionManager.login`** with the assembled session. Returns a `Bool` indicating whether the user must set a **CampusCuts password** (`needsPlatformPassword`).
- **`AuthBackendVerification.verifyAppleIdentityTokenAndFetchSessionTokens`** — Builds JSON with **`identityToken`**, optional **`firstName`**, **`lastName`**, **`email`** (supplemental). Tries **`AppConfiguration.urlAuthApple`** (`…/api/v1/auth/apple`) first; on **404**, retries **`AppConfiguration.urlAuthAppleLegacy`** (`…/api/auth/apple`) for deployments that only forward the legacy prefix.

### Backend contract

- Same success envelope as Google/email where possible: **`data.accessToken`**, optional refresh token, **`data.user`** (including **`needsPlatformPassword`** for OAuth-only accounts).
- Apple supplies **full name only on the first successful authorization** for that app user; the client passes **`firstName` / `lastName`** in the POST when available so the backend can persist them.

---

## Shared configuration

- **`AppConfiguration.swift`** — Builds absolute URLs from the API base (e.g. **`pathAuthGoogle`**, **`pathAuthApple`**, **`pathAuthMe`**). All third-party exchanges use these URLs, not hard-coded hosts in feature code.
- **`CampusCutsAuthTokenStore`** — Persists access (and refresh when provided) tokens after any successful OAuth-backed login.
- **`ProductionLogging`** — Non-fatal logging on verification failures (e.g. `area: auth_google`).

---

## Troubleshooting (short)

| Symptom | Likely cause |
|---------|----------------|
| Google: “not configured” / missing plist | Missing or placeholder **`GoogleService-Info.plist`** / **`CLIENT_ID`**. |
| Google: redirect does nothing | **URL scheme** (reversed client ID) not in the built target’s URL types. |
| Apple: capability errors in Xcode | **Sign In with Apple** not enabled on App ID / entitlements out of sync. |
| Both: HTTP **404** on verify | Backend **`POST /api/v1/auth/google`** or **`/auth/apple`** not deployed or wrong base URL in `AppConfiguration`. Apple client will try legacy **`/api/auth/apple`** after 404. |
| APIs **401** after “sign in” | Client must use **CampusCuts JWT** from the auth response, **not** the raw Google/Apple token (see comments in **`AuthBackendVerification.swift`**). |

---

## Primary source files

| File | Role |
|------|------|
| `Intera/Intera/OAuthProviderSignInSheet.swift` | Provider pills, navigation to email, Apple sheets/dialogs, Google `Task` sign-in. |
| `Intera/Intera/GoogleSignInAppSupport.swift` | GID configuration, interactive sign-in, URL handling, session mapping. |
| `Intera/Intera/AppleSignInAppSupport.swift` | Apple credential → backend → `sessionManager.login`, password-needed flag. |
| `Intera/Intera/ApplePreflowSignInFlow.swift` | Create-account-oriented Apple flow and related UI. |
| `Intera/Intera/AuthBackendVerification.swift` | HTTP POST to `/auth/google` and `/auth/apple`, JSON parsing. |
| `Intera/Intera/AppConfiguration.swift` | Auth URL construction, Apple legacy fallback URL. |
| `Intera/Intera/InteraApp.swift` | `onOpenURL` → Google; `GoogleSignInAppSupport.configure()`. |
| `Intera/Intera/InteraAppDelegate.swift` | Launch-time `GoogleSignInAppSupport.configure()`. |
| `Intera/Intera/Intera.entitlements` | Sign in with Apple capability. |
| `Intera/GoogleService-Info.plist` | Google `CLIENT_ID` (and related Firebase metadata as used by the project). |
| `Intera/GoogleSignInURL.plist` | URL scheme for OAuth return to the app. |

Backend route implementations live in the **CampusCuts** server package (e.g. `POST /api/v1/auth/google`, `POST /api/v1/auth/apple`); see repository docs or `INTERA_PROVIDER_BACKEND_AND_REALTIME_APPENDIX.md` for API context where applicable.
