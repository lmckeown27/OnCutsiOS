//
//  UpcomingBookingDetailsCard.swift
//  Intera
//
//  Collapsible consumer booking card: avatar + provider + service when closed;
//  schedule, price, status when expanded (DisclosureGroup chevron, like past services).
//

import SwiftUI

struct UpcomingBooking: Hashable, Sendable {
    let serviceName: String
    let barberName: String
    let providerAvatarURL: URL?
    let appointmentTime: String
    let appointmentDate: String
    let price: String
    let isConfirmed: Bool
}

extension UpcomingBooking {
    private static let appointmentDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static let priceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    init(row: ConsumerBookingSimpleRow) {
        serviceName = row.displayServiceName
        barberName = row.barberName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Provider"
        providerAvatarURL = ProfileImageURLResolver.url(from: row.barberAvatar)

        if let scheduledAt = row.scheduledAtDate {
            appointmentTime = BookingPacificSchedule.displayTimeWithMinutes(from: scheduledAt)
            appointmentDate = Self.appointmentDateFormatter.string(from: scheduledAt)
        } else {
            appointmentTime = "—"
            appointmentDate = "—"
        }

        if let cents = row.priceUsdCents, cents > 0 {
            let dollars = Decimal(cents) / 100
            price = Self.priceFormatter.string(from: NSDecimalNumber(decimal: dollars)) ?? "—"
        } else {
            price = "—"
        }

        let status = row.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        isConfirmed = status == "ACCEPTED"
    }
}

struct UpcomingBookingDetailsCard: View {
    let booking: UpcomingBooking
    var isCollapsible: Bool = true
    var onOpenBookingDetail: (() -> Void)? = nil

    @State private var isExpanded = false

    private let avatarSize: CGFloat = 40
    private let avatarCornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if isCollapsible {
                DisclosureGroup(isExpanded: $isExpanded) {
                    expandedDetails
                        .padding(.top, 8)
                } label: {
                    collapsedSummary
                }
                .tint(Color.oliveGreen)
            } else {
                VStack(spacing: 12) {
                    collapsedSummary
                    Divider()
                    schedulePriceStatusRow
                }
            }
        }
    }

    private var collapsedSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            providerAvatar

            VStack(alignment: .leading, spacing: 2) {
                Text(booking.barberName)
                    .font(InteraFont.headlineSmall)
                    .foregroundStyle(Color.lavaShellCream)
                    .lineLimit(2)
                Text(booking.serviceName)
                    .font(InteraFont.subheadline.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isCollapsible {
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            schedulePriceStatusRow

            if let onOpenBookingDetail {
                Button(action: onOpenBookingDetail) {
                    bookingDetailLinkRow
                }
                .buttonStyle(UpcomingBookingDetailLinkButtonStyle())
                .accessibilityHint("Opens full booking details")
            }
        }
    }

    private var bookingDetailLinkRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Booking details")
                .font(InteraFont.subheadline.weight(.semibold))
                .foregroundStyle(Color.lavaShellCream)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(InteraFont.caption.weight(.bold))
                .foregroundStyleInteraShellIconSecondary()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var schedulePriceStatusRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(booking.appointmentTime)
                    .font(InteraFont.body.weight(.bold).monospacedDigit())
                    .foregroundStyleOliveGreen()
                Text(booking.appointmentDate)
                    .font(InteraFont.caption.weight(.medium))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            .fixedSize()

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(booking.price)
                    .font(InteraFont.body.weight(.bold))
                    .foregroundStyle(Color.lavaShellCream)
                    .monospacedDigit()
                statusBadge
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var providerAvatar: some View {
        Group {
            if let url = booking.providerAvatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(RoundedRectangle(cornerRadius: avatarCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: avatarCornerRadius, style: .continuous)
                .stroke(Color.lavaShellCream.opacity(0.22), lineWidth: 0.75)
        }
        .accessibilityLabel("Photo of \(booking.barberName)")
    }

    private var avatarPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: avatarCornerRadius, style: .continuous)
                .fill(Color.oliveGreen.opacity(0.12))
            Text(booking.barberName.prefix(1).uppercased())
                .font(InteraFont.title3.weight(.bold))
                .foregroundStyleOliveGreen()
        }
        .frame(width: avatarSize, height: avatarSize)
    }

    private var statusBadge: some View {
        let label = booking.isConfirmed ? "Confirmed" : "Pending"

        return Text(label)
            .font(InteraFont.caption2.weight(.semibold))
            .foregroundStyleOliveGreen()
    }
}

private struct UpcomingBookingDetailLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.oliveGreen.opacity(0.24)
                            : Color.lavaShellCream.opacity(0.1)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        Color.lavaShellCream.opacity(configuration.isPressed ? 0.38 : 0.2),
                        lineWidth: 0.5
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if DEBUG
#Preview("Collapsed upcoming") {
    UpcomingBookingDetailsCard(
        booking: UpcomingBooking(
            serviceName: "Precision Executive Scissor Cut & Hot Towel Shave",
            barberName: "Alex Barber",
            providerAvatarURL: nil,
            appointmentTime: "2:30 PM",
            appointmentDate: "Wed, Apr 2",
            price: "$35.00",
            isConfirmed: true
        ),
        onOpenBookingDetail: nil
    )
    .padding()
    .background(Color.black)
}
#endif
