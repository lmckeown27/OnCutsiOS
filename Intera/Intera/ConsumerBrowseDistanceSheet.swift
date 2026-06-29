//
//  ConsumerBrowseDistanceSheet.swift
//  Intera
//
//  Dating-style “maximum distance” control for the provider browse list.
//

import SwiftUI

struct ConsumerBrowseDistanceSheet: View {
    let onApplied: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var constrainDistance = ConsumerBrowseDistancePreference.constrainBrowseListByDistance
    @State private var miles = ConsumerBrowseDistancePreference.maxDistanceMiles

    private var displayMiles: Int {
        Int(miles.rounded())
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Toggle("Limit providers by distance", isOn: $constrainDistance)
                    .tint(Color.oliveGreen)

                if constrainDistance {
                    Text("Only providers within this radius are included. Closest providers appear first.")
                        .font(InteraFont.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Within \(displayMiles) mi")
                            .font(InteraFont.title2(weight: .semibold))
                        Slider(
                            value: $miles,
                            in: ConsumerBrowseDistancePreference.minimumMiles ... ConsumerBrowseDistancePreference.maximumMiles,
                            step: 1
                        )
                        .tint(Color.oliveGreen)
                        HStack {
                            Text("\(Int(ConsumerBrowseDistancePreference.minimumMiles)) mi")
                                .font(InteraFont.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(Int(ConsumerBrowseDistancePreference.maximumMiles)) mi")
                                .font(InteraFont.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Text("Shows every provider the app can load (same as turning location off for this list). Sorted by rating, not distance.")
                        .font(InteraFont.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Browse distance")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        ConsumerBrowseDistancePreference.constrainBrowseListByDistance = constrainDistance
                        ConsumerBrowseDistancePreference.maxDistanceMiles = miles
                        dismiss()
                        onApplied()
                    }
                    .fontWeight(.semibold)
                }
            }
            .tint(Color.oliveGreen)
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}
