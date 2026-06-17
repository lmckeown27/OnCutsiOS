//
//  MessagingInboxConversationCards.swift
//  Intera
//
//  Containerized conversation cards for the consumer messaging inbox — explicit tap targets,
//  action ribbon, and unread affordances (hub Messages tab + legacy MessagingView).
//

import SwiftUI

// MARK: - Display model

/// Normalized inbox row for card rendering (maps API DTOs and `ChatViewModel.PreviewRow`).
struct MessageThreadDisplayModel: Identifiable, Equatable {
    let id: String
    let providerTitle: String
    let counterpartyAvatarURLString: String?
    let messagePreview: String?
    let lastMessageSenderId: String?
    let occupationLine: String
    let scheduledDisplay: String?
    let unreadCount: Int
    let isTerminalDim: Bool

    var trimmedPreview: String {
        (messagePreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var messageBoxDisplayText: String {
        trimmedPreview.isEmpty ? "No messages yet" : trimmedPreview
    }

    var messageBoxIsPlaceholder: Bool {
        trimmedPreview.isEmpty
    }

    var isUnread: Bool {
        unreadCount > 0
    }

    init(row: ChatViewModel.PreviewRow) {
        id = row.id
        providerTitle = row.inboxResolvedProviderTitle
        counterpartyAvatarURLString = row.inboxCounterpartyAvatarURLString
        messagePreview = row.lastMessagePreview
        lastMessageSenderId = row.lastMessageSenderId
        occupationLine = MessagingProviderRoleLine.occupationAndServicePresentable(booking: row.booking)
        scheduledDisplay = row.booking?.inboxCompactScheduledDisplay
        unreadCount = row.unreadCount ?? 0
        isTerminalDim = row.booking?.inboxRowIsTerminalPastContinuum == true
    }

    init(dto: MessagingConversationRowDTO) {
        id = dto.id
        providerTitle = dto.inboxResolvedProviderTitle
        counterpartyAvatarURLString = dto.inboxCounterpartyAvatarURLString
        messagePreview = dto.lastMessagePreview
        lastMessageSenderId = dto.lastMessageSenderId
        occupationLine = MessagingProviderRoleLine.occupationAndServicePresentable(booking: dto.booking)
        scheduledDisplay = dto.booking?.inboxCompactScheduledDisplay
        unreadCount = dto.unreadCount ?? 0
        isTerminalDim = dto.booking?.inboxRowIsTerminalPastContinuum == true
    }

    func lastMessageIsFromCounterparty(currentUserId: String) -> Bool {
        let me = currentUserId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !me.isEmpty else { return isUnread }
        if let sid = lastMessageSenderId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !sid.isEmpty {
            return sid != me
        }
        return isUnread
    }
}

// MARK: - Press feedback

/// Tactile scale + opacity on press; keeps label colors (no default NavigationLink blue wash).
struct ConversationCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Card

private enum ConversationInboxCardMetrics {
    static let cornerRadius: CGFloat = 14
    static let avatarSize: CGFloat = 72
    static let avatarCornerRadius: CGFloat = 14
    static let cardShadowRadius: CGFloat = 6
    static let cardShadowY: CGFloat = 3
    static let unreadBorderWidth: CGFloat = 1.5
    static let providerNameFont = InteraFont.system(size: 22, weight: .bold, design: .default)
    static let previewFont = InteraFont.system(size: 16, weight: .regular, design: .serif)
    static let previewLineSpacing: CGFloat = 3
    static let metaFont = InteraFont.system(size: 13, weight: .medium, design: .default)
    static let metaKerning: CGFloat = 1.4
}

struct ConversationInboxThreadCard: View {
    let model: MessageThreadDisplayModel
    let currentUserId: String

    private var messagePreviewBoxIsLit: Bool {
        !model.messageBoxIsPlaceholder && model.lastMessageIsFromCounterparty(currentUserId: currentUserId)
    }

    private var messageBoxTextColor: Color {
        if model.messageBoxIsPlaceholder { return Color.lavaShellCreamTertiary }
        return messagePreviewBoxIsLit ? Color.lavaShellCream : Color.lavaShellCreamTertiary
    }

    private var messageBoxFill: Color {
        if model.messageBoxIsPlaceholder { return Color.white.opacity(0.06) }
        return messagePreviewBoxIsLit ? Color.white.opacity(0.16) : Color.white.opacity(0.08)
    }

    private var messageBoxStroke: Color {
        if model.messageBoxIsPlaceholder { return Color.lavaShellCream.opacity(0.14) }
        return messagePreviewBoxIsLit ? Color.lavaShellCream.opacity(0.38) : Color.lavaShellCream.opacity(0.16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardBody
            actionRibbon
        }
        .background {
            RoundedRectangle(cornerRadius: ConversationInboxCardMetrics.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .shadow(
                    color: Color.black.opacity(0.28),
                    radius: ConversationInboxCardMetrics.cardShadowRadius,
                    x: 0,
                    y: ConversationInboxCardMetrics.cardShadowY
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: ConversationInboxCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(
                    model.isUnread ? Color.blue.opacity(0.3) : Color.lavaShellCream.opacity(0.12),
                    lineWidth: model.isUnread ? ConversationInboxCardMetrics.unreadBorderWidth : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: ConversationInboxCardMetrics.cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: ConversationInboxCardMetrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens your conversation with this provider.")
    }

    private var accessibilitySummary: String {
        var parts = [model.providerTitle]
        if model.isUnread { parts.append("New message") }
        parts.append(model.messageBoxDisplayText)
        if !model.occupationLine.isEmpty { parts.append(model.occupationLine) }
        return parts.joined(separator: ", ")
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(
                    imageUrl: model.counterpartyAvatarURLString,
                    name: model.providerTitle,
                    size: ConversationInboxCardMetrics.avatarSize,
                    fontSize: 28,
                    clipStyle: .square(cornerRadius: ConversationInboxCardMetrics.avatarCornerRadius)
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.providerTitle)
                        .font(ConversationInboxCardMetrics.providerNameFont)
                        .foregroundStyle(Color.lavaShellCream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(model.isTerminalDim ? 0.72 : 1)

                    Text(model.messageBoxDisplayText)
                        .font(ConversationInboxCardMetrics.previewFont)
                        .foregroundStyle(messageBoxTextColor)
                        .lineSpacing(ConversationInboxCardMetrics.previewLineSpacing)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(messageBoxFill)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(messageBoxStroke, lineWidth: 1)
                        }
                }
            }

            if !model.occupationLine.isEmpty || !(model.scheduledDisplay ?? "").isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if !model.occupationLine.isEmpty {
                        Text(model.occupationLine)
                            .font(ConversationInboxCardMetrics.metaFont)
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .kerning(ConversationInboxCardMetrics.metaKerning)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    if let sched = model.scheduledDisplay?.nonEmpty {
                        Spacer(minLength: 8)
                        Text(sched)
                            .font(ConversationInboxCardMetrics.metaFont)
                            .foregroundStyle(Color.lavaShellCreamSecondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                }
                .opacity(model.isTerminalDim ? 0.72 : 1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRibbon: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if model.isUnread {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                        Text("New Message")
                            .font(InteraFont.subheadline.weight(.bold))
                            .foregroundStyle(Color.blue)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("View Conversation")
                        .foregroundStyleOliveGreen()
                    Image(systemName: "chevron.right")
                        .font(InteraFont.caption.weight(.bold))
                        .foregroundStyleInteraShellIconSecondary()
                }
                .font(InteraFont.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
