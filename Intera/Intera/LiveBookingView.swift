//
//  LiveBookingView.swift
//  Intera
//
//  Lava lamp booking intake: CampusCuts services + availability, glass cards,
//  sticky footer CTA, review navigation via `BookingMetadata`.
//

import SwiftUI
import CampusCutsModule
#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    /// Posted after a booking request succeeds so hosts can open Bookings when detail was **pushed** (no overlay callback).
    static let interaNavigateToBookingsAfterBookingRequest = Notification.Name("interaNavigateToBookingsAfterBookingRequest")
    /// Posted after a booking is updated (`PUT /bookings-simple/:id`) so lists refresh without switching tabs.
    static let consumerBookingsListShouldRefresh = Notification.Name("consumerBookingsListShouldRefresh")
}

/// `userInfo` keys for booking navigation notifications.
enum InteraBookingsUserInfoKeys {
    /// Set to `true` on `interaNavigateToBookingsAfterBookingRequest` to scroll the bookings timeline to the **Upcoming** section (top of the list).
    static let focusUpcomingSection = "interaBookingsFocusUpcomingSection"
    /// Set to `true` on `interaNavigateToConsumerHomeAfterPayment` when leaving the post-payment review sheet — hub switches without animation so it does not fight `fullScreenCover` dismissal (avoids empty / warning navigation chrome).
    static let snapHubNoAnimation = "interaSnapHubNoAnimationAfterPaymentFlow"
}

// MARK: - Material shell (inputs)

private struct LiveBookingMaterialShell: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
    }
}

private extension View {
    func liveBookingMaterialShell() -> some View {
        modifier(LiveBookingMaterialShell())
    }
}

// MARK: - Unified service chip model (package or embedded list)

private struct LiveServiceChip: Identifiable, Hashable {
    let id: String
    let name: String
    let priceUsd: Int
    let durationMinutes: Int
}

/// `ScrollViewReader` targets for validation: order matches top-to-bottom layout.
private enum LiveBookingScrollAnchor: String {
    case service = "liveBookingService"
    case date = "liveBookingDate"
    case time = "liveBookingTime"
}

// MARK: - View

struct LiveBookingView: View {
    let provider: ServiceProvider
    let sessionManager: AppSessionManager
    let onShowLogin: () -> Void
    let onDismiss: () -> Void
    /// If set, called after the booking request is submitted successfully instead of `onDismiss` (parent closes sheets + navigates).
    var onBookingRequestSuccessfullySent: (() -> Void)? = nil
    /// When set (e.g. rebook from a past booking), selects the matching service chip after services load.
    var preselectServiceName: String? = nil

    @State private var navPath = NavigationPath()
    @State private var isSubmittingBooking = false

    @State private var packageServiceRows: [CampusCutsBarberServiceRow] = []
    @State private var selectedChipId: String?
    @State private var selectedDate: Date = Date()
    @State private var selectedAppointmentTime = Date()

    @State private var ribbonSlots: [BookingRibbonSlot] = []
    /// Time slots stay hidden / dimmed until the user taps a day on the calendar.
    @State private var calendarSelectionCommitted = false
    @State private var isLoadingSlots = false
    @State private var slotsLoadError: String?

    @State private var openDaysByMonthKey: [String: Set<Date>] = [:]
    @State private var loadingOpenDaysMonthKeys: Set<String> = []
    @State private var calendarDisplayedMonth = Date()

    @State private var serviceError: String?
    @State private var timeError: String?

    private var campusCutsBarberIntId: Int? {
        Int(provider.id)
    }

    private var campusCutsClient: CampusCutsClient {
        CampusCutsClient(
            session: CampusCutsUserSessionAdapter(manager: sessionManager),
            environment: .production,
            isProduction: AppConfiguration.campusCutsProductionLiveDataMode
        )
    }

    private var serviceChips: [LiveServiceChip] {
        if !packageServiceRows.isEmpty {
            return packageServiceRows.map {
                LiveServiceChip(id: "pkg-\($0.id)", name: $0.name, priceUsd: $0.priceUsd, durationMinutes: $0.durationMinutes)
            }
        }
        return (provider.services ?? []).map {
            LiveServiceChip(
                id: "emb-\($0.id)",
                name: $0.name,
                priceUsd: $0.price,
                durationMinutes: $0.duration ?? 30
            )
        }
    }

    private var bookingDateRange: ClosedRange<Date> {
        let end = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
        return Date() ... end
    }

    private var calendarAllowedDayStarts: Set<Date>? {
        let monthKey = BookingPacificSchedule.monthCacheKey(for: calendarDisplayedMonth)
        let weekly = provider.weeklyTemplateDayStarts(in: bookingDateRange)

        if let apiDays = openDaysByMonthKey[monthKey] {
            if let weekly { return apiDays.intersection(weekly) }
            return apiDays
        }

        if loadingOpenDaysMonthKeys.contains(monthKey) {
            return weekly
        }

        return weekly
    }

    /// Top-leading dismiss: layered blur + cream stroke so the glyph stays sharp on the lava lamp.
    private var bookingExitOrbButton: some View {
        Button(role: .cancel, action: onDismiss) {
            Image(systemName: "xmark")
                .font(InteraFont.system(size: 16, weight: .bold))
                .foregroundStyle(BookingSelectorTheme.cream)
                .symbolRenderingMode(.monochrome)
                .frame(width: 48, height: 48)
                .background {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.34))
                        Circle()
                            .fill(.thickMaterial)
                        Circle()
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(BookingSelectorTheme.cream, lineWidth: 1)
                    }
                }
                .clipShape(Circle())
                .contentShape(Circle())
                .accessibilityLabel("Cancel")
        }
        .buttonStyle(BookingExitOrbButtonStyle())
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack(alignment: .topLeading) {
                InteraLavaLampBackground()

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        Color.clear
                            .frame(height: 1)
                            .id("liveBookingTop")

                        VStack(alignment: .leading, spacing: 20) {
                            heroCard

                            serviceSection
                                .id(LiveBookingScrollAnchor.service.rawValue)
                                .liveBookingMaterialShell()

                            dateSection
                                .id(LiveBookingScrollAnchor.date.rawValue)

                            timeSection
                                .id(LiveBookingScrollAnchor.time.rawValue)
                                .liveBookingMaterialShell()

                            Color.clear.frame(height: 100)
                        }
                        .padding(.horizontal, 20)
                        // Inset below top-leading exit orb (48pt + safe padding).
                        .padding(.top, 76)
                    }
                    .scrollIndicators(.hidden)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        stickyFooter(scrollProxy: scrollProxy)
                    }
                }

                bookingExitOrbButton
                    .padding(.leading, 28)
                    .padding(.top, 20)
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: BookingNavigationDestination.self) { destination in
                switch destination {
                case .review(let metadata):
                    ReviewBookingView(
                        booking: metadata,
                        onSubmit: { handleReviewSubmit(booking: $0) }
                    )
                }
            }
            .tint(Color.oliveGreen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadPackageServices()
            applyPreselectedServiceIfNeeded()
        }
        .onChange(of: sessionManager.isAuthenticated) { _, isAuthed in
            guard isAuthed else { return }
            attemptSubmitPendingBookingAfterSignIn()
        }
        .onAppear {
            attemptSubmitPendingBookingAfterSignIn()
        }
    }

    /// After OAuth, `NavigationPath` may reset — re-push review, then submit so the user is not sent back to step 1.
    private func attemptSubmitPendingBookingAfterSignIn() {
        guard sessionManager.isAuthenticated else { return }
        guard let booking = PendingPostLoginBooking.peekIfMatches(providerId: provider.id) else { return }
        if navPath.isEmpty {
            navPath.append(BookingNavigationDestination.review(booking))
        }
        guard let consumed = PendingPostLoginBooking.consumeIfMatches(providerId: provider.id) else { return }
        submitReviewedBooking(consumed, resumeAfterAuth: true)
    }

    private func applyPreselectedServiceIfNeeded() {
        guard let raw = preselectServiceName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        let want = raw.lowercased()
        let chips = serviceChips
        guard !chips.isEmpty else { return }

        if let chip = chips.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == want
        }) {
            selectedChipId = chip.id
            return
        }

        let wantNorm = want.replacingOccurrences(of: "_", with: " ")
        if let chip = chips.first(where: {
            $0.name.lowercased().replacingOccurrences(of: "_", with: " ") == wantNorm
        }) {
            selectedChipId = chip.id
            return
        }

        if let chip = chips.first(where: {
            $0.name.lowercased().contains(want) || want.contains($0.name.lowercased())
        }) {
            selectedChipId = chip.id
        }
    }

    private var heroCard: some View {
        VStack(alignment: .center, spacing: 12) {
            Group {
                if let urlStr = provider.profileImageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            heroPlaceholder
                        }
                    }
                } else {
                    heroPlaceholder
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: BookingSelectorTheme.cornerRadius, style: .continuous))

            Text(provider.businessName)
                .font(InteraFont.headlineSmall)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let igURL = provider.instagramProfileURL {
                Link(destination: igURL) {
                    Label("Instagram", systemImage: "camera.fill")
                        .font(InteraFont.subheadline.weight(.medium))
                        .labelStyle(.iconOnly)
                        .foregroundStyleInteraShellIcon()
                        .frame(width: 36, height: 36)
                        .background {
                            Circle().fill(.ultraThinMaterial)
                        }
                        .accessibilityLabel("Open Instagram")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var heroPlaceholder: some View {
        Text(provider.businessName.prefix(2).uppercased())
            .font(InteraFont.headline)
            .foregroundStyleOliveGreen()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.brand.opacity(0.2))
    }

    private func bookingSectionHeader(_ title: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(BookingSelectorTheme.todayBoldFont)
                .foregroundStyle(BookingSelectorTheme.cream)
                .minimumScaleFactor(0.55)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            Rectangle()
                .fill(BookingSelectorTheme.cream.opacity(0.7))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            bookingSectionHeader("Select Your Service")

            if serviceChips.isEmpty {
                Text("No services listed yet.")
                    .font(InteraFont.bodySmall)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(serviceChips) { chip in
                        serviceRowButton(chip)
                    }
                }
            }
            if let serviceError, !serviceError.isEmpty {
                Text(serviceError)
                    .font(InteraFont.caption)
                    .foregroundStyle(Color.red.opacity(0.9))
            }
        }
    }

    private func serviceRowButton(_ chip: LiveServiceChip) -> some View {
        ServiceSelectionRow(
            title: chip.name,
            priceText: "$\(chip.priceUsd)",
            isSelected: selectedChipId == chip.id,
            action: {
                selectedChipId = chip.id
                serviceError = nil
            }
        )
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            bookingSectionHeader("Pick a Day")
            BookingCalendarGridSelector(
                selectedDate: $selectedDate,
                selectionCommitted: $calendarSelectionCommitted,
                range: bookingDateRange,
                allowedDayStarts: calendarAllowedDayStarts,
                onDaySelected: scheduleSlotReloadForPickedDay,
                onDisplayedMonthChange: { month in
                    calendarDisplayedMonth = month
                    Task { await loadOpenDays(forMonth: month) }
                }
            )
        }
    }

    private var availableTimeKeys: Set<String> {
        Set(ribbonSlots.map(\.timeKey))
    }

    private func scheduleSlotReloadForPickedDay() {
        timeError = nil
        Task { await loadSlots() }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            bookingSectionHeader("Choose a Time")

            timePickerBlock

            if let timeError, !timeError.isEmpty {
                Text(timeError)
                    .font(InteraFont.caption)
                    .foregroundStyle(Color.red.opacity(0.9))
            }
        }
    }

    private var timePickerBlock: some View {
        Group {
            if !calendarSelectionCommitted {
                Text("Pick a day on the calendar to see available times.")
                    .font(InteraFont.subheadline.weight(.medium))
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.42))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                BookingMinuteTimePicker(
                    calendarDay: BookingPacificSchedule.pacificStartOfDay(for: selectedDate),
                    availableTimeKeys: availableTimeKeys,
                    selectedTime: $selectedAppointmentTime,
                    isLoading: isLoadingSlots,
                    loadError: slotsLoadError
                )
            }
        }
        .onChange(of: selectedAppointmentTime) { _, _ in
            timeError = nil
        }
    }

    /// Stored on the booking; provider and consumer finalize where to meet in chat.
    private static let coordinateLocationMessage = "Coordinate location via message"

    private func stickyFooter(scrollProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
            PrimaryButton(
                title: "Continue to Confirmation",
                action: { continueTapped(scrollProxy: scrollProxy) },
                variant: .shell,
                size: .footer
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 4)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func loadPackageServices() async {
        guard let bid = campusCutsBarberIntId else {
            packageServiceRows = []
            return
        }
        do {
            packageServiceRows = try await campusCutsClient.fetchBarberServiceRows(barberId: bid)
        } catch {
            packageServiceRows = []
        }
    }

    @MainActor
    private func loadOpenDays(forMonth month: Date) async {
        let monthKey = BookingPacificSchedule.monthCacheKey(for: month)
        guard !monthKey.isEmpty, openDaysByMonthKey[monthKey] == nil else { return }

        loadingOpenDaysMonthKeys.insert(monthKey)
        defer { loadingOpenDaysMonthKeys.remove(monthKey) }

        let days = BookingPacificSchedule.dayStartsInMonth(containing: month, clippedTo: bookingDateRange)
        let open = await BookingOpenDaysLoader.loadOpenDayStarts(
            days: days,
            barberId: provider.id,
            campusCutsBarberIntId: campusCutsBarberIntId,
            bearerToken: sessionManager.currentSession?.token,
            campusCutsClient: campusCutsClient
        )
        openDaysByMonthKey[monthKey] = open
    }

    private func loadSlots() async {
        isLoadingSlots = true
        slotsLoadError = nil
        defer {
            isLoadingSlots = false
            reconcileSelectedTimeAfterLoad()
        }

        let day = BookingPacificSchedule.apiDateString(from: selectedDate)

        if let bid = campusCutsBarberIntId {
            do {
                let slots = try await campusCutsClient.fetchBarberDayAvailability(barberId: bid, dateYYYYMMDD: day)
                let mapped = slots.map { s in
                    let key = normalizeSlotTimeKey(s.startTime)
                    return BookingRibbonSlot(timeKey: key, label: displayTimeLabel(key), available: s.isAvailable)
                }
                ribbonSlots = dedupeRibbonSlotsKeepingOrder(mapped).availableOnly
                if ribbonSlots.isEmpty {
                    await loadSlotsViaShellAPI(day: day)
                } else {
                    slotsLoadError = nil
                }
                return
            } catch {
                if InteraRefreshCancellation.isBenignCancellation(error) { return }
                await loadSlotsViaShellAPI(day: day)
                return
            }
        }
        await loadSlotsViaShellAPI(day: day)
    }

    private func loadSlotsViaShellAPI(day: String) async {
        do {
            let rows = try await BarberAvailabilityAPI.fetchDaySlots(
                barberId: provider.id,
                dateYYYYMMDD: day,
                bearerToken: sessionManager.currentSession?.token
            )
            let mapped = rows.map { BookingRibbonSlot(timeKey: $0.time, label: displayTimeLabel($0.time), available: $0.available) }
            ribbonSlots = dedupeRibbonSlotsKeepingOrder(mapped).availableOnly
            slotsLoadError = nil
        } catch {
            if InteraRefreshCancellation.isBenignCancellation(error) { return }
            ribbonSlots = []
            slotsLoadError = "Couldn’t load times. Try another date."
        }
    }

    private func reconcileSelectedTimeAfterLoad() {
        BookingPacificSchedule.reconcileAppointmentTime(
            &selectedAppointmentTime,
            calendarDay: BookingPacificSchedule.pacificStartOfDay(for: selectedDate),
            availableKeys: availableTimeKeys
        )
    }

    /// Collides on same `timeKey`; keeps first occurrence (stable order).
    private func dedupeRibbonSlotsKeepingOrder(_ rows: [BookingRibbonSlot]) -> [BookingRibbonSlot] {
        var seen = Set<String>()
        let sorted = rows.sorted { $0.timeKey < $1.timeKey }
        return sorted.filter { seen.insert($0.timeKey).inserted }
    }

    private func normalizeSlotTimeKey(_ startTime: String) -> String {
        let trimmed = startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return trimmed }
        let colonIdx = trimmed.index(trimmed.startIndex, offsetBy: 2)
        guard trimmed[colonIdx] == ":" else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 5)
        return String(trimmed[..<end])
    }

    private func displayTimeLabel(_ hhmm: String) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = BookingPacificSchedule.pacificTimeZone
        let parts = hhmm.split(separator: ":")
        guard parts.count >= 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else { return hhmm }
        var dc = DateComponents()
        dc.hour = h
        dc.minute = m
        guard let ref = cal.date(from: dc) else { return hhmm }
        let f = DateFormatter()
        f.timeZone = BookingPacificSchedule.pacificTimeZone
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: ref)
    }

    private func continueTapped(scrollProxy: ScrollViewProxy) {
        serviceError = nil
        timeError = nil
        var messages: [String] = []
        var firstInvalid: LiveBookingScrollAnchor?

        guard let chipId = selectedChipId,
              let chip = serviceChips.first(where: { $0.id == chipId }) else {
            let msg = "Choose a service."
            serviceError = msg
            messages.append(msg)
            failValidation(messages: messages, scrollProxy: scrollProxy, scrollTo: .service)
            return
        }

        var pacificCal = Calendar(identifier: .gregorian)
        pacificCal.timeZone = BookingPacificSchedule.pacificTimeZone
        let todayPacificStart = pacificCal.startOfDay(for: Date())
        let selectedPacificStart = pacificCal.startOfDay(for: selectedDate)
        if !calendarSelectionCommitted {
            let msg = "Pick a day on the calendar."
            messages.append(msg)
            firstInvalid = .date
        } else if selectedPacificStart < todayPacificStart {
            messages.append("Pick a valid date.")
            firstInvalid = .date
        }

        let timeKey = BookingPacificSchedule.pacificHHmmKey(from: selectedAppointmentTime)
        let timeValid = availableTimeKeys.contains(timeKey)
        if !timeValid {
            let msg = "Choose an available time."
            timeError = msg
            messages.append(msg)
            if firstInvalid == nil { firstInvalid = .time }
        }

        if !messages.isEmpty {
            failValidation(messages: messages, scrollProxy: scrollProxy, scrollTo: firstInvalid ?? .service)
            return
        }

        guard availableTimeKeys.contains(timeKey),
              let iso = BookingPacificSchedule.scheduledAtISO(selectedDate: selectedDate, timeHHmm: timeKey) else {
            let msg = "Couldn’t read the selected time."
            timeError = msg
            failValidation(messages: [msg], scrollProxy: scrollProxy, scrollTo: .time)
            return
        }

        let pricingBaseline: Int = {
            if let min = provider.services?.map(\.price).min(), min > 0 { return min }
            if let min = provider.priceRange?.min, min > 0 { return min }
            return 30
        }()

        let metadata = BookingMetadata(
            barberId: provider.id,
            barberDisplayName: provider.businessName,
            serviceName: chip.name,
            location: Self.coordinateLocationMessage,
            scheduledAtPacificISO: iso,
            resolvedPriceUsd: chip.priceUsd,
            durationMinutes: chip.durationMinutes,
            profileImageUrl: provider.profileImageUrl,
            instagramHandle: provider.instagramHandle,
            pricingBaselineUsd: pricingBaseline
        )
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        navPath.append(BookingNavigationDestination.review(metadata))
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
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                AlertManager.shared.present("Your booking request was sent.")
                navPath = NavigationPath()
                if let onSent = onBookingRequestSuccessfullySent {
                    onSent()
                } else {
                    onDismiss()
                }
                NotificationCenter.default.post(
                    name: .interaNavigateToBookingsAfterBookingRequest,
                    object: nil,
                    userInfo: [InteraBookingsUserInfoKeys.focusUpcomingSection: true]
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

    private func failValidation(messages: [String], scrollProxy: ScrollViewProxy, scrollTo: LiveBookingScrollAnchor) {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
        withAnimation(.easeOut(duration: 0.25)) {
            scrollProxy.scrollTo(scrollTo.rawValue, anchor: .top)
        }
        AlertManager.shared.presentErrorToast(messages.joined(separator: " "))
    }
}

// MARK: - Booking exit orb (press scale + haptic)

private struct BookingExitOrbButtonStyle: ButtonStyle {
    private static let pressAnimation = Animation.easeInOut(duration: 0.14)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(Self.pressAnimation, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
            }
    }
}
