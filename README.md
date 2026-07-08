# OnCuts

**OnCuts** is a marketplace for booking local services (starting with grooming on campus). This repository contains the **consumer iOS host app** and the shared **OnCutsPackage** monorepo (API, web, Swift module).

- Product site: [oncuts.com](https://oncuts.com)
- Support: support@oncuts.com

---

## Repository layout

```
OnCutsiOS/              Consumer iOS app (Xcode project + OnCutsiOS target)
OnCutsPackage/          Backend, web app, and OnCutsModule Swift package
LICENSE
```

### OnCutsiOS (consumer app)

| Item | Value |
|------|--------|
| Xcode project | `OnCutsiOS/OnCutsiOS.xcodeproj` |
| Scheme / target | **OnCutsiOS** |
| User-facing name | **OnCuts** (home screen, in-app copy) |
| Swift module import | `import OnCutsModule` |
| Production API | `https://oncuts.com/api/v1` (`AppConfiguration.swift`) |

Open `OnCutsiOS/OnCutsiOS.xcodeproj` in Xcode and run the **OnCutsiOS** scheme on an iOS 17+ simulator or device.

```bash
cd OnCutsiOS
xcodebuild -scheme OnCutsiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### OnCutsPackage

| Item | Value |
|------|--------|
| Swift package | `OnCutsPackage/Package.swift` |
| iOS module product | **OnCutsModule** |
| Shared checkout target | **Core** (Stripe PaymentSheet) |
| Backend | `OnCutsPackage/backend/` (Node / Express) |
| Web app | `OnCutsPackage/web-app/` |

The host app links **OnCutsModule** as a local Swift package (`../OnCutsPackage`).

---

## Architecture (three layers)

```
OnCuts (product brand — App Store display name, web, legal)
    └── OnCutsModule (Swift package — booking, auth, browse API client)
            └── OnCutsiOS (Xcode host — shell UI, lava booking flow, messaging)
```

---

## App identity (intentionally legacy)

User-facing branding is **OnCuts**. Some **platform identifiers** are unchanged so existing App Store, Stripe, and Keychain data keep working:

| Setting | Current value |
|---------|----------------|
| Bundle ID | `Liam.Intera` |
| URL scheme (Stripe return) | `campuscuts://` |
| Apple Pay merchant | `merchant.com.liammckeown.Intera` |
| Keychain service keys | `com.campuscuts.*` |

Renaming these requires a coordinated migration in Apple Developer, Stripe, and App Store Connect — not a code-only change.

---

## Requirements

- Xcode 16+ (iOS 17 deployment target)
- macOS 14+ for local backend tooling (see `OnCutsPackage/Makefile`)
- Node.js 18+ for backend / web development

---

## Development pointers

- **Branding constants:** `OnCutsiOS/OnCutsiOS/AppBranding.swift`
- **API base URL:** `OnCutsiOS/OnCutsiOS/AppConfiguration.swift`
- **Stripe keys (gitignored):** `OnCutsiOS/Config/StripeKeys.secret.xcconfig` (see `StripeKeys.xcconfig.example`)
- **Google Sign-In / Info.plist merge:** `OnCutsiOS/GoogleSignInURL.plist`

For backend and web setup, use the scripts and compose files under `OnCutsPackage/` (`Makefile`, `docker-compose.yml`).

---

## License

See [LICENSE](LICENSE).
