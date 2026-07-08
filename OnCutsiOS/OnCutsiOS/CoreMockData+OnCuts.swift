//
//  MockData+OnCuts.swift
//  Intera
//
//  Created by Liam McKeown on 3/8/26.
//
//  Mock data that matches your AWS Cognito + Stripe setup
//

import Foundation

// MARK: - Extended UserSession for OnCuts

extension UserSession {
    
    /// Mock student user with full OnCuts profile
    static let mockStudentComplete = UserSession(
        userId: "us-east-1:12345678-1234-1234-1234-123456789012", // Cognito format
        token: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.mock-token-data", // JWT format
        email: "alex.johnson@university.edu",
        displayName: "Alex Johnson",
        role: .student,
        stripeCustomerId: "cus_PQRsT123456789", // Stripe customer format
        profileImageURL: nil,
        expiresAt: Date().addingTimeInterval(3600), // 1 hour
        refreshToken: nil
    )
    
    /// Mock barber user with full profile
    static let mockBarberComplete = UserSession(
        userId: "us-east-1:87654321-4321-4321-4321-210987654321",
        token: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.mock-barber-token",
        email: "jordan.smith@campuscuts.com",
        displayName: "Jordan Smith",
        role: .barber,
        stripeCustomerId: "cus_XYZaB987654321", // Barbers are also Stripe customers
        profileImageURL: "https://campuscuts-assets.s3.amazonaws.com/profiles/jordan.jpg",
        expiresAt: Date().addingTimeInterval(3600),
        refreshToken: nil
    )
    
    /// Mock admin user
    static let mockAdmin = UserSession(
        userId: "us-east-1:99999999-9999-9999-9999-999999999999",
        token: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.mock-admin-token",
        email: "admin@campuscuts.com",
        displayName: "System Admin",
        role: .admin,
        stripeCustomerId: nil,
        profileImageURL: nil,
        expiresAt: Date().addingTimeInterval(3600),
        refreshToken: nil
    )
}

// MARK: - AWS Cognito Response Models

/// Mock response from AWS Cognito authentication
struct CognitoAuthResponse: Codable {
    let accessToken: String
    let idToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String
    
    static let mockStudent = CognitoAuthResponse(
        accessToken: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.access",
        idToken: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.id",
        refreshToken: "refresh-token-abc123",
        expiresIn: 3600,
        tokenType: "Bearer"
    )
}

/// Mock Cognito user attributes
struct CognitoUserAttributes: Codable {
    let sub: String // User ID (UUID)
    let email: String
    let emailVerified: Bool
    let name: String
    let customRole: String // custom:role
    let customStripeId: String? // custom:stripe_customer_id
    
    static let mockStudent = CognitoUserAttributes(
        sub: "12345678-1234-1234-1234-123456789012",
        email: "alex.johnson@university.edu",
        emailVerified: true,
        name: "Alex Johnson",
        customRole: "student",
        customStripeId: "cus_PQRsT123456789"
    )
    
    static let mockBarber = CognitoUserAttributes(
        sub: "87654321-4321-4321-4321-210987654321",
        email: "jordan.smith@campuscuts.com",
        emailVerified: true,
        name: "Jordan Smith",
        customRole: "barber",
        customStripeId: "cus_XYZaB987654321"
    )
}

// MARK: - Stripe Models

/// Stripe customer data
struct StripeCustomer: Codable {
    let id: String
    let email: String
    let name: String
    let defaultPaymentMethod: String?
    let balance: Int
    let currency: String
    
    static let mockStudent = StripeCustomer(
        id: "cus_PQRsT123456789",
        email: "alex.johnson@university.edu",
        name: "Alex Johnson",
        defaultPaymentMethod: "pm_1234567890abcdef",
        balance: 0,
        currency: "usd"
    )
}

/// Stripe payment method
struct StripePaymentMethod: Codable {
    let id: String
    let type: String
    let card: CardDetails?
    
    struct CardDetails: Codable {
        let brand: String
        let last4: String
        let expMonth: Int
        let expYear: Int
    }
    
    static let mockCard = StripePaymentMethod(
        id: "pm_1234567890abcdef",
        type: "card",
        card: CardDetails(
            brand: "visa",
            last4: "4242",
            expMonth: 12,
            expYear: 2026
        )
    )
}

/// Stripe payment intent (for booking payments)
struct StripePaymentIntent: Codable {
    let id: String
    let amount: Int
    let currency: String
    let status: String
    let clientSecret: String
    
    static let mockBookingPayment = StripePaymentIntent(
        id: "pi_1234567890abcdef",
        amount: 2500, // $25.00
        currency: "usd",
        status: "requires_payment_method",
        clientSecret: "pi_1234567890abcdef_secret_xyz"
    )
}

// MARK: - OnCuts Backend API Models

/// User profile from your backend
struct OnCutsUserProfile: Codable {
    let userId: String
    let email: String
    let displayName: String
    let role: String
    let phoneNumber: String?
    let profileImageURL: String?
    let stripeCustomerId: String?
    let createdAt: Date
    let lastLoginAt: Date
    
    // Student-specific fields
    let university: String?
    let graduationYear: Int?
    
    // Barber-specific fields
    let stripeConnectedAccountId: String? // For receiving payments
    let isVerified: Bool?
    let rating: Double?
    let totalBookings: Int?
    
    static let mockStudent = OnCutsUserProfile(
        userId: "12345678-1234-1234-1234-123456789012",
        email: "alex.johnson@university.edu",
        displayName: "Alex Johnson",
        role: "student",
        phoneNumber: "+1-555-0123",
        profileImageURL: nil,
        stripeCustomerId: "cus_PQRsT123456789",
        createdAt: Date().addingTimeInterval(-86400 * 30), // 30 days ago
        lastLoginAt: Date(),
        university: "State University",
        graduationYear: 2026,
        stripeConnectedAccountId: nil,
        isVerified: nil,
        rating: nil,
        totalBookings: nil
    )
    
    static let mockBarber = OnCutsUserProfile(
        userId: "87654321-4321-4321-4321-210987654321",
        email: "jordan.smith@campuscuts.com",
        displayName: "Jordan Smith",
        role: "barber",
        phoneNumber: "+1-555-0456",
        profileImageURL: "https://campuscuts-assets.s3.amazonaws.com/profiles/jordan.jpg",
        stripeCustomerId: "cus_XYZaB987654321",
        createdAt: Date().addingTimeInterval(-86400 * 90), // 90 days ago
        lastLoginAt: Date(),
        university: nil,
        graduationYear: nil,
        stripeConnectedAccountId: "acct_1234567890abcdef", // For receiving payments
        isVerified: true,
        rating: 4.8,
        totalBookings: 127
    )
}

/// Booking from your backend
struct OnCutsBooking: Codable, Identifiable {
    let id: String
    let studentId: String
    let barberId: String
    let serviceType: String
    let scheduledAt: Date
    let duration: Int // minutes
    let price: Int // cents
    let status: BookingStatus
    let paymentIntentId: String?
    let createdAt: Date
    
    enum BookingStatus: String, Codable {
        case pending
        case confirmed
        case completed
        case cancelled
    }
    
    static let mockUpcoming = OnCutsBooking(
        id: "book_1234567890",
        studentId: "12345678-1234-1234-1234-123456789012",
        barberId: "87654321-4321-4321-4321-210987654321",
        serviceType: "Haircut",
        scheduledAt: Date().addingTimeInterval(86400), // Tomorrow
        duration: 30,
        price: 2500, // $25.00
        status: .confirmed,
        paymentIntentId: "pi_1234567890abcdef",
        createdAt: Date()
    )
}

// MARK: - Helper: Convert Backend Data to UserSession

extension OnCutsUserProfile {
    /// Convert backend profile to UserSession
    func toUserSession(token: String, expiresAt: Date) -> UserSession {
        UserSession(
            userId: self.userId,
            token: token,
            email: self.email,
            displayName: self.displayName,
            role: UserRole(rawValue: self.role) ?? .student,
            stripeCustomerId: self.stripeCustomerId,
            profileImageURL: self.profileImageURL,
            expiresAt: expiresAt,
            refreshToken: nil
        )
    }
}

// MARK: - Mock API Service

/// Mock service that simulates your AWS backend API
final class MockOnCutsAPI {
    
    /// Simulate login
    static func login(email: String, password: String) async throws -> UserSession {
        // Simulate network delay
        try await Task.sleep(for: .seconds(1))
        
        // In production, this would call AWS Cognito
        let cognitoResponse = CognitoAuthResponse.mockStudent
        let _ = email.contains("barber") 
            ? CognitoUserAttributes.mockBarber 
            : CognitoUserAttributes.mockStudent
        
        // Fetch user profile from your backend
        let profile = email.contains("barber")
            ? OnCutsUserProfile.mockBarber
            : OnCutsUserProfile.mockStudent
        
        // Convert to UserSession
        return profile.toUserSession(
            token: cognitoResponse.idToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(cognitoResponse.expiresIn))
        )
    }
    
    /// Simulate fetching user profile
    static func fetchUserProfile(userId: String) async throws -> OnCutsUserProfile {
        try await Task.sleep(for: .seconds(0.5))
        return OnCutsUserProfile.mockStudent
    }
    
    /// Simulate fetching Stripe customer
    static func fetchStripeCustomer(customerId: String) async throws -> StripeCustomer {
        try await Task.sleep(for: .seconds(0.5))
        return StripeCustomer.mockStudent
    }
    
    /// Simulate creating a booking
    static func createBooking(
        barberId: String,
        serviceType: String,
        scheduledAt: Date
    ) async throws -> OnCutsBooking {
        try await Task.sleep(for: .seconds(1))
        
        return OnCutsBooking(
            id: "book_\(UUID().uuidString.prefix(10))",
            studentId: "12345678-1234-1234-1234-123456789012",
            barberId: barberId,
            serviceType: serviceType,
            scheduledAt: scheduledAt,
            duration: 30,
            price: 2500,
            status: .pending,
            paymentIntentId: nil,
            createdAt: Date()
        )
    }
}

// MARK: - Usage Examples

/*
 
 // Example: Login with mock backend
 let session = try await MockOnCutsAPI.login(
     email: "alex.johnson@university.edu",
     password: "password123"
 )
 sessionManager.login(session: session)
 
 // Example: Fetch user profile
 let profile = try await MockOnCutsAPI.fetchUserProfile(
     userId: session.userId
 )
 
 // Example: Create booking
 let booking = try await MockOnCutsAPI.createBooking(
     barberId: "barber-123",
     serviceType: "Haircut",
     scheduledAt: Date().addingTimeInterval(86400)
 )
 
 // Example: Fetch Stripe customer
 if let stripeId = session.stripeCustomerId {
     let customer = try await MockOnCutsAPI.fetchStripeCustomer(
         customerId: stripeId
     )
 }
 
 */
