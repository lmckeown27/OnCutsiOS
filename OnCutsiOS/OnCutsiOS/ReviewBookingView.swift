//
//  ReviewBookingView.swift
//  OnCuts
//
//  Liquid Glass review step: gradient backdrop, hero card, details, price, submit (auth + completion handled by parent).
//

import SwiftUI

struct ReviewBookingView: View {
    let booking: BookingState
    let onSubmit: (BookingState) -> Void

    @State private var frontendConfigStore = PlatformFrontendConfigStore.shared

    private var serviceFeeQuote: ClientServiceAmounts {
        ClientServiceFeeQuoting.quote(
            listedServiceCents: max(0, booking.finalServicePriceUsd) * 100,
            config: frontendConfigStore.config
        )
    }

    var body: some View {
        ZStack {
            OnCutsShellBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    mainGlassPanel
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .reviewBookingHideScrollBackground()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.onCutsShellBackground)
        .navigationTitle("Review")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .tint(Color.oliveGreen)
        .task {
            await frontendConfigStore.refresh()
        }
    }

    private var mainGlassPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroRow

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)

            reviewInfoRow(title: "Service", value: booking.serviceName)
            reviewInfoRow(title: "When", value: formattedScheduledAt)

            confirmAmountBlock

            if !booking.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(booking.location)
                    .font(OnCutsFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack {
                Spacer(minLength: 0)
                PrimaryButton(
                    title: "Submit",
                    action: submitTapped,
                    variant: .shell,
                    size: .footer,
                    isFullWidth: false
                )
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .onCutsGlassSurface(cornerRadius: 20)
    }

    private var heroRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let urlStr = booking.profileImageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            heroPlaceholder
                        }
                    }
                } else {
                    heroPlaceholder
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(booking.barberDisplayName)
                    .font(OnCutsLiquidGlassTypography.title(18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .onCutsGlassSurface(cornerRadius: 20)
    }

    private var heroPlaceholder: some View {
        Text(booking.barberDisplayName.prefix(2).uppercased())
            .font(OnCutsFont.headline)
            .foregroundStyleOliveGreen()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.brand.opacity(0.15))
    }

    @ViewBuilder
    private var confirmAmountBlock: some View {
        let quote = serviceFeeQuote
        if quote.showsServiceFeeRow {
            VStack(spacing: 10) {
                confirmAmountLine(title: "Service Price", cents: quote.listedServiceCents)
                confirmAmountLine(title: "Service Fee", cents: quote.serviceFeeCents)
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)
                VStack(spacing: 4) {
                    Text("Amount Due upon Booking Acceptance")
                        .font(OnCutsLiquidGlassTypography.title(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(USDCurrencyFormatting.string(cents: quote.chargeAmountCents))
                        .font(OnCutsLiquidGlassTypography.title(34, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            Text("$\(booking.finalServicePriceUsd)")
                .font(OnCutsLiquidGlassTypography.title(34, weight: .bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func confirmAmountLine(title: String, cents: Int) -> some View {
        HStack {
            Text(title)
                .font(OnCutsFont.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(USDCurrencyFormatting.string(cents: cents))
                .font(OnCutsFont.body(weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
    }

    private func reviewInfoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(OnCutsLiquidGlassTypography.title(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(OnCutsFont.body)
                .foregroundStyle(.primary)
        }
    }

    private var formattedScheduledAt: String {
        BookingPacificSchedule.formattedDisplayScheduledTime(booking.scheduledAtPacificISO)
    }

    private func submitTapped() {
        var issues: [String] = []
        let service = booking.serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if service.isEmpty {
            issues.append("Add a service.")
        }
        let loc = booking.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if loc.isEmpty {
            issues.append("Add a location.")
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        iso.timeZone = BookingPacificSchedule.pacificTimeZone
        if iso.date(from: booking.scheduledAtPacificISO) == nil {
            issues.append("Pick a valid date and time.")
        }
        if !issues.isEmpty {
            AlertManager.shared.presentErrorToast(issues.joined(separator: " "))
            return
        }
        onSubmit(booking)
    }
}

// MARK: - Scroll chrome (avoid system grey flash during push)

private extension View {
    @ViewBuilder
    func reviewBookingHideScrollBackground() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
