//
//  PostPaymentReviewContext.swift
//  Intera
//
//  Shown after card/cash payment so the consumer can rate the provider (0 = skip, 1–5 submitted to API).
//

import Foundation

struct PostPaymentReviewContext: Identifiable, Hashable, Sendable {
    var id: String { bookingId }
    let bookingId: String
    let barberName: String
    let serviceName: String
    let barberAvatarURL: String?

    init(bookingId: String, barberName: String, serviceName: String, barberAvatarURL: String?) {
        self.bookingId = bookingId
        self.barberName = barberName
        self.serviceName = serviceName
        self.barberAvatarURL = barberAvatarURL
    }

    init(from payload: BookingPaymentRequestPayload, barberAvatarURLOverride: String? = nil) {
        self.init(
            bookingId: payload.bookingId,
            barberName: payload.barberName,
            serviceName: payload.displayServiceName,
            barberAvatarURL: barberAvatarURLOverride ?? payload.barberAvatarURL
        )
    }
}
