# Intera: Lava lamp background (design + implementation)

This document describes the **lava lamp** animated backdrop used across the Intera **consumer** experience on **iOS**: what it looks like, how it is built in SwiftUI, how it stays visually consistent with navigation and the hub shell, and how foreground **shell cream** colors keep typography readable on top of it.

---

## Role in the product

The lava lamp is the **default ambient background** for signed-in and many full-screen consumer flows on iOS. It reinforces a single **olive / gold** brand atmosphere (warm yellows and greens over a deep midnight base) while staying in **slow, continuous motion** so the shell feels alive without distracting from content.

Foreground UI is tuned for **high contrast on that wash**: primary copy and many icons use **`Color.lavaShellCream`** and stepped opacities (`Secondary`, `Tertiary`) defined in the design system so lists, headers, and glass-style chrome stay legible.

---

## Core implementation: `InteraLavaLampBackground`

**File:** `Intera/Intera/InteraLavaLampBackground.swift`

### Visual stack

1. **Midnight base** — Solid `Color(red: 0.04, green: 0.05, blue: 0.12)`, aligned with the mesh palette’s **midnight** anchor in `InteraLiquidGlass.swift` so switching between “lava shell” and “mesh” surfaces does not jump to a different black.

2. **Angular gradient “waves”** — An `AngularGradient` built from a dense `Gradient` of **green**, **yellow**, **deep yellow**, and a **blend** stop between them (no muddy grey between hues). The gradient repeats around the center so each direction around the screen cycles green ↔ yellow.

3. **Dual phase + blend modes** — Two copies of the same angular layer are stacked:
   - Same rotation on both, but the second is offset by **180°**.
   - Each uses `.blendMode(.plusLighter)` so peaks add light.
   - The pair is then **blurred** (`blur(radius: 60)`), composited with `.blendMode(.screen)` at **0.86** opacity. The intent (per inline comments) is **concurrent yellow and green regions** without corners collapsing to “all yellow” or “all green.”

4. **Scale** — The gradient layer is scaled up (`scaleEffect(2.35)`) so soft edges fill the viewport after blur.

### Motion

- **`TimelineView(.animation(minimumInterval: 1.0 / 30.0))`** drives updates on iOS when **Reduce Motion** is off.
- Rotation angle is derived from wall-clock time: **one full 360° drift every 92 seconds** (`rotationPeriodSeconds`), so the pattern slowly rotates.

### Accessibility

- When **`accessibilityReduceMotion`** is true, animation is skipped: a **static** `lavaStack(rotation: 48)` is shown instead of the timeline-driven rotation.

### Interaction

- The view uses **`.allowsHitTesting(false)`** and **`.ignoresSafeArea()`** so it acts purely as a backdrop.

---

## Hub shell: shared backdrop + scrim

**`InteraHubTabShellBackground`** (same file) wraps the **paged consumer hub** (Home / Messages / Bookings / Profile swipe):

| Platform | Layers |
|----------|--------|
| **iOS** | `InteraLavaLampBackground()` then **`InteraLavaViewportScrimLayer()`** |
| **Else** | `InteraLiquidMeshBackground()` (no lava on non-iOS hub in this composition) |

**`InteraLavaViewportScrimLayer`** — `Intera/Intera/DesignSystemColors.swift`  
A uniform **10% black** linear gradient (same color top and bottom—effectively a flat scrim) over the lava. Comments describe it as matching a CSS-style `linear-gradient(rgba(0,0,0,0.1), …)`. It sits **above** the lamp, **below** scrolling content, and does not receive hits.

**Why it matters:** One shared stack behind `UnifiedProviderHomeScreen` avoids **background flashes** when the user swipes between hub tabs—each tab is not repainting its own unrelated backdrop.

---

## Navigation: keeping lava visible

**`interaNavigationShellBackgroundClear()`** (iOS 18+, same file as hub helpers) applies **`containerBackground(Color.clear, for: .navigation)`** so SwiftUI’s navigation host does not paint an **opaque system background** over the window (which would read as flat black and hide the lamp).

**Usage intent:** Apply on the **root** view inside a `NavigationStack` when the shell should show lava behind transparent content (see doc comment on the extension).

---

## Tab swipe chrome (UIKit bridge)

**File:** `Intera/Intera/HubPageViewControllerSurfaceTint.swift`

SwiftUI’s paged **`TabView`** is backed by **`UIPageViewController`**. Without tuning, **horizontal gutter** areas during swipes could flash **system white**. `HubPageViewControllerSurfaceTint` walks the view hierarchy and tints the page controller / horizontal scroll shell to **`interaHubPageSwipeChromeUIColor`** — the **same RGB midnight** as `InteraLavaLampBackground`’s base — so transitions stay on-brand and aligned with the lava shell rather than light mode system backgrounds.

---

## Root composition

**File:** `Intera/Intera/RootView.swift`

On **iOS**, the root is a `ZStack`:

1. **`InteraLavaLampBackground()`** (full bleed)
2. **`VStack`** with optional live-data banner + **`mainChrome`** on **`Color.clear`** so the lamp shows through where chrome does not paint opaque fills.

On **non-iOS** branches in the same file, the snippet shown does **not** insert the lava lamp at the root (platform-specific shell).

---

## Where `InteraLavaLampBackground()` is used (direct instances)

These screens or containers **explicitly** embed the lamp (in addition to the hub’s `InteraHubTabShellBackground`, which includes it on iOS):

| Area | File (indicative) |
|------|-------------------|
| App root (signed-in shell) | `RootView.swift` |
| Consumer hub tab shell | `ScreensConsumerHome.swift` → `InteraHubTabShellBackground` (contains lava on iOS) |
| Messaging surfaces | `MessagingView.swift` (multiple stacks / states) |
| Live booking intake | `LiveBookingView.swift` |
| Booking detail (when not external) | `ConsumerBookingDetailView.swift` — can skip when `usesExternalLavaBackdrop` so a parent owns one lamp |
| Payment takeover | `ConsumerPaymentTakeoverView.swift` |
| Post-payment review | `ConsumerPostPaymentReviewView.swift` |
| Sign-up / glass flow | `LiquidGlassSignupFlow.swift` |
| Integrated sign-up sheet wrapper | `IntegratedSignUpSheet.swift` |
| Login UI | `UILoginView.swift` |
| Review booking step | `ReviewBookingView.swift` (often paired with mesh; see file comments) |
| Home / guest flows | `ScreensConsumerHome.swift` (additional lava placement beyond hub shell) |

**Note:** Some flows intentionally use **`InteraLiquidMeshBackground`** or **`InteraAuthFlowMeshBackground`** instead of lava (e.g. certain booking or chat stacks) for a **midnight → indigo** mesh look while **sharing the same midnight anchor**—so the overall app still feels coherent when pushing between “lava shell” and “mesh” contexts.

---

## Foreground palette: `lavaShellCream*`

**File:** `Intera/Intera/DesignSystemColors.swift`

| Token | Role |
|-------|------|
| `lavaShellCream` | Primary cream (`#F5F5DC`) for copy and icons on lava |
| `lavaShellCreamSecondary` | Same hue at **0.82** opacity |
| `lavaShellCreamTertiary` | Same hue at **0.64** opacity |

These appear across hub chrome, timelines, messaging, payment UI, provider browse headers, booking selectors (where unselected state stays cream-on-lava), empty states, and integrated sign-up chrome—so **most “on lava” typography** routes through one family of colors.

**`UnifiedTimelineView`** uses **`InteraLavaViewportScrimLayer`** in the stack for viewport treatment while timeline rows use the cream tokens for text.

---

## Related assets / patterns

- **Glass / liquid UI** — `InteraLiquidGlass.swift`: mesh backdrop, typography helpers, haptics; complements lava for auth-adjacent or alternate stacks.
- **Booking selector theme** — Selected states often flip to **`BookingSelectorTheme.deepCharcoal`** on cream fills for controls that must read as “filled” rather than outlined on lava (`BookingSelectorChrome`, `BookingSelectorsViews`, etc.).

---

## Summary for implementers

1. Prefer **one** lava layer per visible hierarchy (hub uses **`InteraHubTabShellBackground`**; detail views may use **`usesExternalLavaBackdrop`** to avoid double lamps).
2. On iOS hub, stack **lava → viewport scrim → content** for parity with design.
3. Use **`lavaShellCream*`** for primary foreground on lava; reserve dark fills for selected chips or high-attention controls.
4. Respect **Reduce Motion** (already handled inside `InteraLavaLampBackground`).
5. When debugging “flat black” behind navigation, confirm **`interaNavigationShellBackgroundClear()`** is applied where intended and that no parent is applying an opaque `NavigationStack` background.

---

## Primary source files

| File | Responsibility |
|------|----------------|
| `InteraLavaLampBackground.swift` | Lava lamp view, hub shell wrapper, navigation clear modifier |
| `DesignSystemColors.swift` | `lavaShellCream*` tokens, `InteraLavaViewportScrimLayer` |
| `InteraLiquidGlass.swift` | `InteraLiquidMeshBackground` / auth mesh (shared midnight anchor) |
| `HubPageViewControllerSurfaceTint.swift` | `TabView` / `UIPageViewController` swipe gutter tint |
| `RootView.swift` | Root ZStack + iOS lava behind `mainChrome` |
