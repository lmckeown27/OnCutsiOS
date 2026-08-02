//
//  PostPaymentReviewContext.swift
//  OnCuts
//
//  Shown after card/cash payment so the consumer can rate satisfaction (faces → 1/3/5) and optionally comment.
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
