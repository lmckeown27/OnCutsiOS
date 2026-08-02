//
//  ConsumerPostPaymentReviewView.swift
//  OnCuts
//
//  After paying, rate satisfaction with three faces and optionally leave a written review.
//

#if os(iOS)
import SwiftUI
import UIKit

/// Three-face satisfaction choice mapped to the bookings-simple `rating` (1…5) API.
private enum PostPaymentSatisfaction: Int, CaseIterable, Identifiable {
    case dissatisfied = 1
    case neutral = 3
    case satisfied = 5

    var id: Int { rawValue }

    var assetName: String {
        switch self {
        case .dissatisfied: return "Dissatisfied Face"
        case .neutral: return "Neutral Face"
        case .satisfied: return "Satisfied Face"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .dissatisfied: return "Dissatisfied"
        case .neutral: return "Neutral"
        case .satisfied: return "Satisfied"
        }
    }

    var caption: String {
        accessibilityLabel
    }
}

struct ConsumerPostPaymentReviewView: View {
    let context: PostPaymentReviewContext
    let sessionManager: AppSessionManager

    @EnvironmentObject private var chatViewModel: ChatViewModel

    /// `nil` = no selection (skip rating on submit / “Not now”).
    @State private var selectedSatisfaction: PostPaymentSatisfaction?
    @State private var comment: String = ""
    @State private var isSubmitting = false
    @State private var bannerError: String?
    @FocusState private var isReviewCommentFocused: Bool

    var body: some View {
        ZStack {
            OnCutsLavaLampBackground()

            ScrollView {
                VStack(spacing: 0) {
                    reviewGlassCard {
                        VStack(spacing: 28) {
                            Text("How was your service?")
                                .font(OnCutsFont.system(size: 22, weight: .bold, design: .default))
                                .foregroundStyle(Color.lavaShellCream)
                                .multilineTextAlignment(.center)
                                .onTapGesture { dismissReviewKeyboard() }

                            interactiveSatisfactionRow
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Written review (optional)")
                                    .font(OnCutsFont.subheadline(weight: .semibold))
                                    .foregroundStyle(Color.lavaShellCreamSecondary)
                                    .onTapGesture { dismissReviewKeyboard() }

                                ZStack(alignment: .topLeading) {
                                    if comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("Share feedback about your service…")
                                            .font(OnCutsFont.body)
                                            .foregroundStyle(Color.paymentFieldPlaceholder)
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 18)
                                            .allowsHitTesting(false)
                                    }
                                    TextEditor(text: $comment)
                                        .scrollContentBackground(.hidden)
                                        .font(OnCutsFont.body)
                                        .onCutsAdaptiveTextEditorForeground()
                                        .focused($isReviewCommentFocused)
                                        .frame(minHeight: 120)
                                        .padding(10)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.paymentFieldBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.onCutsShellGlassStroke, lineWidth: 1)
                                )
                            }

                            if let bannerError {
                                Text(bannerError)
                                    .font(OnCutsFont.footnote)
                                    .foregroundStyle(.orange)
                                    .multilineTextAlignment(.center)
                            }

                            VStack(spacing: 12) {
                                PrimaryButton(
                                    title: "Submit",
                                    action: {
                                        dismissReviewKeyboard()
                                        Task { await finishReviewFlow() }
                                    },
                                    isLoading: isSubmitting,
                                    isDisabled: isSubmitting,
                                    variant: .shell,
                                    size: .footer
                                )

                                Button("Not now") {
                                    dismissReviewKeyboard()
                                    Task { await skipWithoutSubmitting() }
                                }
                                .font(OnCutsFont.subheadline(weight: .semibold))
                                .foregroundStyle(Color.paymentOutlineButtonLabel)
                            }
                        }
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    guard isReviewCommentFocused else { return }
                    dismissReviewKeyboard()
                })
            }
            .scrollDismissesKeyboard(isReviewCommentFocused ? .immediately : .interactively)
        }
        .interactiveDismissDisabled()
    }

    private var interactiveSatisfactionRow: some View {
        HStack(spacing: 20) {
            ForEach(PostPaymentSatisfaction.allCases) { option in
                let isSelected = selectedSatisfaction == option
                Button {
                    dismissReviewKeyboard()
                    if selectedSatisfaction == option {
                        selectedSatisfaction = nil
                    } else {
                        selectedSatisfaction = option
                    }
                } label: {
                    VStack(spacing: 10) {
                        Image(option.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .opacity(selectedSatisfaction == nil || isSelected ? 1 : 0.38)
                            .scaleEffect(isSelected ? 1.08 : 1)
                            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedSatisfaction)

                        Text(option.caption)
                            .font(OnCutsFont.caption(weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(
                                isSelected
                                    ? Color.lavaShellCream
                                    : Color.onCutsShellForegroundTertiary
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    .stroke(Color.onCutsShellGlassStroke, lineWidth: 1)
            )
    }

    private func dismissReviewKeyboard() {
        isReviewCommentFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        guard let selectedSatisfaction else {
            await skipWithoutSubmitting()
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            try await BookingSimplePaymentAPI.submitReview(
                bookingId: context.bookingId,
                rating: selectedSatisfaction.rawValue,
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
