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

    @FocusState private var isPlaceFieldFocused: Bool

    /// Approximate field height so the overlapping dropdown can sit flush under the input.
    private static var placeFieldContentHeight: CGFloat { 48 }
    private static var fieldCornerRadius: CGFloat { 12 }
    /// Visible suggestion rows before the menu scrolls.
    private static var maxVisibleSuggestionRows: Int { 5 }
    /// Approx. height of one suggestion row (title + subtitle + padding + divider).
    private static var suggestionRowEstimatedHeight: CGFloat { 54 }

    private var showsAttachedDropdown: Bool {
        !locationController.deviceTrackingEnabled
            && locationController.shouldShowPlaceSuggestions
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            if locationController.deviceTrackingEnabled {
                deviceLocationLabel
                trackingToggleRow
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

    private var deviceLocationLabel: some View {
        Text(locationController.locationLabel)
            .font(OnCutsFont.headlineSmall.weight(.bold))
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Browse location \(locationController.locationLabel)")
    }

    /// Grey form-style field + matching attached dropdown.
    private var manualPlaceBlock: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 8) {
                Color.clear
                    .frame(height: Self.placeFieldContentHeight)
                if !locationController.isPlaceFieldEditing {
                    trackingToggleRow
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            VStack(spacing: 0) {
                placeTextField
                    .frame(minHeight: Self.placeFieldContentHeight)

                if showsAttachedDropdown {
                    connectedSuggestionsDropdown
                }
            }
            .background {
                RoundedRectangle(cornerRadius: Self.fieldCornerRadius, style: .continuous)
                    .fill(manualInputGreyFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Self.fieldCornerRadius, style: .continuous)
                    .strokeBorder(
                        fieldBorderColor,
                        lineWidth: isPlaceFieldFocused || showsAttachedDropdown ? 1.5 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.fieldCornerRadius, style: .continuous))
            .shadow(
                color: Color.black.opacity(showsAttachedDropdown ? 0.2 : 0.06),
                radius: showsAttachedDropdown ? 12 : 2,
                y: showsAttachedDropdown ? 6 : 1
            )
            .compositingGroup()
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: locationController.isPlaceFieldEditing)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: Self.placeFieldContentHeight)
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
        .background(manualInputGreyFill)
    }

    /// Adaptive grey fill — readable in light and dark mode.
    private var manualInputGreyFill: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color.primary.opacity(0.08)
        #endif
    }

    private var fieldBorderColor: Color {
        if isPlaceFieldFocused || showsAttachedDropdown {
            return Color.primary.opacity(0.35)
        }
        return Color.primary.opacity(0.18)
    }

    private var trackingToggleRow: some View {
        ZStack {
            Text(helperCopy)
                .font(OnCutsFont.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer(minLength: 0)
                Toggle(
                    "Device tracking",
                    isOn: Binding(
                        get: { locationController.deviceTrackingEnabled },
                        set: { locationController.setDeviceTracking($0) }
                    )
                )
                .labelsHidden()
                .tint(Color.oliveGreen)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var helperCopy: String {
        locationController.deviceTrackingEnabled
            ? "Toggle off to turn off device tracking"
            : "Toggle on to turn on device tracking"
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
