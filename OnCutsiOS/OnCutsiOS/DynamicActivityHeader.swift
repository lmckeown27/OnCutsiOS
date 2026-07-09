//
//  DynamicActivityHeader.swift
//  OnCuts
//
//  Home “glass hero” pill for the next active booking (today or upcoming): countdown, barber thumb — detail via parent navigation.
//

import OnCutsModule
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum HomeActivityHeaderHaptics {
    #if os(iOS)
    static func lightTap() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }
    #else
    static func lightTap() {}
    #endif
}

// MARK: - Models

/// Drives time-aware mesh colors and motion on the consumer browse backdrop.
enum HomeBookingMeshAccent: Equatable, Sendable {
    case calm
    case today
    case urgent
}

/// Single highlighted booking for the home chrome (earliest active **today** or **upcoming** appointment).
struct HomeTodayBookingHighlight: Identifiable, Equatable, Sendable {
    let id: String
    /// Original API row — opens `ConsumerBookingDetailView` from the floating reminder.
    let sourceRow: ConsumerBookingSimpleRow
    let barberId: String?
    let barberDisplayName: String
    let barberAvatarURL: URL?
    let serviceTitle: String
    let scheduledAt: Date
    let statusLabel: String

    init?(row: ConsumerBookingSimpleRow) {
        guard let appt = row.toUserProfileAppointment() else { return nil }
        self.id = row.id
        self.sourceRow = row
        self.barberId = row.barberId
        self.barberDisplayName = appt.providerName
        self.barberAvatarURL = ProfileImageURLResolver.url(from: row.barberAvatar)
        self.serviceTitle = appt.serviceName
        self.scheduledAt = appt.scheduledAt
        self.statusLabel = row.displayStatus
    }

    /// Earliest **PENDING** or **ACCEPTED** booking in **Today** or **Upcoming** — any future slot, not only calendar-today.
    static func pickTodayHighlight(
        from rows: [ConsumerBookingSimpleRow],
        now: Date = Date(),
        calendar: Calendar = BookingPacificSchedule.pacificCalendar
    ) -> HomeTodayBookingHighlight? {
        let candidates = rows.filter { row in
            let u = row.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard u == "PENDING" || u == "ACCEPTED" else { return false }
            switch row.scheduleSegment(now: now, calendar: calendar) {
            case .today, .upcoming:
                return true
            case .past:
                return false
            }
        }
        guard !candidates.isEmpty else { return nil }
        let sorted = candidates.sorted { a, b in
            let da = a.toUserProfileAppointment()?.scheduledAt ?? .distantFuture
            let db = b.toUserProfileAppointment()?.scheduledAt ?? .distantFuture
            return da < db
        }
        return HomeTodayBookingHighlight(row: sorted[0])
    }

    func meshAccent(at now: Date) -> HomeBookingMeshAccent {
        let until = scheduledAt.timeIntervalSince(now)
        if until > 24 * 60 * 60 { return .calm }
        if until > 0, until <= 15 * 60 { return .urgent }
        if until <= 0, until >= -45 * 60 { return .urgent }
        if BookingPacificSchedule.isSamePacificBookingDay(scheduledAt: scheduledAt, now: now) {
            return .today
        }
        return .calm
    }

    var isScheduledToday: Bool {
        BookingPacificSchedule.isSamePacificBookingDay(scheduledAt: scheduledAt)
    }
}

/// Completed visit **awaiting consumer payment** (e.g. after **Pay later** on the takeover). Mirrors `ChatViewModel.syncPaymentTakeover` ordering.
struct HomePendingPaymentHighlight: Identifiable, Equatable, Sendable {
    let id: String
    /// Original row — drives `BookingPaymentRequestPayload.from` / takeover presentation.
    let sourceRow: ConsumerBookingSimpleRow
    let barberDisplayName: String
    let barberAvatarURL: URL?
    let serviceTitle: String
    let priceFormatted: String

    private init?(row: ConsumerBookingSimpleRow) {
        guard let payload = BookingPaymentRequestPayload.from(bookingRow: row) else { return nil }
        id = row.id
        sourceRow = row
        barberDisplayName = payload.barberName
        barberAvatarURL = ProfileImageURLResolver.url(from: row.barberAvatar)
        serviceTitle = payload.displayServiceName
        priceFormatted = payload.priceFormatted
    }

    static func pickAwaitingPayment(from rows: [ConsumerBookingSimpleRow]) -> HomePendingPaymentHighlight? {
        let sorted = rows
            .filter { BookingPaymentRequestPayload.from(bookingRow: $0) != nil }
            .sorted { a, b in
                let da = a.scheduledAtDate ?? .distantPast
                let db = b.scheduledAtDate ?? .distantPast
                if da != db { return da > db }
                return a.id > b.id
            }
        guard let first = sorted.first else { return nil }
        return HomePendingPaymentHighlight(row: first)
    }
}

// MARK: - Home booking reminder schedule line

/// Updates on **minute** boundaries (solid cream line in the home reminder card): `{time} Today`, `Tomorrow {time}`, or a day label — never an hours/minutes countdown.
struct AppointmentMinuteCountdownText: View {
    let scheduledAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(
                AppointmentReminderScheduleLine.format(
                    scheduledAt: scheduledAt,
                    now: context.date
                )
            )
        }
    }
}

/// Copy for the home booking reminder (Pacific wall clock; no `Starts in 2h 15m` style strings).
enum AppointmentReminderScheduleLine {
    static func format(scheduledAt: Date, now: Date) -> String {
        let delta = scheduledAt.timeIntervalSince(now)
        let time = BookingPacificSchedule.displayTimeWithMinutes(from: scheduledAt)

        if delta > 0 {
            switch BookingPacificSchedule.pacificCalendarDayOffset(from: now, to: scheduledAt) {
            case 0:
                return "\(time) Today"
            case 1:
                return "Tomorrow \(time)"
            case 2...6:
                let day = BookingPacificSchedule.displayAbbreviatedPacificDay(from: scheduledAt)
                return "\(day) · \(time)"
            default:
                return BookingPacificSchedule.displayAbbreviatedPacificDayWithTime(from: scheduledAt)
            }
        }

        if delta > -45 * 60 {
            return BookingPacificSchedule.isSamePacificBookingDay(scheduledAt: scheduledAt, now: now)
                ? "Happening now"
                : "In progress"
        }
        return BookingPacificSchedule.isSamePacificBookingDay(scheduledAt: scheduledAt, now: now)
            ? "Earlier today"
            : "Was scheduled"
    }
}

struct AppointmentLiveCountdownText: View {
    let scheduledAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(AppointmentReminderScheduleLine.format(scheduledAt: scheduledAt, now: context.date))
        }
    }
}

// MARK: - Floating glass reminder (tap → parent opens booking detail for the highlighted row)

/// Compact frosted card below the utility pill: **provider** in `TimelineSectionHeader` “Today” weight, **service** in `headlineSmall` (same as booking rows), schedule line (`{time} Today`, `Tomorrow {time}`, …) in solid cream.
@available(iOS 26.0, macOS 26.0, *)
struct HomeTodayBookingReminderGlassCard: View {
    let highlight: HomeTodayBookingHighlight
    let onTap: () -> Void

    private let corner: CGFloat = 20
    /// Matches list cards (`ServiceProviderCard`): square thumb — same 12/80 corner ratio as 80×80 list images (`64 × 12/80 ≈ 10`).
    private let avatarSize: CGFloat = 64
    private let avatarCornerRadius: CGFloat = 10

    var body: some View {
        Button {
            HomeActivityHeaderHaptics.lightTap()
            onTap()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                providerAvatar
                VStack(alignment: .leading, spacing: 4) {
                    Text(highlight.barberDisplayName)
                        .font(OnCutsFont.system(size: 28, weight: .bold, design: .default))
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                    Text(serviceAndStatusLine)
                        .font(OnCutsFont.headlineSmall)
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    AppointmentMinuteCountdownText(scheduledAt: highlight.scheduledAt)
                        .font(OnCutsFont.subheadline(weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right.circle.fill")
                    .font(OnCutsFont.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.lavaShellCream.opacity(0.55))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.38), lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityLabel(
            highlight.isScheduledToday
                ? "Today’s appointment, \(highlight.barberDisplayName), \(serviceAndStatusLine)"
                : "Upcoming appointment, \(highlight.barberDisplayName), \(serviceAndStatusLine)"
        )
    }

    private var serviceAndStatusLine: String {
        let service = highlight.serviceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = highlight.statusLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !status.isEmpty else { return service }
        guard !service.isEmpty else { return status }
        return "\(service) · \(status)"
    }

    private var providerAvatar: some View {
        Group {
            if let url = highlight.barberAvatarURL {
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
                .stroke(Color.white.opacity(0.35), lineWidth: 0.75)
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: avatarCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.1))
            Text(highlight.barberDisplayName.prefix(1).uppercased())
                .font(OnCutsFont.title3(weight: .bold))
                .foregroundStyle(Color.lavaShellCream.opacity(0.85))
        }
        .frame(width: avatarSize, height: avatarSize)
    }
}

/// Home stripe: reopen in-app checkout when payment was deferred or the takeover was dismissed.
@available(iOS 26.0, macOS 26.0, *)
struct HomePendingPaymentReminderGlassCard: View {
    let highlight: HomePendingPaymentHighlight
    let onTap: () -> Void

    private let corner: CGFloat = 20
    private let avatarSize: CGFloat = 64
    private let avatarCornerRadius: CGFloat = 10

    var body: some View {
        Button {
            HomeActivityHeaderHaptics.lightTap()
            onTap()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                providerAvatar
                VStack(alignment: .leading, spacing: 4) {
                    Text("Payment due")
                        .font(OnCutsFont.subheadline(weight: .semibold))
                        .foregroundStyle(Color.lavaShellCream.opacity(0.92))
                    Text(highlight.barberDisplayName)
                        .font(OnCutsFont.system(size: 28, weight: .bold, design: .default))
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                    Text("\(highlight.serviceTitle) · \(highlight.priceFormatted)")
                        .font(OnCutsFont.headlineSmall)
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "creditcard.circle.fill")
                    .font(OnCutsFont.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.lavaShellCream.opacity(0.55))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.38), lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityLabel("Payment due, \(highlight.barberDisplayName), \(highlight.serviceTitle), \(highlight.priceFormatted)")
    }

    private var providerAvatar: some View {
        Group {
            if let url = highlight.barberAvatarURL {
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
                .stroke(Color.white.opacity(0.35), lineWidth: 0.75)
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: avatarCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.1))
            Text(highlight.barberDisplayName.prefix(1).uppercased())
                .font(OnCutsFont.title3(weight: .bold))
                .foregroundStyle(Color.lavaShellCream.opacity(0.85))
        }
        .frame(width: avatarSize, height: avatarSize)
    }
}
