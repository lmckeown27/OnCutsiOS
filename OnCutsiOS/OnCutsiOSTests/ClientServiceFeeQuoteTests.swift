import Testing
@testable import OnCutsiOS

struct ClientServiceFeeQuoteTests {
    private func clientConfig(percent: Double, enabled: Bool = true) -> PlatformFrontendConfig {
        PlatformFrontendConfig(
            cashPaymentEnabled: false,
            consumerHomeMode: .providers,
            consumerUserCount: 0,
            feeBurden: .client,
            platformCommissionEnabled: enabled,
            platformFeePercent: percent,
            consumerHomeReviewsEnabled: true,
            paymentTimingMode: .onAccept
        )
    }

    @Test func clientBurdenAddsRoundedFee() {
        let quote = ClientServiceFeeQuoting.quote(
            listedServiceCents: 2000,
            config: clientConfig(percent: 15)
        )
        #expect(quote.serviceFeeCents == 300)
        #expect(quote.chargeAmountCents == 2300)
        #expect(quote.showsServiceFeeRow)
    }

    @Test func halfUpRoundsToNearestCent() {
        // 1999 * 15% = 299.85 → 300
        let quote = ClientServiceFeeQuoting.quote(
            listedServiceCents: 1999,
            config: clientConfig(percent: 15)
        )
        #expect(quote.serviceFeeCents == 300)
        #expect(quote.chargeAmountCents == 2299)
    }

    @Test func operatorBurdenQuotesNoFee() {
        let quote = ClientServiceFeeQuoting.quote(
            listedServiceCents: 2000,
            config: .fallbackProviders
        )
        #expect(quote.serviceFeeCents == 0)
        #expect(quote.chargeAmountCents == 2000)
        #expect(!quote.showsServiceFeeRow)
    }

    @Test func disabledCommissionQuotesNoFee() {
        let quote = ClientServiceFeeQuoting.quote(
            listedServiceCents: 2000,
            config: clientConfig(percent: 15, enabled: false)
        )
        #expect(quote.serviceFeeCents == 0)
        #expect(quote.chargeAmountCents == 2000)
    }

    @Test func bookingPayloadPreferredOverLocalQuote() {
        let amounts = ClientServiceFeeQuoting.resolve(
            listedServiceCents: 2000,
            serviceFeeCents: 250,
            chargeAmountCents: 2250,
            config: clientConfig(percent: 15)
        )
        #expect(amounts.serviceFeeCents == 250)
        #expect(amounts.chargeAmountCents == 2250)
    }

    @Test func missingBookingFeeFallsBackToQuote() {
        let amounts = ClientServiceFeeQuoting.resolve(
            listedServiceCents: 2000,
            serviceFeeCents: nil,
            chargeAmountCents: nil,
            config: clientConfig(percent: 15)
        )
        #expect(amounts.serviceFeeCents == 300)
        #expect(amounts.chargeAmountCents == 2300)
    }

    @Test func invalidPercentDefaultsToFifteen() {
        #expect(PlatformFrontendConfig.sanitizedPercent(nil) == 15)
        #expect(PlatformFrontendConfig.sanitizedPercent(-1) == 15)
        #expect(PlatformFrontendConfig.sanitizedPercent(101) == 15)
        #expect(PlatformFrontendConfig.sanitizedPercent(12.5) == 12.5)
    }

    @Test func unknownFeeBurdenIsOperator() {
        #expect(PlatformFeeBurden.parse(nil) == .operatorBurden)
        #expect(PlatformFeeBurden.parse("CLIENT") == .client)
        #expect(PlatformFeeBurden.parse("something-else") == .operatorBurden)
    }
}
