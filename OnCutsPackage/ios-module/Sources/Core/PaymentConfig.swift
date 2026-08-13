import Foundation

/// Server response used to configure Stripe PaymentSheet (PaymentIntent + optional Customer for saved payment methods).
public struct PaymentConfig: Sendable, Equatable {
    public let paymentIntentClientSecret: String
    public let customerEphemeralKeySecret: String?
    public let customerId: String?
    public let paymentIntentId: String?
    /// From `POST …/create-payment-intent` when the server includes it; use to match `pk_live_` vs `pk_test_`.
    public let paymentIntentLivemode: Bool?
    /// Stripe charge amount (listed service + Service Fee; tip is a separate intent).
    public let amountCents: Int?
    /// Listed service only.
    public let serviceAmountCents: Int?
    /// Extra the client pays to the platform. `0` when operator burden or fee is off.
    public let serviceFeeCents: Int?
    public let feeBurden: String?

    public init(
        paymentIntentClientSecret: String,
        customerEphemeralKeySecret: String? = nil,
        customerId: String? = nil,
        paymentIntentId: String? = nil,
        paymentIntentLivemode: Bool? = nil,
        amountCents: Int? = nil,
        serviceAmountCents: Int? = nil,
        serviceFeeCents: Int? = nil,
        feeBurden: String? = nil
    ) {
        self.paymentIntentClientSecret = paymentIntentClientSecret
        self.customerEphemeralKeySecret = customerEphemeralKeySecret
        self.customerId = customerId
        self.paymentIntentId = paymentIntentId
        self.paymentIntentLivemode = paymentIntentLivemode
        self.amountCents = amountCents
        self.serviceAmountCents = serviceAmountCents
        self.serviceFeeCents = serviceFeeCents
        self.feeBurden = feeBurden
    }
}

/// UI routing after PaymentSheet finishes (SwiftUI / UIKit hosts observe this).
public enum CheckoutDestination: Equatable, Sendable {
    case idle
    case success
    case failed(String)
}
