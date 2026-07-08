# Intera Provider companion — backend & real-time appendix

Curated from **`OnCutsPackage/backend`** and the **Intera** iOS client in this workspace. Use with **`INTERA_CONSUMER_APP_SPEC_FOR_PROVIDER_COMPANION.md`**.

---

## 1. `bookings-simple` REST surface (`/api/v1/bookings-simple`)

Source: **`OnCutsPackage/backend/src/routes/booking-simple.routes.ts`** (all routes below use `authenticate` unless noted).

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/stripe/client-config` | Stripe publishable key / client verification (alias for older proxies). |
| `POST` | `/` | **Consumer** creates booking. Body includes `barberId`, `serviceType`, `priceUsdCents`, `scheduledTime`, `location`, `locationDetails`, `notes`. Server resolves `barberId` to **`barbers.id`** via `SELECT id FROM barbers WHERE id = $1 OR "userId" = $1` — **either** barbers row id **or** barber’s **user id** is accepted. |
| `POST` | `/walk-in/create-payment` | Walk-in payment flow (see file). |
| `POST` | `/walk-in/confirm-payment` | Walk-in confirm. |
| `POST` | `/walk-in/record-cash` | Walk-in cash. |
| `GET` | `/campus/:campusId` | Campus-scoped listing (see file). |
| `POST` | `/:id/hide-from-list` | Consumer hides booking from timeline (`consumer_hidden_bookings`). |
| `GET` | `/:id` | Single booking detail for authorized participant. |
| `PUT` | `/:id/status` | Body: `{ status }`. Allowed values: **`PENDING`, `ACCEPTED`, `REJECTED`, `COMPLETED`, `PAID`, `CANCELLED`**. **Important:** `UPDATE … WHERE ("consumerId" = $userId OR "barberId" = $userId)` — `bookings.barberId` is normally **`barbers.id`**, not `users.id`. **Verify in your DB** whether barbers can update via this route; other routes (e.g. `PUT /:id`, `PUT /:id/complete`) join **`barbers` → `userId`** explicitly. |
| `PUT` | `/:id/complete` | **Barber only** (matches `barber."userId" = JWT userId`). Sets **`COMPLETED`**, deactivates conversation, emails/push, emits **`booking-completed`** to consumer. |
| `PUT` | `/:id/undo-complete` | Barber reverts **`COMPLETED` → `ACCEPTED`**, clears `paymentRequestedAt`, reactivates conversation; emits **`booking-status-changed`** to consumer. |
| `GET` | `/` | Query: `role=barber` \| `consumer`, optional `status` (comma-separated), `startDate`, `endDate`. See §3. |
| `POST` | `/:id/request-payment` | Barber-only; from **`ACCEPTED`** moves flow toward payment (see file — overlaps conceptually with complete in places). |
| `POST` | `/:id/create-payment-intent` | Stripe PaymentIntent for booking (consumer / app checkout). |
| `POST` | `/:id/update-payment-intent` | Update PI (e.g. tip). |
| `POST` | `/:id/confirm-payment` | After Stripe success; marks **`PAID`**, archives/deletes conversation; emits **`payment-received`** to **barber user** room. |
| `POST` | `/:id/pay` | Legacy/mock pay with `paymentMethod: card` \| `cash` (see file). |
| `POST` | `/:id/review` | Consumer submits review after service. |
| `PUT` | `/:id` | **Reschedule / edit** — barber **or** consumer (`bar."userId" = $2 OR consumerId = $2`). Allowed when status is **`PENDING` or `ACCEPTED`**. Updates `bookings.requestedAt` and/or `conversations` fields. Emits **`booking-update`** to **both** `user-${barber_user_id}` and `user-${consumerId}`. |
| `DELETE` | `/:id` | Cancel/delete; barber or consumer; **admin** special case for completed/paid removal (see file). |

**Reschedule / cancel semantics (high level)**

- **`PUT /:id`** — preferred path for **barber-led** time/location/notes edits with notifications to the other party.
- **`PUT /:id/status`** — coarse status machine; **CANCELLED** or **REJECTED** deletes linked conversation + messages in this handler.
- **`DELETE /:id`** — cancellation with `reason` in body (see full handler for status gates).

---

## 2. IDs: `users.id` vs `barbers.id`

| Concept | Value |
|---------|--------|
| **JWT `userId`** | `users.id` (UUID string in app; server uses `sameUuid` in places). |
| **`bookings.consumerId`** | Consumer **`users.id`**. |
| **`bookings.barberId`** | **`barbers.id`** (barber **table** row), **not** the user id. |
| **Socket / notify “barber”** | Uses **`barbers.userId` → `users.id`** for rooms, e.g. `io.to(\`user-${barberUserId}\`)`. |
| **`GET /bookings-simple?role=barber`** | Server loads `SELECT id FROM barbers WHERE "userId" = $jwtUser` and filters `b."barberId" = barberRecordId`. |

**Create booking (`POST /`)** accepts **`barberId`** as either **`barbers.id`** or **`users.id`** of the barber (see `WHERE id = $1 OR "userId" = $1`).

**List response `barberId` field** in JSON is the **booking FK** (i.e. **`barbers.id`**), while nested `consumer.id` / barber user fields may reflect **users** — when building the Provider UI, **always trace through** the GET payload shape in `booking-simple.routes.ts` (mapper around lines ~1384–1420).

---

## 3. `GET /bookings-simple` — `role` and “no barbers row”

From **`router.get('/', …)`**:

1. Runs `SELECT id FROM barbers WHERE "userId" = $jwtUser` → `isBarber`, `barberRecordId`.
2. **`role=barber` and `barberRecordId` set** → `WHERE b."barberId" = barberRecordId`.
3. **`role=consumer`** → `WHERE b."consumerId" = userId`.
4. **Else (default)** — If user **is** a barber: `(barberId = barberRecordId OR consumerId = userId)`. If **not** a barber: **only** `consumerId = userId`.

**Product implication:** A user with **role BARBER in JWT** but **no `barbers` row** behaves like a **consumer-only** list for `role=consumer`; for `role=barber` the `whereClause` would use `barberRecordId = null` — **confirm behavior** in code path (likely empty or error-prone). **Provider app** should call **`GET /auth/me`** (or equivalent) and either **onboard** into `barbers` or **block** with a clear message.

---

## 4. Socket.IO — server (`index.ts`) + `booking-simple` + messages

### 4.1 Server config

- **`OnCutsPackage/backend/src/index.ts`**: `Server(httpServer, { path: '/socket.io/', cors: …, transports: ['polling','websocket'] })`.
- **Intera client** uses **`AppConfiguration.messagingSocketOriginURL`** (scheme + host, **no** `/api/v1`) and path **`/socket.io/`** (see `MessagingRealtime.swift`).
- **CORS**: allowed origins list includes `https://campuscut.com` and localhost variants — **staging origins must be added** here (and in REST CORS) or mobile web sockets will fail.

### 4.2 Client → server events (registered in this repo’s `index.ts`)

| Client emit | Payload (as implemented) | Effect |
|-------------|---------------------------|--------|
| **`join-personal`** | `userId` (TS types say `number`; iOS passes **string** UUID — Socket.IO typically coerces) | `socket.join("user-" + userId)` |
| **`join-campus`** | `campusId` | `socket.join("campus-" + campusId)` |
| **`join-admin-live-feed`** | `userId` | Joins `admin-live-feed` (TODO: verify admin in code) |

**`join-conversation` / `leave-conversation`**

- The **Intera** app emits these (see **`MessagingRealtime.swift`**) to mirror the web client.
- **This repository’s `index.ts` does not define handlers** for `join-conversation` / `leave-conversation`. **Real-time chat still works** because **`message.routes.ts`** emits **`new-message`** to **`io.to(\`user-${recipientId}\`)`**, i.e. the recipient’s **personal room** after they **`join-personal`**.

### 4.3 Server → client events (catalog)

| Event | When | Room / target | Payload (curated) |
|-------|------|-----------------|-------------------|
| **`joined-personal`** | After `join-personal` | Emit to socket | `{ userId, socketId }` |
| **`new-message`** | After `POST …/messages/.../messages` | **`user-${recipientId}`** | **Message object** (same as REST `result.data.message`). |
| **`new-booking-request`** | After consumer `POST /bookings-simple` | **`user-${barberUserId}`** (barber’s **users.id**) | `{ id, consumerId, barberId, serviceType, priceUsdCents, scheduledTime, location, notes, status: 'PENDING', consumerName, createdAt }` — note **`barberId` here is `barberRecordId` (`barbers.id`)**. |
| **`booking-completed`** | After **`PUT …/:id/complete`** | **`user-${consumerId}`** | `{ bookingId, status: 'COMPLETED', barberName, serviceName, price, priceFormatted, paymentUrl, scheduledDate, scheduledTime, location, stripeAccountId, barberAvatar, barberProfileImageUrl }` |
| **`booking-status-changed`** | After **`PUT …/:id/undo-complete`** (consumer) | **`user-${consumerId}`** | `{ bookingId, status: 'ACCEPTED', message: '…' }` |
| **`booking-update`** | After **`PUT …/:id`** (edit) | **`user-${barber_user_id}`** and **`user-${consumerId}`** | `{ id, scheduledTime, location, notes, status, barberId, consumerId, serviceType, updatedBy: 'barber' \| 'consumer' }` |
| **`payment-received`** | After **`POST …/:id/confirm-payment`** (and cash path in file) | **`user-${barber_user_id}`** | `{ bookingId, consumerId, consumerName, amountPaid, tipAmount, totalFormatted, tipFormatted? }` |

**Consumer iOS listeners today** (`MessagingRealtime.swift`): **`new-message`**, **`booking-completed`**, **`booking-status-changed`**. It does **not** yet listen for **`new-booking-request`**, **`booking-update`**, or **`payment-received`** — the **Provider app** should subscribe to those relevant to barbers.

---

## 5. Messages REST (path prefix in monolith)

**`OnCutsPackage/backend/src/routes/message.routes.ts`** uses paths like **`/conversations`** — confirm how **`app.use`** mounts this (e.g. `/api/v1/messages`). Intera’s **`MessagingAPIService`** should match your deployed router prefix.

---

## 6. Product / permissions (decisions for you to lock)

| Topic | Suggested starting point |
|-------|---------------------------|
| **Who may use Provider app** | Only users with a **`barbers` row** (`GET /auth/me` + existence check). Reject **students** at sign-in or immediately after me with a dedicated “consumer app” deep link. |
| **Admin** | Intera consumer **`RootView`** routes `.admin` to **`MainTabView`** — decide if admins use Provider app or web only. |
| **Web vs app** | Stripe Connect onboarding, tax, disputes, calendar deep integrations may stay **web-only** day one; Provider app focuses on **schedule, requests, messages, complete, payout notifications**. |
| **Staging** | Duplicate **`AppConfiguration`** pattern: separate API root, plist / xcconfig for **`pk_test_`**, Stripe Dashboard Apple Pay domain + merchant, and **socket CORS** origins for your staging host. |
| **App Review** | Barber demo account with **`PENDING`**, **`ACCEPTED`**, **`COMPLETED`**, paid thread; at least one **active conversation** with messages; document steps in App Store Connect. |

---

## 7. Consumer Intera files to read for parity

| File | Why |
|------|-----|
| `Intera/Intera/MessagingRealtime.swift` | Socket connect params, events, `join-personal`. |
| `Intera/Intera/ChatViewModel.swift` | Socket lifecycle + booking refresh + payment takeover bridge. |
| `Intera/Intera/BookingPaymentRequestPayload.swift` | `booking-completed` payload decoding. |
| `Intera/Intera/AppConfiguration.swift` | REST root + socket origin. |
| `Intera/Intera/ConsumerBookingsHubView.swift` | Consumer `bookings-simple` list UX. |
| `OnCutsPackage/ios-module/Sources/Core/CheckoutViewModel.swift` | PaymentSheet + Apple Pay wiring. |

---

## 8. Known caveat to validate in QA

**`PUT /:id/status`** authorization uses **`"barberId" = userId`**. Elsewhere **`barberId`** is **`barbers.id`**. If status updates from the barber fail with 404, fix server-side to join `barbers` on `userId` (same pattern as **`PUT /:id/complete`**) or document the **intended** client workaround.

---

*Generated from repository sources; re-run diff against `booking-simple.routes.ts` after backend merges.*
