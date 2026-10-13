//
//  ConsumerBrowseLocationChrome.swift
//  OnCuts
//
//  Web-parity browse location line + device-tracking Off/On toggle.
//

import SwiftUI

/// Location label (tracking On) or place search (tracking Off), plus the device-tracking switch.
struct ConsumerBrowseLocationChrome: View {
    @Bindable var locationController: ConsumerBrowseLocationController
    /// Compact glass header styling vs sticky legacy chrome.
    var usesGlassChrome: Bool = false
    /// When `false`, the location and toggle sit directly on the host surface (e.g. the Discover sheet) with no capsule.
    var showsContainer: Bool = true

    @FocusState private var isPlaceFieldFocused: Bool

    /// Matches the My Operators | Discover switch so the two rows read as one set.
    private static var capsuleHeight: CGFloat { 56 }
    /// Visible suggestion rows before the menu scrolls.
    private static var maxVisibleSuggestionRows: Int { 5 }
    /// Approx. height of one suggestion row (title + subtitle + padding + divider).
    private static var suggestionRowEstimatedHeight: CGFloat { 54 }

    private var showsAttachedDropdown: Bool {
        !locationController.deviceTrackingEnabled
            && locationController.shouldShowPlaceSuggestions
    }

    var body: some View {
        Group {
            if locationController.deviceTrackingEnabled {
                deviceLocationCapsule
            } else {
                manualPlaceBlock
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, usesGlassChrome ? 0 : .space4)
        .padding(.top, usesGlassChrome ? 0 : .space2)
        .padding(.bottom, usesGlassChrome ? 0 : .space1)
        .onChange(of: isPlaceFieldFocused) { _, focused in
            locationController.setPlaceFieldEditing(focused)
        }
        .onChange(of: locationController.placeFieldResignGeneration) { _, _ in
            isPlaceFieldFocused = false
        }
        .onChange(of: locationController.deviceTrackingEnabled) { _, enabled in
            if enabled {
                isPlaceFieldFocused = false
            }
        }
    }

    /// Same frosted capsule as the My Operators | Discover switch: location, then the tracking toggle.
    private var deviceLocationCapsule: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill")
                .font(OnCutsFont.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.oliveGreen)
                .accessibilityHidden(true)
            Text(locationController.locationLabel)
                .font(OnCutsFont.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel("Browse location \(locationController.locationLabel)")
            if !showsContainer {
                Spacer(minLength: 8)
            }
            trackingToggle
        }
        .padding(.leading, showsContainer ? 16 : 0)
        .padding(.trailing, showsContainer ? 6 : 0)
        .frame(minHeight: showsContainer ? Self.capsuleHeight : 44)
        .background {
            if showsContainer {
                Capsule().fill(.ultraThinMaterial)
            }
        }
        .overlay {
            if showsContainer {
                Capsule()
                    .stroke(Color.lavaShellCream, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Container only while suggestions are open, so the dropdown stays readable over the list.
    private var manualPlaceShowsContainer: Bool {
        showsContainer || showsAttachedDropdown
    }

    private var manualPlaceRowHeight: CGFloat {
        showsContainer ? Self.capsuleHeight : 44
    }

    /// City field and tracking toggle share one frosted container; suggestions open beneath without pushing the layout.
    private var manualPlaceBlock: some View {
        Color.clear
            .frame(height: manualPlaceRowHeight)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        placeTextField
                        trackingToggle
                            .padding(.trailing, manualPlaceShowsContainer ? 6 : 0)
                    }
                    .frame(minHeight: manualPlaceRowHeight)

                    if showsAttachedDropdown {
                        connectedSuggestionsDropdown
                    }
                }
                .background {
                    if manualPlaceShowsContainer {
                        RoundedRectangle(cornerRadius: Self.capsuleHeight / 2, style: .continuous)
                            .fill(showsAttachedDropdown ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
                    }
                }
                .overlay {
                    if manualPlaceShowsContainer {
                        RoundedRectangle(cornerRadius: Self.capsuleHeight / 2, style: .continuous)
                            .stroke(
                                isPlaceFieldFocused || showsAttachedDropdown ? Color.oliveGreen : Color.lavaShellCream,
                                lineWidth: 1
                            )
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Self.capsuleHeight / 2, style: .continuous))
                .shadow(
                    color: Color.black.opacity(showsAttachedDropdown ? 0.2 : 0),
                    radius: showsAttachedDropdown ? 12 : 0,
                    y: showsAttachedDropdown ? 6 : 0
                )
                .compositingGroup()
            }
            .zIndex(locationController.isPlaceFieldEditing ? 80 : 1)
    }

    private var placeTextField: some View {
        HStack(spacing: 10) {
            TextField(
                "",
                text: Binding(
                    get: { locationController.placeQuery },
                    set: { locationController.updatePlaceQuery($0) }
                ),
                prompt: Text("Enter a city or town")
                    .foregroundStyle(Color.secondary)
            )
            .font(OnCutsFont.bodyMedium)
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.leading)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($isPlaceFieldFocused)
            .onSubmit {
                Task { await commitPlaceFromKeyboard() }
            }
            .accessibilityLabel("Enter a city or town for browse location")

            // Keep the clear control mounted so inserting it mid-edit does not resign the keyboard.
            Button {
                locationController.clearManualPlace()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(OnCutsFont.body)
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .opacity(locationController.placeQuery.isEmpty ? 0 : 1)
            .allowsHitTesting(!locationController.placeQuery.isEmpty)
            .accessibilityLabel("Clear location")
            .accessibilityHidden(locationController.placeQuery.isEmpty)
        }
        .padding(.leading, manualPlaceShowsContainer ? 18 : 0)
        .padding(.trailing, 4)
        .padding(.vertical, manualPlaceShowsContainer ? 12 : 8)
        .frame(maxWidth: .infinity, minHeight: manualPlaceRowHeight)
        .tint(Color.oliveGreen)
    }

    private var connectedSuggestionsDropdown: some View {
        let visibleRows = min(
            locationController.placeSuggestions.count,
            Self.maxVisibleSuggestionRows
        )
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(locationController.placeSuggestions) { suggestion in
                        Button {
                            Task {
                                await locationController.selectPlace(suggestion)
                                isPlaceFieldFocused = false
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(OnCutsFont.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(OnCutsFont.caption)
                                        .foregroundStyle(Color.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 11)
                            .padding(.horizontal, 14)
                            .frame(minHeight: Self.suggestionRowEstimatedHeight - 1, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if suggestion.id != locationController.placeSuggestions.last?.id {
                            Rectangle()
                                .fill(Color.primary.opacity(0.12))
                                .frame(height: 1)
                                .padding(.leading, 14)
                        }
                    }
                }
            }
            .frame(height: CGFloat(visibleRows) * Self.suggestionRowEstimatedHeight)
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trackingToggle: some View {
        Toggle(
            "Device tracking",
            isOn: Binding(
                get: { locationController.deviceTrackingEnabled },
                set: { locationController.setDeviceTracking($0) }
            )
        )
        .labelsHidden()
        .tint(Color.oliveGreen)
        .accessibilityLabel("Device tracking")
    }

    @MainActor
    private func commitPlaceFromKeyboard() async {
        if let first = locationController.placeSuggestions.first {
            await locationController.selectPlace(first)
            isPlaceFieldFocused = false
            return
        }
        await locationController.commitTypedPlaceIfPossible()
        isPlaceFieldFocused = false
    }
}
