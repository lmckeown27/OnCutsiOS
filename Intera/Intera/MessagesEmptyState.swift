//
//  MessagesEmptyState.swift
//  Intera
//
//  Shown only when `GET /messages/conversations` returns **no rows** yet (`ChatViewModel.rows` empty).
//  Branch B is **not** a “quick reply” widget — it is the **empty-inbox + active booking** affordance so a
//  consumer with a confirmed/pending booking can still open the provider thread while the conversation row appears.
//

import SwiftUI

/// Branches for the signed-in, empty-inbox messaging shell.
enum MessagesEmptyStatePhase: Equatable {
    /// No threads yet — nudge toward discovering providers on the home tab.
    case noBookings
    /// User has a PENDING or ACCEPTED booking but the inbox preview list is still empty (e.g. thread not listed yet).
    case activeBooking(ConsumerBookingSimpleRow)
}

struct MessagesEmptyState: View {
    let phase: MessagesEmptyStatePhase
    /// Dismisses inbox / navigates to browse so the user can find a service provider.
    let onBrowseServiceProviders: () -> Void
    /// Opens the booking’s provider conversation (same hub shell path as other booking message entry points).
    let onOpenBookingConversation: (ConsumerBookingSimpleRow) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch phase {
                case .noBookings:
                    branchNoBookings
                case .activeBooking(let booking):
                    branchActiveBooking(booking: booking)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        #if os(iOS)
        .scrollContentBackground(.hidden)
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Branch A

    private var branchNoBookings: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Text("Find your next service")
                    .font(InteraFont.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.lavaShellCream)

                Text("Book with a service provider to start a private conversation here. Explore people and services near you.")
                    .font(InteraFont.subheadline)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            Button(action: onBrowseServiceProviders) {
                Text("Browse service providers")
                    .font(InteraFont.headline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.oliveGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Branch B

    private func branchActiveBooking(booking: ConsumerBookingSimpleRow) -> some View {
        Button {
            onOpenBookingConversation(booking)
        } label: {
            providerSummaryCard(booking: booking)
        }
        .buttonStyle(EmptyInboxBookingCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens messages with this provider for your booking.")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerSummaryCard(booking: ConsumerBookingSimpleRow) -> some View {
        let name = booking.barberName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Your provider"
        let timeLine = Self.formattedRequestTime(booking.scheduledTime)
        let service = booking.displayServiceName

        return HStack(alignment: .center, spacing: 14) {
            AvatarView(
                imageUrl: booking.barberAvatar,
                name: name,
                size: 58,
                fontSize: 22,
                clipStyle: .square(cornerRadius: 14)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(InteraFont.title3.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .multilineTextAlignment(.leading)

                Text(service)
                    .font(InteraFont.subheadline.weight(.medium))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(timeLine)
                    .font(InteraFont.footnote.weight(.medium))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(InteraFont.body.weight(.semibold))
                .foregroundStyle(Color.lavaShellCream.opacity(0.55))
        }
        .padding(18)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThickMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.15))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
            }
        }
    }

    private static func formattedRequestTime(_ iso: String) -> String {
        guard let d = ConsumerBookingSimpleRow.parseScheduledISO(iso) else {
            return iso
        }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct EmptyInboxBookingCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
