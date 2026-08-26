//
//  PaymentTimingModeTests.swift
//  OnCutsTests
//

import Testing
@testable import OnCuts

struct PaymentTimingModeTests {
    @Test func parseDefaultsToOnAccept() {
        #expect(PaymentTimingMode.parse(nil) == .onAccept)
        #expect(PaymentTimingMode.parse("") == .onAccept)
        #expect(PaymentTimingMode.parse("on_accept") == .onAccept)
        #expect(PaymentTimingMode.parse("AFTER_COMPLETE") == .afterComplete)
        #expect(PaymentTimingMode.parse("after_complete") == .afterComplete)
    }

    @Test func onAcceptGatesPayOnAcceptedUnpaid() {
        let unpaidAccepted = makeRow(status: "ACCEPTED", paidAt: nil, tipDecidedAt: nil)
        let completedTipPending = makeRow(status: "COMPLETED", paidAt: "2026-01-01T00:00:00Z", tipDecidedAt: nil)
        let unpaidCompleted = makeRow(status: "COMPLETED", paidAt: nil, tipDecidedAt: nil)

        #expect(unpaidAccepted.needsServicePayment(timingMode: .onAccept))
        #expect(!unpaidAccepted.needsTipDecision(timingMode: .onAccept))
        #expect(unpaidAccepted.needsPaymentAction(timingMode: .onAccept))

        #expect(!completedTipPending.needsServicePayment(timingMode: .onAccept))
        #expect(completedTipPending.needsTipDecision(timingMode: .onAccept))

        // Unpaid COMPLETED is unusual for on_accept; tip gate still matches COMPLETED without tipDecidedAt.
        #expect(!unpaidCompleted.needsServicePayment(timingMode: .onAccept))
        #expect(unpaidCompleted.needsTipDecision(timingMode: .onAccept))
    }

    @Test func afterCompleteGatesPayOnCompletedUnpaidOnly() {
        let unpaidAccepted = makeRow(status: "ACCEPTED", paidAt: nil, tipDecidedAt: nil)
        let unpaidCompleted = makeRow(status: "COMPLETED", paidAt: nil, tipDecidedAt: nil)
        let paidCompleted = makeRow(status: "COMPLETED", paidAt: "2026-01-01T00:00:00Z", tipDecidedAt: "2026-01-01T00:05:00Z")

        #expect(!unpaidAccepted.needsServicePayment(timingMode: .afterComplete))
        #expect(!unpaidAccepted.needsTipDecision(timingMode: .afterComplete))
        #expect(!unpaidAccepted.needsPaymentAction(timingMode: .afterComplete))
        #expect(unpaidAccepted.displayStatus(timingMode: .afterComplete) == "Confirmed")

        #expect(unpaidCompleted.needsServicePayment(timingMode: .afterComplete))
        #expect(!unpaidCompleted.needsTipDecision(timingMode: .afterComplete))
        #expect(unpaidCompleted.needsPaymentAction(timingMode: .afterComplete))
        #expect(unpaidCompleted.displayStatus(timingMode: .afterComplete) == "Payment required")

        #expect(!paidCompleted.needsPaymentAction(timingMode: .afterComplete))
    }

    @Test func payloadModeFollowsTiming() {
        let unpaidAccepted = makeRow(status: "ACCEPTED", paidAt: nil, tipDecidedAt: nil)
        let unpaidCompleted = makeRow(status: "COMPLETED", paidAt: nil, tipDecidedAt: nil)

        let onAcceptConfig = PlatformFrontendConfig.fallbackProviders
        let afterConfig = PlatformFrontendConfig(
            cashPaymentEnabled: false,
            consumerHomeMode: .providers,
            consumerUserCount: 0,
            feeBurden: .operatorBurden,
            platformCommissionEnabled: true,
            platformFeePercent: 15,
            consumerHomeReviewsEnabled: true,
            paymentTimingMode: .afterComplete
        )

        let acceptPayload = BookingPaymentRequestPayload.from(
            bookingRow: unpaidAccepted,
            frontendConfig: onAcceptConfig
        )
        #expect(acceptPayload?.mode == .serviceConfirm)
        #expect(acceptPayload?.allowsOptionalTipOnServiceCharge == false)

        #expect(
            BookingPaymentRequestPayload.from(
                bookingRow: unpaidAccepted,
                frontendConfig: afterConfig
            ) == nil
        )

        let afterPayload = BookingPaymentRequestPayload.from(
            bookingRow: unpaidCompleted,
            frontendConfig: afterConfig
        )
        #expect(afterPayload?.mode == .serviceConfirm)
        #expect(afterPayload?.allowsOptionalTipOnServiceCharge == true)
    }

    private func makeRow(
        status: String,
        paidAt: String?,
        tipDecidedAt: String?
    ) -> ConsumerBookingSimpleRow {
        ConsumerBookingSimpleRow(
            id: "b1",
            barberId: "barber-1",
            serviceType: nil,
            serviceName: "Haircut",
            scheduledTime: "2026-08-26T18:00:00.000Z",
            status: status,
            barberName: "Test Barber",
            barberAvatar: nil,
            location: nil,
            notes: nil,
            priceUsdCents: 2000,
            serviceFeeCents: nil,
            chargeAmountCents: nil,
            feeBurden: nil,
            paidAt: paidAt,
            completedAt: status == "COMPLETED" ? "2026-08-26T19:00:00.000Z" : nil,
            tipRequestedAt: nil,
            tipDecidedAt: tipDecidedAt,
            tipAmountCents: nil,
            pendingRescheduleRequest: nil
        )
    }
}
