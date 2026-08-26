//
//  BookingPaymentRequestPayload.swift
//  OnCuts
//
//  In-app payment takeover: service confirm / tip decision (on_accept) or
//  post-complete service (+ optional tip) when paymentTimingMode is after_complete.
//

import Foundation

struct BookingPaymentRequestPayload: Identifiable, Hashable, Sendable {
    enum Mode: String, Hashable, Sendable {
        /// Charge service (on_accept: ACCEPTED unpaid; after_complete: COMPLETED unpaid).
        case serviceConfirm
        /// Tip only after complete when `paymentTimingMode == on_accept`.
        case tipDecide
    }

    var id: String { bookingId }
    let bookingId: String
    let paymentUrl: URL
    let barberName: String
    let serviceName: String
    /// Listed service only (`priceUsdCents`). Never includes Service Fee or tip.
    let listedServiceCents: Int
    /// Extra the client pays to the platform. `0` when burden is operator or the fee is off.
    let serviceFeeCents: Int
    /// What the client owes for the service (`listed + serviceFee`). Tip is separate.
    let chargeAmountCents: Int
    /// Same as `chargeAmountCents` for service pay; listed/tip amount for tip-decide.
    let priceCents: Int
    let priceFormatted: String
    /// Barber’s Stripe Connect account (`acct_…`) when the server includes it (e.g. `booking-completed` socket).
    let barberStripeAccountId: String?
    /// Profile image URL string (absolute or app-relative), when known from the socket or bookings list.
    let barberAvatarURL: String?
    /// ISO / API `scheduledTime` for the appointment (service-confirm screen shows date + time).
    let scheduledTime: String?
    let mode: Mode
    /// Snapshot of admin payment structure when this payload was built.
    let paymentTimingMode: PaymentTimingMode

    /// Human-readable service label (matches consumer booking row / web), not raw enum strings like `HAIRCUT`.
    var displayServiceName: String {
        let t = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "Service" }
        if t == t.uppercased() {
            return Self.formatServiceTypeForConsumerDisplay(t)
        }
        return t
    }

    /// Service PI may include an optional tip when paying after complete.
    var allowsOptionalTipOnServiceCharge: Bool {
        mode == .serviceConfirm && paymentTimingMode == .afterComplete
    }

    /// Decode Socket.IO payload from provider mark-complete (`booking-completed`).
    @MainActor
    static func decode(socketData: [Any]) -> BookingPaymentRequestPayload? {
        decode(
            socketData: socketData,
            timingMode: PlatformFrontendConfigStore.shared.paymentTimingMode
        )
    }

    static func decode(
        socketData: [Any],
        timingMode: PaymentTimingMode
    ) -> BookingPaymentRequestPayload? {
        guard let raw = socketData.first else { return nil }
        guard let dict = raw as? [String: Any] else { return nil }

        let bid = stringValue(dict["bookingId"] ?? dict["booking_id"]) ?? ""
        let trimmedBid = bid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBid.isEmpty else { return nil }

        let urlString = stringValue(dict["paymentUrl"] ?? dict["payment_url"]) ?? ""
        let paymentUrl: URL? = {
            let t = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let u = URL(string: t) { return u }
            return AppConfiguration.urlConsumerBookingPaymentWeb(bookingId: trimmedBid)
        }()
        guard let paymentUrl else { return nil }

        let barber = stringValue(dict["barberName"] ?? dict["barber_name"]) ?? "Your provider"
        let service = stringValue(dict["serviceName"] ?? dict["service_name"]) ?? "Service"

        let cents: Int = {
            if let n = dict["price"] as? Int { return n }
            if let n = dict["price"] as? NSNumber { return n.intValue }
            if let d = dict["price"] as? Double { return Int(d) }
            return 0
        }()

        let formatted =
            stringValue(dict["priceFormatted"] ?? dict["price_formatted"])
            ?? String(format: "$%.2f", Double(cents) / 100.0)

        let stripeAcct = stringValue(dict["stripeAccountId"] ?? dict["stripe_account_id"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let avatar = stringValue(
            dict["barberAvatar"]
                ?? dict["barber_avatar"]
                ?? dict["barberProfileImageUrl"]
                ?? dict["barber_profile_image_url"]
                ?? dict["barberImageUrl"]
                ?? dict["barber_image_url"]
                ?? dict["providerAvatar"]
                ?? dict["provider_avatar"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let scheduled = stringValue(
            dict["scheduledTime"]
                ?? dict["scheduled_time"]
                ?? dict["requestedAt"]
                ?? dict["requested_at"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let phase = stringValue(dict["phase"])?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mode: Mode = {
            if timingMode == .afterComplete { return .serviceConfirm }
            if phase == "service" { return .serviceConfirm }
            return .tipDecide
        }()

        return BookingPaymentRequestPayload(
            bookingId: trimmedBid,
            paymentUrl: paymentUrl,
            barberName: barber,
            serviceName: service,
            listedServiceCents: cents,
            serviceFeeCents: 0,
            chargeAmountCents: cents,
            priceCents: cents,
            priceFormatted: formatted,
            barberStripeAccountId: stripeAcct,
            barberAvatarURL: avatar,
            scheduledTime: scheduled,
            mode: mode,
            paymentTimingMode: timingMode
        )
    }

    @MainActor
    static func from(bookingRow: ConsumerBookingSimpleRow) -> BookingPaymentRequestPayload? {
        from(bookingRow: bookingRow, frontendConfig: PlatformFrontendConfigStore.shared.config)
    }

    static func from(
        bookingRow: ConsumerBookingSimpleRow,
        frontendConfig: PlatformFrontendConfig
    ) -> BookingPaymentRequestPayload? {
        let timing = frontendConfig.paymentTimingMode
        let mode: Mode
        if bookingRow.needsServicePayment(timingMode: timing) {
            mode = .serviceConfirm
        } else if bookingRow.needsTipDecision(timingMode: timing) {
            mode = .tipDecide
        } else {
            return nil
        }
        guard let url = AppConfiguration.urlConsumerBookingPaymentWeb(bookingId: bookingRow.id) else { return nil }
        let name = bookingRow.barberName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Your provider"
        let amounts = bookingRow.resolvedClientServiceAmounts(quotingWith: frontendConfig)
        let displayCents = mode == .serviceConfirm ? amounts.chargeAmountCents : amounts.listedServiceCents
        return BookingPaymentRequestPayload(
            bookingId: bookingRow.id,
            paymentUrl: url,
            barberName: name,
            serviceName: bookingRow.displayServiceName,
            listedServiceCents: amounts.listedServiceCents,
            serviceFeeCents: mode == .serviceConfirm ? amounts.serviceFeeCents : 0,
            chargeAmountCents: amounts.chargeAmountCents,
            priceCents: displayCents,
            priceFormatted: USDCurrencyFormatting.string(cents: displayCents),
            barberStripeAccountId: nil,
            barberAvatarURL: bookingRow.barberAvatar,
            scheduledTime: bookingRow.scheduledTime,
            mode: mode,
            paymentTimingMode: timing
        )
    }

    /// Same word-splitting as `ConsumerBookingSimpleRow` for `serviceType`-style values.
    private static func formatServiceTypeForConsumerDisplay(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { String($0.prefix(1).uppercased() + $0.dropFirst()) }
            .joined(separator: " ")
    }

    private static func stringValue(_ any: Any?) -> String? {
        guard let any else { return nil }
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return String(describing: any)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
