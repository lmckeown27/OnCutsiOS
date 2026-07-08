//
//  MessagingGlassComponents.swift
//  OnCuts
//
//  Layered glass UI for the messaging flow: inbox tiles, liquid bubbles, pinned booking header, motion + haptics.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Motion & haptics

enum MessagingFlowMotion {
    static let messageAppearSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    /// Push/pop for hub Messages → thread (`navigationDestination(item:)`).
    static let threadNavigationPush = Animation.smooth(duration: 0.38)
    /// Delay before bubble insert transitions + animated scroll-to-bottom on first paint.
    static let threadOpenMotionDelay: Duration = .milliseconds(380)
}

enum MessagingFlowHaptics {
    #if os(iOS)
    static func receivedMessage() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func sentMessage() {
        OnCutsLiquidGlassHaptics.notification(.success)
    }
    #else
    static func receivedMessage() {}
    static func sentMessage() {}
    #endif
}

// MARK: - Inbox unread indicator

/// Green dot inside the trailing edge of the latest-message preview when the counterparty sent an unread message.
struct MessagingInboxIncomingUnreadDot: View {
    var body: some View {
        Circle()
            .fill(Color.oliveLight)
            .frame(width: 9, height: 9)
            .accessibilityLabel("Unread message")
    }
}

// MARK: - Inbox tile (ultraThin material shell)

struct MessagingConversationTile<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.lavaShellGlassStroke, lineWidth: 1)
            }
    }
}

// MARK: - Liquid bubble (asymmetric continuous corners)

private enum LiquidBubbleMetrics {
    static let tailLarge: CGFloat = 22
    static let cornerSmall: CGFloat = 7
}

enum MessagingLiquidBubbleShape {
    static func isolated(isFromCurrentUser: Bool) -> UnevenRoundedRectangle {
        let t = LiquidBubbleMetrics.tailLarge
        let s = LiquidBubbleMetrics.cornerSmall
        if isFromCurrentUser {
            return UnevenRoundedRectangle(
                topLeadingRadius: s,
                bottomLeadingRadius: s,
                bottomTrailingRadius: t,
                topTrailingRadius: s,
                style: .continuous
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: s,
            bottomLeadingRadius: t,
            bottomTrailingRadius: s,
            topTrailingRadius: s,
            style: .continuous
        )
    }
}

// MARK: - Outgoing bubble fill (opaque in light mode for contrast on white shell)

enum MessagingOutgoingBubbleStyle {
    static func rimStroke(for colorScheme: ColorScheme, isOutgoing: Bool) -> Color {
        guard isOutgoing else {
            return colorScheme == .dark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.08)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.06)
    }

    static var labelColor: Color { .white }
}

// MARK: - Bubble chrome (text + media)

struct MessagingBubbleChrome<Content: View>: View {
    let isOutgoing: Bool
    private let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(isOutgoing: Bool, @ViewBuilder content: () -> Content) {
        self.isOutgoing = isOutgoing
        self.content = content()
    }

    var body: some View {
        let shape = MessagingLiquidBubbleShape.isolated(isFromCurrentUser: isOutgoing)
        content
            .background {
                if isOutgoing {
                    if colorScheme == .dark {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.oliveGreen.opacity(0.88),
                                    Color.oliveDark.opacity(0.78),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    } else {
                        shape.fill(Color.oliveDark)
                    }
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(
                    MessagingOutgoingBubbleStyle.rimStroke(for: colorScheme, isOutgoing: isOutgoing),
                    lineWidth: 0.5
                )
            }
    }
}

// MARK: - Pinned booking (latest `bookings-simple` row for barber profile id)

struct PinnedBookingHeader: View {
    let barberProfileId: String?
    let sessionManager: AppSessionManager

    @State private var bookings: [ConsumerBookingSimpleRow] = []
    @State private var loadFailed = false

    private var normalizedTarget: String {
        barberProfileId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var latestForBarber: ConsumerBookingSimpleRow? {
        guard !normalizedTarget.isEmpty else { return nil }
        return bookings
            .filter { row in
                let bid = row.barberId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                return !bid.isEmpty && bid == normalizedTarget
            }
            .sorted { a, b in
                let da = a.scheduledAtDate ?? .distantPast
                let db = b.scheduledAtDate ?? .distantPast
                if da != db { return da > db }
                return a.id > b.id
            }
            .first
    }

    var body: some View {
        Group {
            if let row = latestForBarber {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(OnCutsFont.caption(weight: .semibold))
                            .foregroundStyleOnCutsShellIconSecondary()
                        Text("Latest booking")
                            .font(OnCutsFont.caption(weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(row.displayServiceName)
                        .font(OnCutsFont.headlineSmall)
                        .foregroundStyle(.primary)
                    Text(row.displayStatus)
                        .font(OnCutsFont.caption(weight: .semibold))
                        .foregroundStyleOliveGreen(opacity: 0.95)
                    if let when = formattedSchedule(row) {
                        Text(when)
                            .font(OnCutsFont.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let loc = row.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse")
                            .font(OnCutsFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            } else if loadFailed {
                Text("Couldn’t refresh booking details")
                    .font(OnCutsFont.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .task(id: normalizedTarget) {
            await loadBookings()
        }
    }

    private static let displayDF: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func formattedSchedule(_ row: ConsumerBookingSimpleRow) -> String? {
        guard let d = row.scheduledAtDate else { return nil }
        return Self.displayDF.string(from: d)
    }

    @MainActor
    private func loadBookings() async {
        guard sessionManager.isAuthenticated, !normalizedTarget.isEmpty else {
            bookings = []
            return
        }
        loadFailed = false
        do {
            bookings = try await ConsumerBookingsSimpleAPI.fetchConsumerBookings(
                bearerToken: sessionManager.currentSession?.token,
                consumerUserId: sessionManager.currentSession?.userId
            )
        } catch {
            if OnCutsRefreshCancellation.isBenignCancellation(error) { return }
            bookings = []
            loadFailed = true
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
