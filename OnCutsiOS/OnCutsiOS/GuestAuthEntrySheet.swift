//
//  GuestAuthEntrySheet.swift
//  Intera
//
//  First step when a guest taps Profile: Sign In vs Sign Up.
//

import OnCutsModule
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct GuestAuthEntrySheet: View {
    @Binding var isPresented: Bool
    /// Called before the sheet is dismissed; use to record what to present next in `onDismiss`.
    let onSignIn: () -> Void
    let onSignUp: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                PrimaryButton(
                    title: "Sign In",
                    action: {
                        onSignIn()
                        isPresented = false
                    },
                    isLoading: false,
                    isDisabled: false,
                    size: .large
                )

                PrimaryButton(
                    title: "Sign Up",
                    action: {
                        onSignUp()
                        isPresented = false
                    },
                    isLoading: false,
                    isDisabled: false,
                    size: .large
                )

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
