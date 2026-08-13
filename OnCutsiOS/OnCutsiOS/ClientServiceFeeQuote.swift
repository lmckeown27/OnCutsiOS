//
//  ClientServiceFeeQuote.swift
//  OnCuts
//
//  Quotes the client Service Fee the same way as web `quoteClientServiceFee`.
//  The server PaymentIntent is the charge of record — this is display-only until a booking exists.
//

import Foundation

enum PlatformFeeBurden: String, Codable, Sendable, Equatable {
    case client
    case operatorBurden = "operator"

    /// Anything other than `"client"` is treated as operator (no client Service Fee).
    static func parse(_ raw: String?) -> PlatformFeeBurden {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t == "client" ? .client : .operatorBurden
    }
}

struct ClientServiceAmounts: Equatable, Sendable {
    let listedServiceCents: Int
    let serviceFeeCents: Int
    let chargeAmountCents: Int

    var showsServiceFeeRow: Bool { serviceFeeCents > 0 }
}

enum ClientServiceFeeQuoting {
    /// Half-up to the nearest cent, matching JavaScript `Math.round` for non-negative amounts.
    static func quote(listedServiceCents: Int, config: PlatformFrontendConfig) -> ClientServiceAmounts {
        let listed = max(0, listedServiceCents)
        guard config.feeBurden == .client,
              config.platformCommissionEnabled,
              config.platformFeePercent > 0
        else {
            return ClientServiceAmounts(
                listedServiceCents: listed,
                serviceFeeCents: 0,
                chargeAmountCents: listed
            )
        }
        let raw = Double(listed) * config.platformFeePercent / 100.0
        let fee = Int(raw.rounded(.toNearestOrAwayFromZero))
        return ClientServiceAmounts(
            listedServiceCents: listed,
            serviceFeeCents: fee,
            chargeAmountCents: listed + fee
        )
    }

    /// Prefer booking `serviceFeeCents` / `chargeAmountCents`; otherwise quote from frontend-config.
    static func resolve(
        listedServiceCents: Int?,
        serviceFeeCents: Int?,
        chargeAmountCents: Int?,
        config: PlatformFrontendConfig
    ) -> ClientServiceAmounts {
        let listed = max(0, listedServiceCents ?? 0)
        if let fee = serviceFeeCents, let charge = chargeAmountCents {
            return ClientServiceAmounts(
                listedServiceCents: listed,
                serviceFeeCents: max(0, fee),
                chargeAmountCents: max(0, charge)
            )
        }
        if let charge = chargeAmountCents {
            let fee = serviceFeeCents.map { max(0, $0) } ?? max(0, charge - listed)
            return ClientServiceAmounts(
                listedServiceCents: listed,
                serviceFeeCents: fee,
                chargeAmountCents: max(0, charge)
            )
        }
        if let fee = serviceFeeCents {
            let safeFee = max(0, fee)
            return ClientServiceAmounts(
                listedServiceCents: listed,
                serviceFeeCents: safeFee,
                chargeAmountCents: listed + safeFee
            )
        }
        return quote(listedServiceCents: listed, config: config)
    }
}

enum USDCurrencyFormatting {
    static func string(cents: Int) -> String {
        let dollars = Decimal(cents) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSDecimalNumber(decimal: dollars))
            ?? String(format: "$%.2f", Double(cents) / 100.0)
    }
}
