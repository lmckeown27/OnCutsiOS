//
//  ConsumerBookingDetailView.swift
//  Intera
//
//  Full detail for a row from `GET /api/v1/bookings-simple?role=consumer`.
//

import SwiftUI
import CampusCutsModule
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

struct ConsumerBookingDetailView: View {
    let row: ConsumerBookingSimpleRow
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    /// When set (e.g. home reminder push), unique per navigation so `matchedGeometryEffect` never collides on reopen.
    var bookingDetailPresentationID: UUID? = nil
    /// When true, rebook is blocked with the same messaging as provider detail (pending/upcoming request).
    var hasActiveConsumerBooking: Bool = false
    /// When `true`, skips the default `InteraLavaLampBackground` so a parent (e.g. home reminder morph) owns the lava layer.
    var usesExternalLavaBackdrop: Bool = false
    var onShowLogin: () -> Void = {}
    var bookingMessagingMode: ChatViewModel.BookingDetailMessagingMode = .bookingsTab
    /// Host `NavigationStack` pushes ``ConsumerHomeBookingStackRoute/messagingThread`` (path) or sets browse handoff.
    var presentBookingMessagingThread: ((ChatViewModel.BookingMessagingThreadHandoff) -> Void)? = nil

    @State private var showRebookSheet = false
    @State private var isOpeningMessaging = false
    @State private var showMessagingUnavailableAlert = false
    @State private var rebookProvider: ServiceProvider?
    @State private var isLoadingRebook = false
    @State private var showActiveBookingAlert = false
    @State private var showLiveDataStripeAlert = false

    /// Local overrides after the user confirms edits (row is immutable from the API).
    @State private var localScheduledAt: Date?
    @State private var localServiceName: String?
    @State private var localLocation: String?

    @State private var isEditing = false
    @State private var draftScheduledAt = Date()
    @State private var draftCalendarCommitted = true
    @State private var draftServiceName = ""
    @State private var draftLocation = ""
    @State private var draftNotes = ""
    @State private var showScheduleEditSheet = false
    /// Which row opened the schedule sheet (drives the navigation title).
    @State private var scheduleEditEntry: ScheduleEditEntry = .date

    private enum ScheduleEditEntry {
        case date
        case time
    }

    @State private var scheduleEditSlotsError: String?
    @State private var scheduleEditSlotRows: [BookingRibbonSlot] = []
    @State private var scheduleEditSlotsLoading = false
    @State private var editTimePickerKey: String?

    @State private var alternativeServiceNames: [String] = []
    @State private var alternativeLocationNames: [String] = []
    @State private var isLoadingEditPickerOptions = false
    @State private var isConfirmingEdits = false
    @State private var showCancelBookingConfirmation = false
    @State private var isCancellingBooking = false

    /// Server snapshot after pull-to-refresh; navigation `row` is the fallback.
    @State private var refreshedRow: ConsumerBookingSimpleRow?

    private var bookingRow: ConsumerBookingSimpleRow {
        refreshedRow ?? row
    }

    /// Matches `LiveBookingView` when the barber has no preset stations.
    private static let coordinateLocationMessage = "Coordinate location via message"

    private static func isCoordinateLocationPlaceholder(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(Self.coordinateLocationMessage) == .orderedSame
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatViewModel: ChatViewModel

    private static let dateOnlyDF: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    private static let timeOnlyDF: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    private var allowsBookingEdit: Bool {
        let segmentOk = bookingRow.scheduleSegment() == .today || bookingRow.scheduleSegment() == .upcoming
        let u = bookingRow.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let statusOk = u == "PENDING" || u == "ACCEPTED"
        return segmentOk && statusOk
    }

    private var requestChangeToolbarTitle: String {
        bookingRow.hasPendingRescheduleRequest ? "Update Request" : "Request Change"
    }

    private var submitRequestButtonTitle: String {
        bookingRow.hasPendingRescheduleRequest ? "Update Request" : "Submit Request"
    }

    private var confirmedScheduledAt: Date {
        bookingRow.scheduledAtDate ?? scheduledAtForDisplay
    }

    private var rescheduleDraftBaselineDate: Date {
        bookingRow.pendingRescheduleRequest?.proposedScheduledAtDate ?? confirmedScheduledAt
    }

    private var rescheduleDraftBaselineLocation: String {
        let pending = bookingRow.pendingRescheduleRequest?.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !pending.isEmpty, !Self.isCoordinateLocationPlaceholder(pending) { return pending }
        return effectiveLocationString ?? ""
    }

    private var rescheduleDraftBaselineNotes: String {
        bookingRow.pendingRescheduleRequest?.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? bookingRow.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? ""
    }

    private var hasRescheduleDraftChanges: Bool {
        let scheduleDelta = abs(draftScheduledAt.timeIntervalSince(rescheduleDraftBaselineDate))
        if scheduleDelta > 60 { return true }
        let locDraft = draftLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if locDraft != rescheduleDraftBaselineLocation.trimmingCharacters(in: .whitespacesAndNewlines) { return true }
        let notesDraft = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if notesDraft != rescheduleDraftBaselineNotes.trimmingCharacters(in: .whitespacesAndNewlines) { return true }
        return false
    }

    private var hasServiceDraftChange: Bool {
        draftServiceName.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(effectiveServiceName) != .orderedSame
    }

    /// Provider marked the booking **COMPLETED** — consumer owes payment (same gate as `BookingPaymentRequestPayload.from(bookingRow:)`).
    private var showsPayForServiceCTA: Bool {
        let u = bookingRow.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard u == "COMPLETED" else { return false }
        return BookingPaymentRequestPayload.from(bookingRow: bookingRow) != nil
    }

    private var showsMessageProviderCTA: Bool {
        guard sessionManager.isAuthenticated else { return false }
        switch bookingMessagingMode {
        case .bookingsTab, .homeBookingPathHandoff:
            break
        }
        let u = bookingRow.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return !["CANCELLED", "REJECTED", "DECLINED", "REFUNDED"].contains(u)
    }

    /// Location isn’t persisted reliably for consumer bookings from iOS; hide it on **Past** detail so we don’t show a blank "—" row.
    private var showsLocationInBookingTimeline: Bool {
        bookingRow.scheduleSegment() != .past
    }

    /// Hides the entire location block when the only value is the “coordinate in chat” placeholder (no map / no label row for that).
    private var showsReadOnlyLocationTimelineBlock: Bool {
        guard showsLocationInBookingTimeline else { return false }
        if let loc = effectiveLocationString {
            return !Self.isCoordinateLocationPlaceholder(loc)
        }
        return true
    }

    private var scheduledAtForDisplay: Date {
        localScheduledAt ?? bookingRow.scheduledAtDate ?? Date()
    }

    private var effectiveServiceName: String {
        localServiceName ?? bookingRow.displayServiceName
    }

    /// Effective location including local edits after Confirm.
    private var effectiveLocationString: String? {
        let s = (localLocation ?? bookingRow.location)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    private var scheduleEditRange: ClosedRange<Date> {
        let end = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
        return Date() ... end
    }

    private var campusCutsClient: CampusCutsClient {
        CampusCutsClient(
            session: CampusCutsUserSessionAdapter(manager: sessionManager),
            environment: .production,
            isProduction: AppConfiguration.campusCutsProductionLiveDataMode
        )
    }

    var body: some View {
        bookingDetailScrollRoot
    }

    /// Split from `body` so the Swift compiler can type-check the stack (navigation + sheets + thread destination).
    private var bookingDetailScrollRoot: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 24) {
                heroSection

                bookingStatusPill

                if bookingRow.hasPendingRescheduleRequest {
                    pendingRescheduleBanner
                }

                if showsMessageProviderCTA {
                    messageProviderButton
                }

                if showsPayForServiceCTA {
                    VStack(spacing: 12) {
                        Text(payForServiceSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(BookingSelectorTheme.cream.opacity(0.88))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        Button {
                            chatViewModel.presentPaymentTakeover(forBookingRow: bookingRow)
                        } label: {
                            Text("Pay for this service")
                                .font(BookingSelectorTheme.todayBoldFont)
                                .foregroundStyle(BookingSelectorTheme.deepCharcoal)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 54)
                                .background {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(BookingSelectorTheme.cream)
                                }
                        }
                        .buttonStyle(BookButtonStyle())
                        .shadow(color: Color.oliveGreen.opacity(0.28), radius: 7, y: 2)
                    }
                    .padding(.top, 4)
                }

                if showsRebookCTA {
                    Button {
                        Task { await startRebookFlow() }
                    } label: {
                        HStack(spacing: 10) {
                            if isLoadingRebook {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(BookingSelectorTheme.deepCharcoal)
                            }
                            Text("Book again")
                                .font(BookingSelectorTheme.todayBoldFont)
                                .foregroundStyle(BookingSelectorTheme.deepCharcoal)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(BookingSelectorTheme.cream)
                        }
                        .opacity(isLoadingRebook ? 0.55 : 1)
                    }
                    .buttonStyle(BookButtonStyle())
                    .disabled(isLoadingRebook)
                    .shadow(color: Color.oliveGreen.opacity(0.28), radius: 7, y: 2)
                    .padding(.top, 4)
                }

                infoTimelineCard

                if formattedPrice != nil || bookingRow.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil {
                    supplementaryDetailsCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .refreshable {
            await refreshBookingDetailFromServer()
        }
        #if os(iOS)
        .scrollContentBackground(.hidden)
        #endif
        .background {
            Group {
                if usesExternalLavaBackdrop {
                    Color.clear
                } else {
                    InteraLavaLampBackground()
                        .ignoresSafeArea()
                }
            }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .tint(BookingSelectorTheme.cream)
        .sheet(isPresented: $showRebookSheet, onDismiss: {
            if let p = rebookProvider {
                PendingPostLoginBooking.clearIfGuestClosedBooking(
                    providerId: p.id,
                    isAuthenticated: sessionManager.isAuthenticated
                )
            }
            rebookProvider = nil
        }) {
            if let provider = rebookProvider {
                LiveBookingView(
                    provider: provider,
                    sessionManager: sessionManager,
                    onShowLogin: onShowLogin,
                    onDismiss: { showRebookSheet = false },
                    onBookingRequestSuccessfullySent: {
                        showRebookSheet = false
                        rebookProvider = nil
                        dismiss()
                    },
                    preselectServiceName: bookingRow.displayServiceName
                )
                .tint(Color.oliveGreen)
                .interaBookingFlowSheetPresentation()
            }
        }
        .alert("Active Booking Exists", isPresented: $showActiveBookingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You already have an active booking. Please complete or cancel it before making a new one.")
        }
        .alert("Stripe test mode", isPresented: $showLiveDataStripeAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Live Data Mode is on. Booking and live checkout are disabled so you do not email real barbers or charge real cards. Use a build with this flag off and Stripe test keys to exercise the full flow.")
        }
        .alert("Messages unavailable", isPresented: $showMessagingUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("We couldn’t open your conversation with this provider. Try again from the Messages tab.")
        }
        .onAppear {
            if localScheduledAt == nil { localScheduledAt = bookingRow.scheduledAtDate }
            if localServiceName == nil { localServiceName = bookingRow.displayServiceName }
        }
        .toolbar {
            if allowsBookingEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button(action: cancelEditing) {
                            bookingDetailGlassIconOrb(systemName: "xmark", accessibilityLabel: "Cancel editing")
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Button(action: beginEditing) {
                            bookingDetailGlassEditOrb(title: requestChangeToolbarTitle)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if allowsBookingEdit && isEditing {
                confirmChangesInset
            }
        }
        .confirmationDialog(
            "Cancel this booking?",
            isPresented: $showCancelBookingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel booking", role: .destructive) {
                Task { await performCancelBooking() }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Your provider will be notified. This can’t be undone.")
        }
        .sheet(isPresented: $showScheduleEditSheet) {
            scheduleEditHalfSheet
        }
        .task(id: isEditing) {
            guard isEditing, allowsBookingEdit else { return }
            await loadEditPickerOptions()
        }
    }

    @MainActor
    private func refreshBookingDetailFromServer() async {
        await InteraPullToRefresh.runMainActorAsyncIsolatedFromRefreshableCancellation {
            await performBookingDetailRefresh()
        }
    }

    @MainActor
    private func performBookingDetailRefresh() async {
        guard let session = sessionManager.currentSession else { return }
        guard let token = session.token.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            onShowLogin()
            return
        }
        do {
            let fresh = try await ConsumerBookingsSimpleAPI.fetchConsumerBookingById(
                bookingId: row.id,
                bearerToken: token
            )
            refreshedRow = fresh
            if !isEditing {
                localScheduledAt = fresh.scheduledAtDate
                localServiceName = fresh.displayServiceName
                localLocation = fresh.location
                draftNotes = fresh.pendingRescheduleRequest?.notes?.nilIfEmpty
                    ?? fresh.notes?.nilIfEmpty
                    ?? ""
            }
            NotificationCenter.default.post(name: .consumerBookingsListShouldRefresh, object: nil)
        } catch {
            if ConsumerBookingsSimpleAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
            } else {
                AlertManager.shared.presentErrorToast(error.localizedDescription)
            }
        }
    }

    private var showsRebookCTA: Bool {
        bookingRow.scheduleSegment() == .past
            && bookingRow.barberId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
            && !showsPayForServiceCTA
    }

    private var messageProviderButton: some View {
        Button {
            Task { @MainActor in
                await openProviderConversation()
            }
        } label: {
            HStack(spacing: 10) {
                if isOpeningMessaging {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BookingSelectorTheme.cream)
                }
                Image(systemName: "message.fill")
                    .font(.body.weight(.semibold))
                Text("Messages")
                    .font(BookingSelectorTheme.todayBoldFont)
            }
            .foregroundStyle(BookingSelectorTheme.cream)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(BookingSelectorTheme.cream.opacity(0.55), lineWidth: 1)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    }
            }
            .opacity(isOpeningMessaging ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isOpeningMessaging)
        .accessibilityLabel("Messages with \(bookingRow.barberDisplayName)")
        .accessibilityHint("Opens your conversation with this provider about this booking.")
    }

    @MainActor
    private func openProviderConversation() async {
        guard sessionManager.isAuthenticated else {
            onShowLogin()
            return
        }
        guard !isOpeningMessaging else { return }
        isOpeningMessaging = true
        defer { isOpeningMessaging = false }
        guard let handoff = await chatViewModel.presentMessagingThreadForBooking(
            row: bookingRow,
            sessionManager: sessionManager,
            presentationStack: .bookingsTabNavigation
        ) else {
            showMessagingUnavailableAlert = true
            return
        }
        if let presentBookingMessagingThread {
            presentBookingMessagingThread(handoff)
            return
        }
        switch bookingMessagingMode {
        case .bookingsTab:
            _ = chatViewModel.openBookingsTabMessagingThreadIfNeeded(handoff)
        case .homeBookingPathHandoff:
            _ = chatViewModel.openHomeBookingMessagingThreadIfNeeded(handoff)
        }
    }

    @MainActor
    private func startRebookFlow() async {
        guard let bid = bookingRow.barberId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return }
        if AppConfiguration.campusCutsProductionLiveDataMode {
            showLiveDataStripeAlert = true
            return
        }
        if hasActiveConsumerBooking {
            showActiveBookingAlert = true
            return
        }
        isLoadingRebook = true
        defer { isLoadingRebook = false }
        do {
            rebookProvider = try await CampusCutsBarberDetailAPI.fetchServiceProvider(
                barberId: bid,
                bearerToken: sessionManager.currentSession?.token
            )
        } catch {
            rebookProvider = rebookFallbackProvider(barberId: bid)
        }
        showRebookSheet = true
    }

    private func rebookFallbackProvider(barberId: String) -> ServiceProvider {
        ServiceProvider(
            id: barberId,
            userId: barberId,
            businessName: bookingRow.barberDisplayName,
            bio: nil,
            instagramHandle: nil,
            profileImageUrl: bookingRow.barberAvatar?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            rating: nil,
            reviewCount: nil,
            completedBookings: nil,
            isAvailableNow: nil,
            priceRange: nil,
            category: .haircuts,
            specialty: "Barber",
            services: nil,
            availability: nil,
            locations: nil,
            distanceMilesFromUser: nil,
            customerReviews: nil
        )
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .center, spacing: 12) {
            barberAvatar
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: BookingSelectorTheme.cornerRadius, style: .continuous))

            Text(bookingRow.barberDisplayName)
                .font(BookingSelectorTheme.todayBoldFont)
                .foregroundStyle(BookingSelectorTheme.cream)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)

            if allowsBookingEdit && isEditing {
                serviceEditHeroRow
            } else {
                Text(serviceTypePastLine)
                    .bookingCalendarWeekdayLabelStyle()
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.92))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var serviceTypePastLine: String {
        if let local = localServiceName?.trimmingCharacters(in: .whitespacesAndNewlines), !local.isEmpty {
            return local.uppercased()
        }
        if let t = bookingRow.serviceType?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t.replacingOccurrences(of: "_", with: " ").uppercased()
        }
        return bookingRow.displayServiceName.uppercased()
    }

    @ViewBuilder
    private var barberAvatar: some View {
        if let url = ProfileImageURLResolver.url(from: bookingRow.barberAvatar) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BookingSelectorTheme.cornerRadius, style: .continuous)
                .fill(BookingSelectorTheme.cream.opacity(0.12))
            Text(bookingRow.barberDisplayName.prefix(1).uppercased())
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(BookingSelectorTheme.cream)
        }
    }

    // MARK: - Status

    private var pendingRescheduleBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Schedule change pending approval", systemImage: "clock.badge.questionmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BookingSelectorTheme.cream)

            if let pending = bookingRow.pendingRescheduleRequest,
               let proposed = pending.proposedScheduledAtDate {
                Text("Requested: \(Self.dateOnlyDF.string(from: proposed)) at \(Self.timeOnlyDF.string(from: proposed))")
                    .font(.subheadline)
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.88))
            }

            if let loc = bookingRow.pendingRescheduleRequest?.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
               !Self.isCoordinateLocationPlaceholder(loc) {
                Text("Location: \(loc)")
                    .font(.caption)
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.78))
            }

            Text("Your confirmed appointment stays as shown below until your provider approves.")
                .font(.caption)
                .foregroundStyle(BookingSelectorTheme.cream.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.oliveGreen.opacity(0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.oliveGreen.opacity(0.45), lineWidth: 1)
                }
        }
    }

    private var bookingStatusPill: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .bookingCalendarWeekdayLabelStyle()
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.75))
                Text(bookingRow.displayStatus)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BookingSelectorTheme.cream)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(BookingSelectorTheme.cream, lineWidth: 1)
            }
        }
    }

    // MARK: - Timeline (date / time / location)

    private var infoTimelineCard: some View {
        VStack(alignment: .leading, spacing: (allowsBookingEdit && isEditing) ? 16 : 0) {
            if allowsBookingEdit && isEditing {
                Text("Propose a new date, time, or location. Your provider must approve before your appointment changes.")
                    .font(.caption)
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                dateEditTimelineRow()
                timeEditTimelineRow()
                if !alternativeLocationNames.isEmpty {
                    locationPickerEditRow(isLast: false)
                }
                notesEditRow(isLast: true)
            } else {
                let showLocation = showsReadOnlyLocationTimelineBlock
                timelineRow(
                    isLast: false,
                    label: "DATE",
                    value: formattedDateLine,
                    isEditingChrome: false
                )
                timelineRow(
                    isLast: !showLocation,
                    label: "TIME",
                    value: formattedTimeLine,
                    isEditingChrome: false
                )
                if showLocation {
                    readOnlyLocationBlock(isLast: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            timelineCardBackground
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isEditing)
    }

    @ViewBuilder
    private var timelineCardBackground: some View {
        if allowsBookingEdit && isEditing {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.clear)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            }
        }
    }

    @ViewBuilder
    private func readOnlyLocationBlock(isLast: Bool) -> some View {
        if let loc = effectiveLocationString, !Self.isCoordinateLocationPlaceholder(loc) {
            locationTimelineRow(isLast: isLast, locationText: loc)
        } else {
            timelineRow(
                isLast: isLast,
                label: "LOCATION",
                value: "—",
                isEditingChrome: false
            )
        }
    }

    /// Compact centered service menu under the provider name (no "SERVICE" label).
    private var serviceEditHeroRow: some View {
        Group {
            if isLoadingEditPickerOptions {
                ProgressView()
                    .tint(BookingSelectorTheme.cream)
                    .padding(.vertical, 8)
            } else {
                Picker(selection: $draftServiceName) {
                    ForEach(alternativeServiceNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                } label: {
                    HStack(alignment: .center, spacing: 6) {
                        Spacer(minLength: 0)
                        Text(draftServiceName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(BookingSelectorTheme.cream)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BookingSelectorTheme.cream.opacity(0.85))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
                .pickerStyle(.menu)
                .tint(BookingSelectorTheme.cream)
            }
        }
        .frame(maxWidth: Self.serviceEditHeroMaxWidth)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BookingSelectorTheme.cream, lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private static let serviceEditHeroMaxWidth: CGFloat = 280

    private func notesEditRow(isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTES (OPTIONAL)")
                .bookingCalendarWeekdayLabelStyle()
                .foregroundStyle(BookingSelectorTheme.cream.opacity(0.78))
            TextField("Add a note for your provider", text: $draftNotes, axis: .vertical)
                .lineLimit(2 ... 4)
                .font(.body.weight(.medium))
                .foregroundStyle(BookingSelectorTheme.cream)
                .textFieldStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BookingSelectorTheme.cream, lineWidth: 1)
        }
        .padding(.bottom, isLast ? 0 : 0)
    }

    /// Menu-style picker for provider preset locations (only shown when at least one exists).
    private func locationPickerEditRow(isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LOCATION")
                .bookingCalendarWeekdayLabelStyle()
                .foregroundStyle(BookingSelectorTheme.cream.opacity(0.78))
            if isLoadingEditPickerOptions {
                ProgressView()
                    .tint(BookingSelectorTheme.cream)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                Picker(selection: $draftLocation) {
                    ForEach(alternativeLocationNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Text(draftLocation)
                            .font(.body.weight(.medium))
                            .foregroundStyle(BookingSelectorTheme.cream)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BookingSelectorTheme.cream.opacity(0.85))
                    }
                }
                .pickerStyle(.menu)
                .tint(BookingSelectorTheme.cream)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BookingSelectorTheme.cream, lineWidth: 1)
        }
    }

    private func dateEditTimelineRow() -> some View {
        Button {
            scheduleEditEntry = .date
            showScheduleEditSheet = true
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("DATE")
                    .bookingCalendarWeekdayLabelStyle()
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.78))
                Text(formattedDraftDateLine)
                    .font(.body.weight(.medium))
                    .foregroundStyle(BookingSelectorTheme.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BookingSelectorTheme.cream, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func timeEditTimelineRow() -> some View {
        Button {
            scheduleEditEntry = .time
            showScheduleEditSheet = true
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("TIME")
                    .bookingCalendarWeekdayLabelStyle()
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.78))
                Text(formattedDraftTimeLine)
                    .font(.body.weight(.medium))
                    .foregroundStyle(BookingSelectorTheme.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BookingSelectorTheme.cream, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var formattedDraftDateLine: String {
        Self.dateOnlyDF.string(from: draftScheduledAt)
    }

    private var formattedDraftTimeLine: String {
        Self.timeOnlyDF.string(from: draftScheduledAt)
    }

    private func locationTimelineRow(isLast: Bool, locationText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOCATION")
                .bookingCalendarWeekdayLabelStyle()
                .foregroundStyle(BookingSelectorTheme.cream.opacity(0.78))
            Text(locationText)
                .font(.body.weight(.medium))
                .foregroundStyle(BookingSelectorTheme.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, isLast ? 0 : 18)
        .background(Color.clear)
    }

    private func timelineRow(
        isLast: Bool,
        label: String,
        value: String,
        isEditingChrome: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .bookingCalendarWeekdayLabelStyle()
                .foregroundStyle(BookingSelectorTheme.cream.opacity(0.78))
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(BookingSelectorTheme.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, isLast ? 0 : 18)
        .padding(isEditingChrome ? 12 : 0)
        .background(Color.clear)
        .overlay {
            if isEditingChrome {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BookingSelectorTheme.cream, lineWidth: 1)
            }
        }
    }

    // MARK: - Supplementary (price / notes)

    private var supplementaryDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let price = formattedPrice {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRICE")
                        .bookingCalendarWeekdayLabelStyle()
                        .foregroundStyle(BookingSelectorTheme.cream.opacity(0.78))
                    Text(price)
                        .font(.body.weight(.medium))
                        .foregroundStyle(BookingSelectorTheme.cream)
                }
            }
            if let n = bookingRow.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTES")
                        .bookingCalendarWeekdayLabelStyle()
                        .foregroundStyle(BookingSelectorTheme.cream.opacity(0.78))
                    Text(n)
                        .font(.body)
                        .foregroundStyle(BookingSelectorTheme.cream)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            }
        }
    }

    private var formattedDateLine: String {
        Self.dateOnlyDF.string(from: scheduledAtForDisplay)
    }

    private var formattedTimeLine: String {
        Self.timeOnlyDF.string(from: scheduledAtForDisplay)
    }

    private var formattedPrice: String? {
        guard let cents = bookingRow.priceUsdCents, cents > 0 else { return nil }
        let dollars = Decimal(cents) / 100
        return Self.currencyFormatter.string(from: NSDecimalNumber(decimal: dollars))
    }

    private var payForServiceSubtitle: String {
        if let p = formattedPrice {
            return "Your provider marked this visit complete. Pay \(p) with Apple Pay, card, or cash (in person)."
        }
        return "Your provider marked this visit complete. Pay with Apple Pay, card, or cash (in person)."
    }

    // MARK: - Edit mode actions

    private func beginEditing() {
        if let proposed = bookingRow.pendingRescheduleRequest?.proposedScheduledAtDate {
            draftScheduledAt = proposed
        } else {
            draftScheduledAt = confirmedScheduledAt
        }
        draftServiceName = effectiveServiceName
        let baselineLoc = rescheduleDraftBaselineLocation
        if !baselineLoc.isEmpty, !Self.isCoordinateLocationPlaceholder(baselineLoc) {
            draftLocation = baselineLoc
        } else if let loc = effectiveLocationString, !Self.isCoordinateLocationPlaceholder(loc) {
            draftLocation = loc
        } else {
            draftLocation = ""
        }
        draftNotes = rescheduleDraftBaselineNotes
        draftCalendarCommitted = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            isEditing = true
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
    }

    private func cancelEditing() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            isEditing = false
        }
    }

    private func confirmEdits() {
        Task { await saveBookingEdits() }
    }

    @MainActor
    private func performCancelBooking() async {
        guard !isCancellingBooking else { return }
        guard let session = sessionManager.currentSession else {
            onShowLogin()
            return
        }
        guard let token = session.token.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            onShowLogin()
            return
        }
        isCancellingBooking = true
        defer { isCancellingBooking = false }
        do {
            let fresh = try await ConsumerBookingsSimpleAPI.fetchConsumerBookingById(bookingId: bookingRow.id, bearerToken: token)
            let u = fresh.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard u == "PENDING" || u == "ACCEPTED" else {
                AlertManager.shared.presentErrorToast(
                    "This booking cannot be cancelled. Current status: \(fresh.displayStatus)."
                )
                return
            }
            try await MessagingAPIService.cancelBookingSimple(bookingId: bookingRow.id, bearerToken: token)
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            NotificationCenter.default.post(name: .consumerBookingsListShouldRefresh, object: nil)
            dismiss()
        } catch {
            if ConsumerBookingsSimpleAPI.isUnauthorizedHTTPError(error) || MessagingAPIService.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
                onShowLogin()
            } else {
                AlertManager.shared.presentErrorToast(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func saveBookingEdits() async {
        guard !isConfirmingEdits else { return }
        guard let session = sessionManager.currentSession else {
            onShowLogin()
            return
        }
        guard let token = session.token.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            onShowLogin()
            return
        }
        isConfirmingEdits = true
        defer { isConfirmingEdits = false }

        guard hasRescheduleDraftChanges || hasServiceDraftChange else {
            AlertManager.shared.presentErrorToast("Change the date, time, location, notes, or service before submitting.")
            return
        }

        let iso = BookingPacificSchedule.scheduledTimeStringForAPI(from: draftScheduledAt)
        let locRaw = draftLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let locForAPI: String? = {
            if locRaw.isEmpty || Self.isCoordinateLocationPlaceholder(locRaw) { return nil }
            return locRaw
        }()
        let notesForAPI = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let svcRaw = draftServiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let svcForAPI = svcRaw.isEmpty ? bookingRow.displayServiceName : svcRaw

        do {
            if hasRescheduleDraftChanges {
                _ = try await ConsumerBookingsSimpleAPI.submitRescheduleRequest(
                    bookingId: bookingRow.id,
                    scheduledTimeISO: iso,
                    location: locForAPI,
                    notes: notesForAPI,
                    bearerToken: token
                )
            }
            if hasServiceDraftChange {
                try await ConsumerBookingsSimpleAPI.updateConsumerBookingMetadata(
                    bookingId: bookingRow.id,
                    location: hasRescheduleDraftChanges ? nil : locForAPI,
                    serviceName: svcForAPI,
                    bearerToken: token
                )
            }
            if hasServiceDraftChange {
                localServiceName = draftServiceName
            }
            await performBookingDetailRefresh()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isEditing = false
            }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            AlertManager.shared.present(
                hasRescheduleDraftChanges
                    ? "Schedule change requested. Your provider will review it."
                    : "Booking details updated."
            )
            NotificationCenter.default.post(name: .consumerBookingsListShouldRefresh, object: nil)
        } catch {
            if ConsumerBookingsSimpleAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
            } else {
                AlertManager.shared.presentErrorToast(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func loadEditPickerOptions() async {
        isLoadingEditPickerOptions = true
        defer { isLoadingEditPickerOptions = false }

        func mergeServiceNames(_ apiNames: [String]) -> [String] {
            let trimmed = apiNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            var merged = trimmed.isEmpty ? [effectiveServiceName] : trimmed
            if !merged.contains(where: { $0.caseInsensitiveCompare(draftServiceName) == .orderedSame }) {
                merged.insert(draftServiceName, at: 0)
            }
            return merged
        }

        func mergeLocationNames(_ apiLocs: [String]) -> [String] {
            var set = Set(
                apiLocs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !Self.isCoordinateLocationPlaceholder($0) }
            )
            let cur = draftLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cur.isEmpty, !Self.isCoordinateLocationPlaceholder(cur) { set.insert(cur) }
            if let persisted = effectiveLocationString, !Self.isCoordinateLocationPlaceholder(persisted) {
                set.insert(persisted)
            }
            return set.sorted()
        }

        guard let bid = bookingRow.barberId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            alternativeServiceNames = mergeServiceNames([])
            alternativeLocationNames = mergeLocationNames([])
            return
        }

        do {
            let provider = try await CampusCutsBarberDetailAPI.fetchServiceProvider(
                barberId: bid,
                bearerToken: sessionManager.currentSession?.token
            )
            let serviceNames = (provider.services ?? []).map(\.name)
            alternativeServiceNames = mergeServiceNames(serviceNames)
            let locs = provider.locations ?? []
            alternativeLocationNames = mergeLocationNames(locs)
            if !alternativeLocationNames.isEmpty, !alternativeLocationNames.contains(where: { $0 == draftLocation }) {
                draftLocation = alternativeLocationNames[0]
            }
            if !alternativeServiceNames.contains(where: { $0 == draftServiceName }) {
                draftServiceName = alternativeServiceNames[0]
            }
        } catch {
            alternativeServiceNames = mergeServiceNames([])
            alternativeLocationNames = mergeLocationNames([])
        }
    }

    // MARK: - Schedule edit availability (provider-published slots)

    @MainActor
    private func loadScheduleEditDaySlots() async {
        scheduleEditSlotsLoading = true
        scheduleEditSlotsError = nil
        defer { scheduleEditSlotsLoading = false }

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: draftScheduledAt)
        var slots = await fetchRibbonSlotsForEditDay(dayStart)
        let currentKey = pacificHHmmKey(from: draftScheduledAt)

        if let idx = slots.firstIndex(where: { $0.timeKey == currentKey }) {
            let s = slots[idx]
            slots[idx] = BookingRibbonSlot(timeKey: s.timeKey, label: s.label, available: true)
        } else if !currentKey.isEmpty {
            slots.append(
                BookingRibbonSlot(
                    timeKey: currentKey,
                    label: editSlotDisplayLabel(hhmm: currentKey),
                    available: true
                )
            )
            slots.sort { $0.timeKey < $1.timeKey }
        }

        scheduleEditSlotRows = dedupeEditRibbonSlots(slots).availableOnly

        if scheduleEditSlotRows.isEmpty {
            scheduleEditSlotsError = "No open times for this day."
        } else {
            scheduleEditSlotsError = nil
        }
        editTimePickerKey = currentKey.isEmpty ? scheduleEditSlotRows.first?.timeKey : currentKey
    }

    private func fetchRibbonSlotsForEditDay(_ day: Date) async -> [BookingRibbonSlot] {
        let dayStr = BookingPacificSchedule.apiDateString(from: day)
        guard let bid = bookingRow.barberId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return []
        }
        if let intId = Int(bid) {
            do {
                let campus = try await campusCutsClient.fetchBarberDayAvailability(barberId: intId, dateYYYYMMDD: dayStr)
                let mapped = campus.map {
                    BookingRibbonSlot(
                        timeKey: normalizeEditSlotTimeKey($0.startTime),
                        label: editSlotDisplayLabel(hhmm: normalizeEditSlotTimeKey($0.startTime)),
                        available: $0.isAvailable
                    )
                }
                if !mapped.isEmpty {
                    return dedupeEditRibbonSlots(mapped)
                }
            } catch {
                if InteraRefreshCancellation.isBenignCancellation(error) { return [] }
            }
        }
        do {
            let rows = try await BarberAvailabilityAPI.fetchDaySlots(
                barberId: bid,
                dateYYYYMMDD: dayStr,
                bearerToken: sessionManager.currentSession?.token
            )
            let mapped = rows.map {
                BookingRibbonSlot(timeKey: $0.time, label: editSlotDisplayLabel(hhmm: $0.time), available: $0.available)
            }
            return dedupeEditRibbonSlots(mapped)
        } catch {
            if InteraRefreshCancellation.isBenignCancellation(error) { return [] }
            return []
        }
    }

    private func normalizeEditSlotTimeKey(_ startTime: String) -> String {
        let trimmed = startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return trimmed }
        let colonIdx = trimmed.index(trimmed.startIndex, offsetBy: 2)
        guard trimmed[colonIdx] == ":" else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 5)
        return String(trimmed[..<end])
    }

    /// Slot keys are **Pacific** (barber availability). Labels use the **device timezone** so the grid matches Clock / user expectation.
    private func editSlotDisplayLabel(hhmm: String) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = BookingPacificSchedule.pacificTimeZone
        let parts = hhmm.split(separator: ":")
        guard parts.count >= 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else { return hhmm }
        let day = cal.dateComponents([.year, .month, .day], from: draftScheduledAt)
        var full = DateComponents()
        full.timeZone = BookingPacificSchedule.pacificTimeZone
        full.year = day.year
        full.month = day.month
        full.day = day.day
        full.hour = h
        full.minute = m
        full.second = 0
        guard let instant = cal.date(from: full) else { return hhmm }
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: instant)
    }

    private func dedupeEditRibbonSlots(_ rows: [BookingRibbonSlot]) -> [BookingRibbonSlot] {
        var seen = Set<String>()
        let sorted = rows.sorted { $0.timeKey < $1.timeKey }
        return sorted.filter { seen.insert($0.timeKey).inserted }
    }

    private func pacificHHmmKey(from date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = BookingPacificSchedule.pacificTimeZone
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return String(format: "%02d:%02d", h, m)
    }

    private func applyPacificTimeKey(_ key: String, keepingScheduledDate scheduled: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = BookingPacificSchedule.pacificTimeZone
        let dcDay = cal.dateComponents([.year, .month, .day], from: scheduled)
        let parts = key.split(separator: ":")
        guard let h = Int(parts[0]), let m = Int(parts[1]) else { return }
        var full = DateComponents()
        full.timeZone = BookingPacificSchedule.pacificTimeZone
        full.year = dcDay.year
        full.month = dcDay.month
        full.day = dcDay.day
        full.hour = h
        full.minute = m
        full.second = 0
        if let d = cal.date(from: full) {
            draftScheduledAt = d
        }
    }

    // MARK: - Edit chrome (toolbar + CTA + schedule sheet)

    private var scheduleEditCalendarBlock: some View {
        BookingCalendarGridSelector(
            selectedDate: $draftScheduledAt,
            selectionCommitted: $draftCalendarCommitted,
            range: scheduleEditRange,
            onDaySelected: {}
        )
    }

    private var scheduleEditTimeSlotBlock: some View {
        Group {
            if scheduleEditSlotsLoading || (scheduleEditSlotRows.isEmpty && scheduleEditSlotsError == nil) {
                ProgressView()
                    .tint(BookingSelectorTheme.cream)
                    .padding(.vertical, 36)
            } else if scheduleEditSlotRows.isEmpty {
                Text(scheduleEditSlotsError ?? "No open times for this day.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 16)
            } else {
                BookingTimeSlotGrid(
                    slots: scheduleEditSlotRows,
                    selectedTimeKey: $editTimePickerKey,
                    selectedCalendarDay: draftScheduledAt
                )
                    .onChange(of: editTimePickerKey) { _, newKey in
                        guard let newKey else { return }
                        applyPacificTimeKey(newKey, keepingScheduledDate: draftScheduledAt)
                    }
            }
        }
    }

    private var confirmChangesInset: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: confirmEdits) {
                    HStack(spacing: 10) {
                        if isConfirmingEdits {
                            ProgressView()
                                .controlSize(.small)
                                .tint(BookingSelectorTheme.deepCharcoal)
                        }
                        Text(submitRequestButtonTitle)
                            .font(BookingSelectorTheme.todayBoldFont)
                            .foregroundStyle(BookingSelectorTheme.deepCharcoal)
                    }
                    .contentTransition(.interpolate)
                    .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isEditing)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(BookingSelectorTheme.cream)
                    }
                }
                .buttonStyle(BookButtonStyle())
                .disabled(isConfirmingEdits || isCancellingBooking || (!hasRescheduleDraftChanges && !hasServiceDraftChange))
                .opacity((isConfirmingEdits || isCancellingBooking || (!hasRescheduleDraftChanges && !hasServiceDraftChange)) ? 0.55 : 1)
                .frame(maxWidth: .infinity)

                Button {
                    showCancelBookingConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        if isCancellingBooking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.red)
                        }
                        Text("Cancel Booking")
                            .font(BookingSelectorTheme.todayBoldFont)
                            .foregroundStyle(Color.red)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.red.opacity(0.85), lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isConfirmingEdits || isCancellingBooking)
                .opacity((isConfirmingEdits || isCancellingBooking) ? 0.55 : 1)
                .accessibilityLabel("Cancel booking")
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isEditing)
    }

    private var scheduleEditHalfSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if scheduleEditEntry == .date {
                        scheduleEditCalendarBlock
                    } else {
                        scheduleEditTimeSlotBlock
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 28)
            }
            .task(id: scheduleEditEntry) {
                guard scheduleEditEntry == .time else { return }
                await loadScheduleEditDaySlots()
            }
            .navigationTitle(scheduleEditEntry == .date ? "Request Schedule Change" : "Choose a Time")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showScheduleEditSheet = false
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BookingSelectorTheme.cream)
                }
            }
        }
        .tint(BookingSelectorTheme.cream)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            ZStack {
                Color.black.opacity(0.48)
                Rectangle()
                    .fill(Material.ultraThickMaterial)
            }
        }
    }

    private func bookingDetailGlassEditOrb(title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(BookingSelectorTheme.cream)
            .accessibilityLabel("Edit booking details")
    }

    private func bookingDetailGlassIconOrb(systemName: String, accessibilityLabel: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(BookingSelectorTheme.cream)
            .accessibilityLabel(accessibilityLabel)
    }
}

private extension ConsumerBookingSimpleRow {
    var barberDisplayName: String {
        barberName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Provider"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#if DEBUG
#Preview {
    let manager = AppSessionManager()
    manager.mockLogin(as: .student)
    let coordinator = MainCoordinator(sessionManager: manager)

    return NavigationStack {
        ConsumerBookingDetailView(
            row: ConsumerBookingSimpleRow(
                id: "preview-1",
                barberId: "barber-preview",
                serviceType: "HAIRCUT",
                serviceName: "Fade",
                scheduledTime: "2026-04-02T15:00:00.000Z",
                status: "PENDING",
                barberName: "Alex Barber",
                barberAvatar: nil,
                location: "Dorm quad",
                notes: "Please bring clippers",
                priceUsdCents: 3500,
                pendingRescheduleRequest: nil
            ),
            sessionManager: manager,
            coordinator: coordinator
        )
    }
    .environmentObject(ChatViewModel())
}
#endif
