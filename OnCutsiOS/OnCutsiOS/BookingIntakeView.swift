//
//  BookingIntakeView.swift
//  OnCuts
//
//  Barber booking intake: shrinking header, glass form, availability-driven time slots,
//  Pacific `scheduledAt` for the backend, review then auth-aware submit.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Scroll offset (shrinking header)

private struct BookingScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Glass field chrome

private struct GlassFormFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.onCutsShellGlassStroke, lineWidth: 1)
            }
    }
}

private extension View {
    func glassFormField() -> some View {
        modifier(GlassFormFieldChrome())
    }
}

private struct SoftFieldErrorText: View {
    let message: String?

    var body: some View {
        if let message, !message.isEmpty {
            Text(message)
                .font(OnCutsFont.caption)
                .foregroundStyle(Color.red.opacity(0.95))
                .shadow(color: Color.red.opacity(0.5), radius: 4, x: 0, y: 0)
                .shadow(color: Color.red.opacity(0.35), radius: 10, x: 0, y: 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .accessibilityLabel(message)
        }
    }
}

// MARK: - Intake

struct BookingIntakeView: View {
    let provider: ServiceProvider
    let sessionManager: AppSessionManager
    let onShowLogin: () -> Void
    let onDismiss: () -> Void

    private static let bookingScrollSpace = "bookingIntakeScroll"

    @State private var navPath = NavigationPath()
    @State private var isSubmittingBooking = false
    @State private var scrollMinY: CGFloat = 0

    @State private var selectedServiceId: String?
    @State private var customServiceName: String = ""
    @State private var selectedDate: Date = Date()
    @State private var selectedAppointmentTime = Date()
    @State private var locationText: String = ""
    /// Menu `Picker` with `tag("")` often fails to update a `String` binding on iOS; index-backed selection stays in sync with the chosen row.
    @State private var selectedLocationIndex: Int = 0

    @State private var slots: [BarberAvailabilitySlotDTO] = []
    @State private var isLoadingSlots = false
    @State private var slotsLoadError: String?

    @State private var serviceError: String?
    @State private var dateError: String?
    @State private var timeError: String?
    @State private var locationError: String?

    private var headerCollapse: CGFloat {
        min(1, max(0, -scrollMinY / 96))
    }

    private var services: [ServiceProvider.Service] {
        provider.services ?? []
    }

    private var hasServicePicker: Bool {
        !services.isEmpty
    }

    private var availableTimeKeys: Set<String> {
        Set(slots.filter(\.available).map(\.time))
    }

    private var availabilityQueryDurationMinutes: Int {
        if let sid = selectedServiceId,
           let svc = services.first(where: { $0.id == sid }),
           let duration = svc.duration {
            return BookingAvailabilityQuery.clampedDurationMinutes(duration)
        }
        return BookingAvailabilityQuery.clampedDurationMinutes(nil)
    }

    private var bookingDateRange: ClosedRange<Date> {
        let end = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
        return Date() ... end
    }

    var body: some View {
        ZStack {
            #if os(iOS)
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            OnCutsLiquidMeshBackground()
            #endif
            NavigationStack(path: $navPath) {
                ZStack(alignment: .top) {
                    ScrollViewReader { proxy in
                        ScrollView {
                        Color.clear
                            .frame(height: 1)
                            .id("bookingFormTop")

                        GeometryReader { g in
                            Color.clear.preference(
                                key: BookingScrollOffsetKey.self,
                                value: g.frame(in: .named(Self.bookingScrollSpace)).minY
                            )
                        }
                        .frame(height: 0)

                        VStack(alignment: .leading, spacing: .space5) {
                            // Spacer under floating header
                            Color.clear.frame(height: headerHeight)

                            sectionTitle("Service")
                            if hasServicePicker {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(services) { s in
                                            serviceChip(service: s, isSelected: selectedServiceId == s.id) {
                                                selectedServiceId = s.id
                                                #if os(iOS)
                                                OnCutsLiquidGlassHaptics.selectionChanged()
                                                #endif
                                                Task { await loadSlots() }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            } else {
                                TextField("Service type", text: $customServiceName)
                                    .font(OnCutsFont.body)
                                    .textInputAutocapitalization(.words)
                                    .glassFormField()
                            }
                            SoftFieldErrorText(message: serviceError)

                            sectionTitle("Date")
                            DatePicker(
                                "Date",
                                selection: $selectedDate,
                                in: bookingDateRange,
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.graphical)
                            .glassFormField()
                            .onChange(of: selectedDate) { _, _ in
                                Task { await loadSlots() }
                            }
                            SoftFieldErrorText(message: dateError)

                            sectionTitle("Time")
                            BookingMinuteTimePicker(
                                calendarDay: BookingPacificSchedule.pacificStartOfDay(for: selectedDate),
                                availableTimeKeys: availableTimeKeys,
                                selectedTime: $selectedAppointmentTime,
                                isLoading: isLoadingSlots,
                                loadError: slotsLoadError
                            )
                            .glassFormField()
                            SoftFieldErrorText(message: timeError)

                            sectionTitle("Location")
                            locationField
                            if locationError != nil {
                                locationAmberCallout
                            }
                            SoftFieldErrorText(message: locationError)

                            PrimaryButton(
                                title: "Continue to Confirmation",
                                action: { continueTapped(scrollProxy: proxy) },
                                variant: .shell,
                                size: .footer
                            )
                            .padding(.top, .space4)
                            .padding(.bottom, .space8)
                        }
                        .padding(.horizontal, .space4)
                    }
                    #if os(iOS)
                    .scrollContentBackground(.hidden)
                    #endif
                    .coordinateSpace(name: Self.bookingScrollSpace)
                    .onPreferenceChange(BookingScrollOffsetKey.self) { scrollMinY = $0 }
                }

                    shrinkingHeader
                }
                .navigationTitle("Book")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") { onDismiss() }
                }
                #endif
            }
            .navigationDestination(for: BookingNavigationDestination.self) { destination in
                switch destination {
                case .review(let booking):
                    ReviewBookingView(
                        booking: booking,
                        onSubmit: { handleReviewSubmit(booking: $0) }
                    )
                }
            }
            .tint(Color.oliveGreen)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            }
        }
        .task {
            await loadSlots()
            prefillLocation()
        }
        .onChange(of: sessionManager.isAuthenticated) { _, isAuthed in
            guard isAuthed else { return }
            attemptSubmitPendingBookingAfterSignIn()
        }
        .onAppear {
            attemptSubmitPendingBookingAfterSignIn()
        }
    }

    private func attemptSubmitPendingBookingAfterSignIn() {
        guard sessionManager.isAuthenticated else { return }
        guard let booking = PendingPostLoginBooking.peekIfMatches(providerId: provider.id) else { return }
        if navPath.isEmpty {
            navPath.append(BookingNavigationDestination.review(booking))
        }
        guard let consumed = PendingPostLoginBooking.consumeIfMatches(providerId: provider.id) else { return }
        submitReviewedBooking(consumed, resumeAfterAuth: true)
    }

    private var headerHeight: CGFloat {
        120 - 36 * headerCollapse
    }

    private var shrinkingHeader: some View {
        let avatarSize: CGFloat = 56 - 16 * headerCollapse
        let nameSize: CGFloat = 20 - 4 * headerCollapse

        return HStack(alignment: .center, spacing: 12) {
            Group {
                if let urlStr = provider.profileImageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            placeholderInitials
                        }
                    }
                } else {
                    placeholderInitials
                }
            }
            .frame(width: max(40, avatarSize), height: max(40, avatarSize))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.businessName)
                    .font(OnCutsLiquidGlassTypography.title(max(16, nameSize), weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(headerCollapse > 0.85 ? 1 : 2)

                if let igURL = provider.instagramProfileURL {
                    Link(destination: igURL) {
                        Image("Instagram")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .accessibilityLabel("Instagram")
                    }
                    .opacity(headerCollapse > 0.95 ? 0 : 1)
                    .frame(height: headerCollapse > 0.95 ? 0 : nil)
                    .clipped()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12 - 4 * headerCollapse)
        .onCutsGlassSurface(cornerRadius: 20)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var placeholderInitials: some View {
        Text(provider.businessName.prefix(2).uppercased())
            .font(OnCutsFont.headline)
            .foregroundStyleOliveGreen()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.brand.opacity(0.15))
    }

    @ViewBuilder
    private var locationField: some View {
        let locs = provider.locations ?? []
        if locs.count > 1 {
            Picker("Location", selection: $selectedLocationIndex) {
                ForEach(Array(locs.enumerated()), id: \.offset) { index, loc in
                    Text(loc).tag(index)
                }
            }
            .pickerStyle(.menu)
            .glassFormField()
            .onAppear {
                syncLocationSelectionFromPicker(locs: locs)
            }
            .onChange(of: selectedLocationIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < locs.count else { return }
                locationText = locs[newIndex]
            }
        } else if let one = locs.first {
            Text(one)
                .font(OnCutsFont.bodyMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassFormField()
                .onAppear { if locationText.isEmpty { locationText = one } }
        } else {
            TextField("Where should we meet?", text: $locationText)
                .textInputAutocapitalization(.words)
                .glassFormField()
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(OnCutsFont.headlineSmall)
            .foregroundStyle(.primary)
    }

    private func serviceChip(service: ServiceProvider.Service, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(service.name)  $\(service.price)")
                .font(OnCutsFont.body(weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isSelected ? Color.oliveGreen.opacity(0.55) : Color.primary.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var locationAmberCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(OnCutsFont.body(weight: .semibold))
                #if canImport(UIKit)
                .foregroundStyle(Color(UIColor.systemYellow))
                #else
                .foregroundStyle(.yellow)
                #endif
            Text("Add a meeting location so your provider knows where to find you.")
                .font(OnCutsFont.body)
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    #if canImport(UIKit)
                    .fill(Color(UIColor.systemYellow).opacity(0.22))
                    #else
                    .fill(Color.yellow.opacity(0.22))
                    #endif
                    .blur(radius: 18)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
    }

    private func prefillLocation() {
        let locs = provider.locations ?? []
        if locs.count > 1 {
            syncLocationSelectionFromPicker(locs: locs)
        } else if locationText.isEmpty, let one = locs.first, locs.count == 1 {
            locationText = one
        }
    }

    private func syncLocationSelectionFromPicker(locs: [String]) {
        guard !locs.isEmpty else { return }
        if selectedLocationIndex < 0 || selectedLocationIndex >= locs.count {
            selectedLocationIndex = 0
        }
        locationText = locs[selectedLocationIndex]
    }

    /// Resolved string sent to the server (picker binding is authoritative for multi-location barbers).
    private func resolvedMeetingLocationForSubmit() -> String {
        let locs = provider.locations ?? []
        if locs.count > 1 {
            let idx = min(max(0, selectedLocationIndex), locs.count - 1)
            return locs[idx].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return locationText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadSlots() async {
        isLoadingSlots = true
        slotsLoadError = nil
        defer { isLoadingSlots = false }

        let day = BookingPacificSchedule.apiDateString(from: selectedDate)
        do {
            let rows = try await BarberAvailabilityAPI.fetchDaySlots(
                barberId: provider.id,
                dateYYYYMMDD: day,
                durationMinutes: availabilityQueryDurationMinutes,
                bearerToken: sessionManager.currentSession?.token
            )
            slots = rows
            BookingPacificSchedule.selectEarliestOpenAppointmentTime(
                &selectedAppointmentTime,
                calendarDay: BookingPacificSchedule.pacificStartOfDay(for: selectedDate),
                availableKeys: availableTimeKeys
            )
        } catch {
            if OnCutsRefreshCancellation.isBenignCancellation(error) { return }
            slots = []
            slotsLoadError = "Couldn’t load times. Pull to refresh or pick another date."
            #if DEBUG
            print("Availability error: \(error)")
            #endif
        }
    }

    private func continueTapped(scrollProxy: ScrollViewProxy) {
        clearFieldErrors()
        var messages: [String] = []

        let servicePick: (name: String, price: Int)? = {
            if hasServicePicker {
                guard let sid = selectedServiceId,
                      let svc = services.first(where: { $0.id == sid }) else { return nil }
                return (svc.name, svc.price)
            }
            let raw = customServiceName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            let fallback = provider.priceRange.map { ($0.min + $0.max) / 2 } ?? 40
            return (raw, fallback)
        }()

        if servicePick == nil {
            let msg = hasServicePicker ? "Choose a service." : "Enter a service type."
            serviceError = msg
            messages.append(msg)
        }

        var pacificCal = Calendar(identifier: .gregorian)
        pacificCal.timeZone = BookingPacificSchedule.pacificTimeZone
        let todayPacificStart = pacificCal.startOfDay(for: Date())
        let selectedPacificStart = pacificCal.startOfDay(for: selectedDate)
        if selectedPacificStart < todayPacificStart {
            dateError = "Pick today or a future date."
            messages.append("Pick a valid date.")
        }

        let timeKey = BookingPacificSchedule.pacificHHmmKey(from: selectedAppointmentTime)
        let timeValid = availableTimeKeys.contains(timeKey)
        if !timeValid {
            timeError = "Choose an available time."
            messages.append("Choose a time.")
        }

        let loc = resolvedMeetingLocationForSubmit()
        if loc.isEmpty {
            locationError = "Add or select a location."
            messages.append("Add a location.")
        }

        if !messages.isEmpty {
            withAnimation(.easeOut(duration: 0.25)) {
                scrollProxy.scrollTo("bookingFormTop", anchor: .top)
            }
            AlertManager.shared.presentErrorToast(messages.joined(separator: " "))
            return
        }

        guard let sp = servicePick,
              availableTimeKeys.contains(timeKey),
              let iso = BookingPacificSchedule.scheduledAtISO(selectedDate: selectedDate, timeHHmm: timeKey) else {
            timeError = "Couldn’t read the selected time."
            AlertManager.shared.presentErrorToast("Couldn’t build the appointment time. Try again.")
            return
        }

        let pricingBaseline: Int = {
            if let min = provider.services?.map(\.price).min(), min > 0 { return min }
            if let min = provider.priceRange?.min, min > 0 { return min }
            return 30
        }()

        let state = BookingState(
            barberId: provider.id,
            barberDisplayName: provider.businessName,
            serviceName: sp.name,
            location: loc,
            scheduledAtPacificISO: iso,
            resolvedPriceUsd: sp.price,
            durationMinutes: availabilityQueryDurationMinutes,
            profileImageUrl: provider.profileImageUrl,
            instagramHandle: provider.instagramHandle,
            pricingBaselineUsd: pricingBaseline
        )
        #if os(iOS)
        OnCutsLiquidGlassHaptics.notification(.success)
        #endif
        navPath.append(BookingNavigationDestination.review(state))
    }

    private func handleReviewSubmit(booking: BookingState) {
        guard sessionManager.isAuthenticated else {
            PendingPostLoginBooking.stashForSignIn(providerId: provider.id, booking: booking)
            onShowLogin()
            return
        }
        submitReviewedBooking(booking, resumeAfterAuth: false)
    }

    private func submitReviewedBooking(_ booking: BookingState, resumeAfterAuth: Bool) {
        Task { @MainActor in
            guard !isSubmittingBooking else { return }
            isSubmittingBooking = true
            defer { isSubmittingBooking = false }
            do {
                try await AppointmentCreateAPI.createAppointment(
                    booking: booking,
                    bearerToken: sessionManager.currentSession?.token
                )
                #if os(iOS)
                OnCutsLiquidGlassHaptics.notification(.success)
                #endif
                AlertManager.shared.present("Your booking request was sent.")
                navPath = NavigationPath()
                onDismiss()
                NotificationCenter.default.post(
                    name: .onCutsNavigateToBookingsAfterBookingRequest,
                    object: nil,
                    userInfo: [OnCutsBookingsUserInfoKeys.focusUpcomingSection: true]
                )
            } catch {
                if AppointmentCreateAPI.isUnauthorizedError(error) {
                    await sessionManager.recoverSessionAfterUnauthorized()
                    PendingPostLoginBooking.stashForSignIn(providerId: provider.id, booking: booking)
                    onShowLogin()
                } else {
                    AlertManager.shared.presentErrorToast(error.localizedDescription)
                    if resumeAfterAuth {
                        PendingPostLoginBooking.stashForSignIn(providerId: provider.id, booking: booking)
                    }
                }
            }
        }
    }

    private func clearFieldErrors() {
        serviceError = nil
        dateError = nil
        timeError = nil
        locationError = nil
    }
}
