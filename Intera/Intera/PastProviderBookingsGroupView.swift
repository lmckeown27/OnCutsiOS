//
//  PastProviderBookingsGroupView.swift
//  Intera
//
//  Collapses multiple past services with the same service provider into one card;
//  expanding shows compact rows for each booking.
//

import SwiftUI

struct PastProviderBookingsGroupView: View {
    let group: ConsumerPastProviderGroup
    var scheduleLine: (ConsumerBookingSimpleRow) -> String
    var onRemovePastBooking: ((ConsumerBookingSimpleRow) -> Void)? = nil

    @State private var isExpanded = false
    @State private var rowPendingRemove: ConsumerBookingSimpleRow?
    @State private var confirmRemoveFromList = false

    private var visitSubtitle: String {
        let n = group.bookings.count
        if n == 1 { return "1 past service" }
        return "\(n) past services"
    }

    private var avatarURL: URL? {
        ProfileImageURLResolver.url(from: group.barberAvatar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(group.bookings) { row in
                        nestedPastRow(row: row)
                    }
                }
                .padding(.top, 4)
            } label: {
                groupLabel
            }
            .tint(Color.oliveGreen)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(groupCardBackground)
        .confirmationDialog(
            "Delete this booking from your list?",
            isPresented: $confirmRemoveFromList,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let r = rowPendingRemove {
                    onRemovePastBooking?(r)
                }
                rowPendingRemove = nil
            }
            Button("Cancel", role: .cancel) {
                rowPendingRemove = nil
            }
        } message: {
            Text("It won’t appear on your Bookings page. Your provider still keeps their records.")
        }
    }

    private static let avatarCornerRadius: CGFloat = 6

    private var groupLabel: some View {
        HStack(alignment: .center, spacing: 12) {
            let avatarRect = RoundedRectangle(cornerRadius: Self.avatarCornerRadius, style: .continuous)
            ZStack {
                avatarRect
                    .fill(Color.lavaShellCream.opacity(0.12))
                if let url = avatarURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Image(systemName: "person.crop.square.fill")
                                .font(InteraFont.title2)
                                .foregroundStyle(Color.lavaShellCreamTertiary)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(avatarRect)
                } else {
                    Image(systemName: "person.crop.square.fill")
                        .font(InteraFont.title2)
                        .foregroundStyle(Color.lavaShellCreamTertiary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(avatarRect)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.providerDisplayName)
                    .font(InteraFont.headlineSmall)
                    .foregroundStyle(Color.lavaShellCream)
                Text(visitSubtitle)
                    .font(InteraFont.caption.weight(.semibold))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private func nestedPastRow(row: ConsumerBookingSimpleRow) -> some View {
        NavigationLink(value: ConsumerHomeBookingStackRoute.bookingsTabDetail(row)) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.displayServiceName)
                        .font(InteraFont.subheadline.weight(.semibold))
                        .foregroundStyle(Color.lavaShellCream)
                    HStack(spacing: 6) {
                        Text(scheduleLine(row))
                            .font(InteraFont.caption)
                            .foregroundStyle(Color.lavaShellCream.opacity(0.88))
                        Spacer(minLength: 0)
                        Text(row.displayStatus)
                            .font(InteraFont.caption2.weight(.semibold))
                            .foregroundStyle(Color.lavaShellCreamTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(InteraFont.caption.weight(.bold))
                    .foregroundStyle(Color.oliveGreen)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PastNestedServiceRowButtonStyle())
        .accessibilityHint("Opens booking details")
        .contextMenu {
            if onRemovePastBooking != nil {
                Button(role: .destructive) {
                    rowPendingRemove = row
                    confirmRemoveFromList = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var groupCardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [Color.lavaShellCream.opacity(0.18)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.5
                    )
            }
    }
}

// MARK: - Press feedback (NavigationLink + plain looked static)

private struct PastNestedServiceRowButtonStyle: ButtonStyle {
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
