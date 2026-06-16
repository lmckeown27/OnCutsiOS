//
//  BookingTimelineRow.swift
//  Intera
//
//  Modular row for the bookings timeline: past (muted), today (emphasis + tap → detail),
//  upcoming (time-forward).
//

import SwiftUI

struct BookingTimelineRow: View {
    let row: ConsumerBookingSimpleRow
    let position: TimelinePosition
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    let scheduleLine: String
    var hasActiveConsumerBooking: Bool = false
    var onShowLogin: () -> Void = {}
    var onRemovePastBooking: ((ConsumerBookingSimpleRow) -> Void)? = nil

    @State private var confirmRemoveFromList = false

    private var providerLine: String {
        row.barberName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Provider"
    }

    var body: some View {
        contentColumn
            .padding(.vertical, position == .today ? 10 : 6)
    }

    // MARK: - Card column

    @ViewBuilder
    private var contentColumn: some View {
        switch position {
        case .past:
            pastCard
        case .today:
            todayCard
        case .upcoming:
            upcomingCard
        }
    }

    private var pastCard: some View {
        NavigationLink(value: ConsumerHomeBookingStackRoute.bookingsTabDetail(row)) {
            compactLabels
                .opacity(0.5)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground(elevated: false))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if onRemovePastBooking != nil {
                Button(role: .destructive) {
                    confirmRemoveFromList = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete this booking from your list?",
            isPresented: $confirmRemoveFromList,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onRemovePastBooking?(row)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It won’t appear on your Bookings page. Your provider still keeps their records.")
        }
    }

    private var upcomingCard: some View {
        UpcomingBookingDetailsCard(
            booking: UpcomingBooking(row: row),
            isCollapsible: true,
            detailRoute: ConsumerHomeBookingStackRoute.bookingsTabDetail(row)
        )
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(elevated: false))
    }

    private var todayCard: some View {
        NavigationLink(value: ConsumerHomeBookingStackRoute.bookingsTabDetail(row)) {
            UpcomingBookingDetailsCard(
                booking: UpcomingBooking(row: row),
                isCollapsible: false,
                detailRoute: nil
            )
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(elevated: true))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var compactLabels: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.displayServiceName)
                .font(InteraFont.headlineSmall)
                .foregroundStyle(Color.lavaShellCream)
            Text(providerLine)
                .font(InteraFont.subheadline)
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Text(scheduleLine)
                .font(InteraFont.caption)
                .foregroundStyle(Color.lavaShellCream.opacity(position == .past ? 0.62 : 0.92))
            Text(row.displayStatus)
                .font(InteraFont.caption2.weight(.semibold))
                .foregroundStyle(Color.lavaShellCreamTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cardBackground(elevated: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        elevated
                            ? LinearGradient(
                                colors: [Color.oliveGreen.opacity(0.85), Color.oliveGreen.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(colors: [Color.lavaShellCream.opacity(0.14)], startPoint: .top, endPoint: .bottom),
                        lineWidth: elevated ? 1.5 : 0.5
                    )
            }
            .shadow(color: elevated ? Color.oliveGreen.opacity(0.22) : .clear, radius: elevated ? 12 : 0, y: elevated ? 4 : 0)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
