//
//  StatusBadge.swift
//  OnCuts
//
//  Status badge for booking states
//

import SwiftUI

struct StatusBadge: View {
    let status: BookingStatus
    
    var body: some View {
        Text(status.displayName)
            .font(OnCutsFont.labelSmall)
            .fontWeight(.medium)
            .padding(.horizontal, .space2)
            .padding(.vertical, .space1)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }
    
    var statusColor: Color {
        switch status {
        case .pending:
            return .statusPending
        case .accepted, .confirmed:
            return .statusAccepted
        case .completed:
            return .statusCompleted
        case .cancelled, .rejected:
            return .statusCancelled
        case .noShow:
            return .statusNoShow
        }
    }
}

// MARK: - Booking Status Enum

enum BookingStatus: String, Codable, CaseIterable {
    case pending = "PENDING"
    case accepted = "ACCEPTED"
    case confirmed = "CONFIRMED"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
    case rejected = "REJECTED"
    case noShow = "NO_SHOW"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .confirmed: return "Confirmed"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .rejected: return "Rejected"
        case .noShow: return "No Show"
        }
    }
    
    var icon: String {
        switch self {
        case .pending: return "clock.fill"
        case .accepted, .confirmed: return "checkmark.circle.fill"
        case .completed: return "checkmark.seal.fill"
        case .cancelled, .rejected: return "xmark.circle.fill"
        case .noShow: return "person.slash.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: .space3) {
        ForEach(BookingStatus.allCases, id: \.self) { status in
            HStack {
                StatusBadge(status: status)
                Spacer()
                Image(systemName: status.icon)
                    .foregroundStyle(statusColorFor(status))
            }
            .padding(.horizontal)
        }
    }
    .padding()
}

private func statusColorFor(_ status: BookingStatus) -> Color {
    switch status {
    case .pending: return .statusPending
    case .accepted, .confirmed: return .statusAccepted
    case .completed: return .statusCompleted
    case .cancelled, .rejected: return .statusCancelled
    case .noShow: return .statusNoShow
    }
}
