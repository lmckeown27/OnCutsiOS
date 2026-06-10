//
//  ConsumerPostPaymentReviewView.swift
//  Intera
//
//  After paying, rate the provider (0 = no rating) and optionally leave a written review.
//

#if os(iOS)
import SwiftUI

struct ConsumerPostPaymentReviewView: View {
    let context: PostPaymentReviewContext
    let sessionManager: AppSessionManager

    @EnvironmentObject private var chatViewModel: ChatViewModel

    /// 0 = no star rating (skip rating on API); 1…5 are submitted.
    @State private var starRating: Int = 0
    @State private var comment: String = ""
    @State private var isSubmitting = false
    @State private var bannerError: String?

    var body: some View {
        ZStack {
            InteraLavaLampBackground()

            ScrollView {
                VStack(spacing: 0) {
                    reviewGlassCard {
                        VStack(spacing: 28) {
                            Text("How was your service?")
                                .font(.system(size: 22, weight: .bold, design: .default))
                                .foregroundStyle(Color.lavaShellCream)
                                .multilineTextAlignment(.center)

                            interactiveStarRow
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Written review (optional)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.lavaShellCreamSecondary)

                                ZStack(alignment: .topLeading) {
                                    if comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("Share feedback about your service…")
                                            .font(.body)
                                            .foregroundStyle(Color.paymentFieldPlaceholder)
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 18)
                                            .allowsHitTesting(false)
                                    }
                                    TextEditor(text: $comment)
                                        .scrollContentBackground(.hidden)
                                        .font(.body)
                                        .interaAdaptiveTextEditorForeground()
                                        .frame(minHeight: 120)
                                        .padding(10)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.paymentFieldBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.interaShellGlassStroke, lineWidth: 1)
                                )
                            }

                            if let bannerError {
                                Text(bannerError)
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                                    .multilineTextAlignment(.center)
                            }

                            VStack(spacing: 12) {
                                Button {
                                    Task { await finishReviewFlow() }
                                } label: {
                                    HStack {
                                        if isSubmitting {
                                            ProgressView()
                                                .tint(Color.paymentFilledButtonLabel)
                                        }
                                        Text("Submit")
                                            .font(.system(size: 18, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 52)
                                    .foregroundStyle(Color.paymentFilledButtonLabel)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.paymentFilledButtonFill)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isSubmitting)

                                Button("Not now") {
                                    Task { await skipWithoutSubmitting() }
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.paymentOutlineButtonLabel)
                            }
                        }
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var interactiveStarRow: some View {
        HStack(spacing: 10) {
            ForEach(1 ... 5, id: \.self) { index in
                Button {
                    if starRating == index {
                        starRating = 0
                    } else {
                        starRating = index
                    }
                } label: {
                    Image(systemName: index <= starRating ? "star.fill" : "star")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(
                            index <= starRating
                                ? Color(red: 1, green: 0.84, blue: 0.35)
                                : Color.interaShellForegroundTertiary
                        )
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set rating to \(index) stars")
            }
        }
    }

    private func reviewGlassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.thickMaterial)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.paymentGlassWash)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.interaShellGlassStroke, lineWidth: 1)
            )
    }

    @MainActor
    private func skipWithoutSubmitting() async {
        bannerError = nil
        await chatViewModel.refreshConsumerBookingsAndSyncPayment(sessionManager: sessionManager)
        await chatViewModel.completePostPaymentReviewNavigatingHome()
    }

    @MainActor
    private func finishReviewFlow() async {
        bannerError = nil
        if starRating < 1 {
            await skipWithoutSubmitting()
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            try await BookingSimplePaymentAPI.submitReview(
                bookingId: context.bookingId,
                rating: starRating,
                comment: trimmed.isEmpty ? nil : trimmed,
                bearerToken: sessionManager.currentSession?.token
            )
            await chatViewModel.refreshConsumerBookingsAndSyncPayment(sessionManager: sessionManager)
            await chatViewModel.completePostPaymentReviewNavigatingHome()
        } catch {
            if BookingSimplePaymentAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
                return
            }
            bannerError = error.localizedDescription
        }
    }
}
#endif
