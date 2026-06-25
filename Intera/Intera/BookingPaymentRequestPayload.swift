//
//  BookingPaymentRequestPayload.swift
//  Intera
//
//  Socket `booking-completed` + in-app payment takeover when the provider marks the service complete.
//

import Foundation

struct BookingPaymentRequestPayload: Identifiable, Hashable, Sendable {
    var id: String { bookingId }
    let bookingId: String
    let paymentUrl: URL
    let barberName: String
    let serviceName: String
    let priceCents: Int
    let priceFormatted: String
    /// Barber’s Stripe Connect account (`acct_…`) when the server includes it (e.g. `booking-completed` socket).
    let barberStripeAccountId: String?
    /// Profile image URL string (absolute or app-relative), when known from the socket or bookings list.
    let barberAvatarURL: String?

    /// Human-readable service label (matches consumer booking row / web), not raw enum strings like `HAIRCUT`.
    var displayServiceName: String {
        let t = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "Service" }
        if t == t.uppercased() {
            return Self.formatServiceTypeForConsumerDisplay(t)
        }
        return t
    }

    /// Decode Socket.IO payload from `PUT /bookings-simple/:id/complete` (see backend `booking-completed` emit).
    static func decode(socketData: [Any]) -> BookingPaymentRequestPayload? {
        guard         let raw = socketData.first else { return nil }
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

        return BookingPaymentRequestPayload(
            bookingId: trimmedBid,
            paymentUrl: paymentUrl,
            barberName: barber,
            serviceName: service,
            priceCents: cents,
            priceFormatted: formatted,
            barberStripeAccountId: stripeAcct,
            barberAvatarURL: avatar
        )
    }

    static func from(bookingRow: ConsumerBookingSimpleRow) -> BookingPaymentRequestPayload? {
        let u = bookingRow.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard u == "COMPLETED" else { return nil }
        guard let url = AppConfiguration.urlConsumerBookingPaymentWeb(bookingId: bookingRow.id) else { return nil }
        let name = bookingRow.barberName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Your provider"
        let cents = bookingRow.priceUsdCents ?? 0
        let formatted: String = {
            let d = Decimal(cents) / 100
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = "USD"
            return f.string(from: NSDecimalNumber(decimal: d)) ?? String(format: "$%.2f", Double(cents) / 100.0)
        }()
        return BookingPaymentRequestPayload(
            bookingId: bookingRow.id,
            paymentUrl: url,
            barberName: name,
            serviceName: bookingRow.displayServiceName,
            priceCents: cents,
            priceFormatted: formatted,
            barberStripeAccountId: nil,
            barberAvatarURL: bookingRow.barberAvatar
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
