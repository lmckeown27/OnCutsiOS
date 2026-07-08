//
//  BookingCard.swift
//  OnCuts
//
//  Card component for displaying booking information
//

import SwiftUI

struct BookingCard: View {
    let booking: Booking
    var onTap: (() -> Void)? = nil
    var showActions: Bool = false
    var onCancel: (() -> Void)? = nil
    var onMessage: (() -> Void)? = nil
    
    var body: some View {
        OnCutsCard {
            VStack(alignment: .leading, spacing: .space4) {
                // Header with barber info and status
                HStack {
                    AvatarView(
                        imageUrl: booking.barberProfileImage,
                        name: booking.barberName,
                        size: 40
                    )
                    
                    VStack(alignment: .leading, spacing: .space1) {
                        Text(booking.barberName)
                            .font(OnCutsFont.labelLarge)
                            .foregroundStyle(Color.neutral800)
                        
                        Text(booking.serviceName)
                            .font(OnCutsFont.caption)
                            .foregroundStyle(Color.neutral500)
                    }
                    
                    Spacer()
                    
                    StatusBadge(status: booking.status)
                }
                
                Divider()
                
                // Booking details
                VStack(spacing: .space2) {
                    DetailRow(
                        icon: "calendar",
                        text: booking.scheduledTime.formatted(date: .abbreviated, time: .omitted)
                    )
                    
                    DetailRow(
                        icon: "clock",
                        text: booking.scheduledTime.formatted(date: .omitted, time: .shortened)
                    )
                    
                    if let location = booking.location {
                        DetailRow(
                            icon: "mappin.circle",
                            text: location
                        )
                    }
                    
                    DetailRow(
                        icon: "dollarsign.circle",
                        text: String(format: "$%.2f", booking.servicePrice)
                    )
                }
                
                // Actions
                if showActions {
                    HStack(spacing: .space3) {
                        if let onMessage = onMessage {
                            PrimaryButton(
                                title: "Message",
                                action: onMessage,
                                variant: .outline,
                                size: .small
                            )
                        }
                        
                        if booking.canCancel, let onCancel = onCancel {
                            PrimaryButton(
                                title: "Cancel",
                                action: onCancel,
                                variant: .danger,
                                size: .small
                            )
                        }
                    }
                }
            }
        }
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: .space2) {
            Image(systemName: icon)
                .font(OnCutsFont.caption)
                .foregroundStyle(Color.neutral400)
                .frame(width: 16)
            
            Text(text)
                .font(OnCutsFont.bodySmall)
                .foregroundStyle(Color.neutral600)
        }
    }
}

// MARK: - Booking Model

struct Booking: Identifiable, Codable {
    let id: String
    let consumerId: String
    let barberId: String
    let barberName: String
    let barberProfileImage: String?
    let serviceName: String
    let servicePrice: Double
    let scheduledTime: Date
    let location: String?
    let status: BookingStatus
    let notes: String?
    
    var canCancel: Bool {
        status == .pending || status == .accepted
    }
    
    // Mock data
    static let mockUpcoming = Booking(
        id: "1",
        consumerId: "user-1",
        barberId: "barber-1",
        barberName: "Jordan Smith",
        barberProfileImage: nil,
        serviceName: "Haircut & Fade",
        servicePrice: 30.00,
        scheduledTime: Date().addingTimeInterval(86400), // Tomorrow
        location: "Student Center",
        status: .accepted,
        notes: nil
    )
    
    static let mockPending = Booking(
        id: "2",
        consumerId: "user-1",
        barberId: "barber-2",
        barberName: "Alex Johnson",
        barberProfileImage: nil,
        serviceName: "Beard Trim",
        servicePrice: 15.00,
        scheduledTime: Date().addingTimeInterval(172800), // 2 days
        location: "Dorm Lounge",
        status: .pending,
        notes: "Please bring fade attachment"
    )
    
    static let mockCompleted = Booking(
        id: "3",
        consumerId: "user-1",
        barberId: "barber-1",
        barberName: "Jordan Smith",
        barberProfileImage: nil,
        serviceName: "Haircut",
        servicePrice: 25.00,
        scheduledTime: Date().addingTimeInterval(-86400), // Yesterday
        location: "Student Center",
        status: .completed,
        notes: nil
    )
    
    static let mocks: [Booking] = [mockUpcoming, mockPending, mockCompleted]
    
    // MARK: - Beauty Service Booking Mocks
    
    /// Mock bookings for beauty services
    static let beautyMocks: [Booking] = [
        // Upcoming makeup appointment
        Booking(
            id: "beauty-301",
            consumerId: "user-100",
            barberId: "beauty-201",
            barberName: "Maya Chen",
            barberProfileImage: "https://i.pravatar.cc/300?img=47",
            serviceName: "Event Makeup",
            servicePrice: 75.0,
            scheduledTime: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
            location: "Student Center - Room 204",
            status: .accepted,
            notes: "Formal event - natural glam look"
        ),
        
        // Upcoming lash appointment
        Booking(
            id: "beauty-302",
            consumerId: "user-100",
            barberId: "beauty-206",
            barberName: "Victoria Lee",
            barberProfileImage: "https://i.pravatar.cc/300?img=27",
            serviceName: "Classic Lash Set",
            servicePrice: 120.0,
            scheduledTime: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date(),
            location: "Lash Luxe Studio",
            status: .pending,
            notes: "First time getting lashes"
        ),
        
        // Completed nail appointment
        Booking(
            id: "beauty-303",
            consumerId: "user-100",
            barberId: "beauty-203",
            barberName: "Jasmine Torres",
            barberProfileImage: "https://i.pravatar.cc/300?img=49",
            serviceName: "Gel Manicure",
            servicePrice: 45.0,
            scheduledTime: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
            location: "Campus Nails",
            status: .completed,
            notes: nil
        ),
        
        // Completed braiding appointment
        Booking(
            id: "beauty-304",
            consumerId: "user-100",
            barberId: "beauty-209",
            barberName: "Keisha Washington",
            barberProfileImage: "https://i.pravatar.cc/300?img=28",
            serviceName: "Knotless Box Braids",
            servicePrice: 180.0,
            scheduledTime: Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date(),
            location: "Braids by Keisha Studio",
            status: .completed,
            notes: "Medium length, brought own hair"
        )
    ]
}

// MARK: - Preview

#Preview("Single Card") {
    BookingCard(
        booking: .mockUpcoming,
        showActions: true,
        onCancel: { print("Cancel") },
        onMessage: { print("Message") }
    )
    .padding()
    .background(Color.neutral50)
}

#Preview("List") {
    ScrollView {
        VStack(spacing: .space4) {
            Text("UPCOMING")
                .font(OnCutsFont.labelSmall)
                .foregroundStyle(Color.neutral500)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach([Booking.mockUpcoming, Booking.mockPending]) { booking in
                BookingCard(
                    booking: booking,
                    showActions: true,
                    onCancel: { print("Cancel \(booking.id)") },
                    onMessage: { print("Message") }
                )
            }
            
            Text("PAST")
                .font(OnCutsFont.labelSmall)
                .foregroundStyle(Color.neutral500)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, .space4)
            
            BookingCard(booking: .mockCompleted)
        }
        .padding()
    }
    .background(Color.neutral50)
}
