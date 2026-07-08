//
//  PhoneNumberSignInPlaceholderView.swift
//  OnCuts
//
//  Phone/SMS sign-in entry point. Full Firebase + backend linking can replace this later.
//

import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct PhoneNumberSignInPlaceholderView: View {
    @State private var phoneDigits = ""
    @State private var infoMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter your mobile number. We’ll text you a code to sign in.")
                    .font(OnCutsFont.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Phone number", text: $phoneDigits)
                    .textContentType(.telephoneNumber)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    #endif
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    }

                Button {
                    infoMessage = "Phone number sign-in isn’t available in this build yet. Please use email or Google."
                } label: {
                    Text("Send verification code")
                        .font(OnCutsFont.body(weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.oliveGreen)
                .disabled(phoneDigits.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let infoMessage {
                    Text(infoMessage)
                        .font(OnCutsFont.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle("Phone number")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
