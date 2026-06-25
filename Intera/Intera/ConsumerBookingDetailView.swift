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
    @FocusState private var isRequestChangeNotesFocused: Bool
    @State private var showScheduleEditSheet = false
    /// Which row opened the schedule sheet (drives the navigation title).
    @State private var scheduleEditEntry: ScheduleEditEntry = .date

    private enum ScheduleEditEntry {
        case date
        case time
    }

    @State private var scheduleEditSlotsError: String?
    @State private var scheduleEditSlotRows: [BookingRibbonSlot] = []
    @State private var scheduleEditAvailableTimeKeys: Set<String> = []
    @State private var scheduleEditSlotsLoading = false
    @State private var scheduleEditOpenDaysByMonthKey: [String: Set<Date>] = [:]
    @State private var scheduleEditLoadingOpenDaysMonthKeys: Set<String> = []
    @State private var scheduleEditDisplayedMonth = Date()

    @State private var alternativeServiceNames: [String] = []
    @State private var alternativeLocationNames: [String] = []
    @State private var isLoadingEditPickerOptions = false
    @State private var isConfirmingEdits = false
    @State private var isConfirmingCancelBooking = false
    @State private var isCancellingBooking = false

    /// Snapshotted when Request Change edit chrome finishes loading picker options — Submit stays inert until drafts differ.
    @State private var requestChangeBaselineScheduledAt = Date()
    @State private var requestChangeBaselineServiceName = ""
    @State private var requestChangeBaselineLocation = ""
    @State private var requestChangeBaselineNotes = ""
    @State private var requestChangeBaselinesReady = false

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

    private func normalizedRequestChangeDraft(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasRequestChangeDraftChanges: Bool {
        guard isEditing, requestChangeBaselinesReady else { return false }
        var pacificCal = Calendar(identifier: .gregorian)
        pacificCal.timeZone = BookingPacificSchedule.pacificTimeZone
        if pacificCal.startOfDay(for: draftScheduledAt) != pacificCal.startOfDay(for: requestChangeBaselineScheduledAt) {
            return true
        }
        if BookingPacificSchedule.pacificHHmmKey(from: draftScheduledAt)
            != BookingPacificSchedule.pacificHHmmKey(from: requestChangeBaselineScheduledAt) {
            return true
        }
        if normalizedRequestChangeDraft(draftLocation) != normalizedRequestChangeDraft(requestChangeBaselineLocation) {
            return true
        }
        if normalizedRequestChangeDraft(draftNotes) != normalizedRequestChangeDraft(requestChangeBaselineNotes) {
            return true
        }
        // Service edits disabled — Request Change is date/time only.
        // if normalizedRequestChangeDraft(draftServiceName).caseInsensitiveCompare(
        //     normalizedRequestChangeDraft(requestChangeBaselineServiceName)
        // ) != .orderedSame {
        //     return true
        // }
        return false
    }

    private var hasScheduleDraftChangesFromRequestBaseline: Bool {
        guard requestChangeBaselinesReady else { return false }
        var pacificCal = Calendar(identifier: .gregorian)
        pacificCal.timeZone = BookingPacificSchedule.pacificTimeZone
        if pacificCal.startOfDay(for: draftScheduledAt) != pacificCal.startOfDay(for: requestChangeBaselineScheduledAt) {
            return true
        }
        if BookingPacificSchedule.pacificHHmmKey(from: draftScheduledAt)
            != BookingPacificSchedule.pacificHHmmKey(from: requestChangeBaselineScheduledAt) {
            return true
        }
        if normalizedRequestChangeDraft(draftLocation) != normalizedRequestChangeDraft(requestChangeBaselineLocation) {
            return true
        }
        if normalizedRequestChangeDraft(draftNotes) != normalizedRequestChangeDraft(requestChangeBaselineNotes) {
            return true
        }
        return false
    }

    // Service edits disabled — Request Change is date/time only.
    // private var hasServiceDraftChangeFromRequestBaseline: Bool {
    //     guard requestChangeBaselinesReady else { return false }
    //     return normalizedRequestChangeDraft(draftServiceName).caseInsensitiveCompare(
    //         normalizedRequestChangeDraft(requestChangeBaselineServiceName)
    //     ) != .orderedSame
    // }

    private var isRequestChangeEditing: Bool {
        allowsBookingEdit && isEditing
    }

    /// Provider marked the booking **COMPLETED** — consumer owes payment (same gate as `BookingPaymentRequestPayload.from(bookingRow:)`).
    private var showsPayForServiceCTA: Bool {
        let u = bookingRow.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard u == "COMPLETED" else { return false }
        return BookingPaymentRequestPayload.from(bookingRow: bookingRow) != nil
    }

    private var showsMessageProviderCTA: Bool {
        guard sessionManager.isAuthenticated else { return false }
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

    private var scheduleEditAllowedDayStarts: Set<Date>? {
        let cal = Calendar.current
        let monthKey = BookingPacificSchedule.monthCacheKey(for: scheduleEditDisplayedMonth)
        let preservedDays: Set<Date> = [
            cal.startOfDay(for: requestChangeBaselineScheduledAt),
            cal.startOfDay(for: draftScheduledAt),
        ]

        if let apiDays = scheduleEditOpenDaysByMonthKey[monthKey] {
            return apiDays.union(preservedDays)
        }

        if scheduleEditLoadingOpenDaysMonthKeys.contains(monthKey) {
            return nil
        }

        return nil
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
        bookingDetailScrollRootCore
            .bookingDetailRequestChangeKeyboardHandling(
                isEditing: isEditing,
                showScheduleEditSheet: $showScheduleEditSheet,
                dismissNotesKeyboard: dismissRequestChangeNotesKeyboard
            )
    }

    private var bookingDetailScrollRootCore: some View {
        ScrollView {
            bookingDetailScrollContent
        }
        .refreshable {
            await refreshBookingDetailFromServer()
        }
        #if os(iOS)
        .scrollDismissesKeyboard(isRequestChangeEditing ? .immediately : .automatic)
        #endif
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
            Text("Live Data Mode is on. Booking and live checkout are disabled so you do not email real service providers or charge real cards. Use a build with this flag off and Stripe test keys to exercise the full flow.")
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
            ToolbarItem(placement: .principal) {
                Text(displayableServiceLine)
                    .font(Self.heroServiceDisplayFont)
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if allowsBookingEdit && !isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: beginEditing) {
                        bookingDetailToolbarIcon(
                            systemName: "pencil",
                            accessibilityLabel: requestChangeToolbarTitle
                        )
                    }
                    .buttonStyle(.borderless)
                }
            } else if allowsBookingEdit && isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: cancelEditing) {
                        bookingDetailToolbarIcon(
                            systemName: "xmark",
                            accessibilityLabel: "Cancel editing"
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if allowsBookingEdit && isEditing {
                confirmChangesInset
            }
        }
        .sheet(isPresented: $showScheduleEditSheet) {
            scheduleEditHalfSheet
        }
        .task(id: isEditing) {
            guard isEditing, allowsBookingEdit else {
                requestChangeBaselinesReady = false
                return
            }
            requestChangeBaselinesReady = false
            await loadEditPickerOptions()
            captureRequestChangeBaselines()
        }
        .navigationDestination(item: chatViewModel.bookingDetailMessagingThreadHandoffBinding(forBookingId: bookingRow.id)) { handoff in
            bookingDetailMessagingThreadDestination(handoff)
        }
    }

    @ViewBuilder
    private func bookingDetailMessagingThreadDestination(_ handoff: ChatViewModel.BookingMessagingThreadHandoff) -> some View {
        MessagingConversationView(
            conversationId: handoff.conversationId,
            sessionManager: sessionManager,
            coordinator: coordinator,
            initialBooking: handoff.bookingSnapshot,
            counterpartyAvatarURLString: handoff.counterpartyAvatarURLString,
            counterpartyFallbackDisplayName: handoff.counterpartyFallbackName,
            initialDraftText: handoff.initialDraft.isEmpty ? nil : handoff.initialDraft,
            onNavigationVisibilityChanged: { visible, _ in
                if !visible {
                    chatViewModel.promoteOrInsertConversationFromHandoff(handoff)
                    chatViewModel.clearBookingDetailMessagingThreadPresentation()
                }
            },
            onResyncSharedHubInboxSilently: {
                await chatViewModel.reloadInboxSilently(sessionManager: sessionManager)
            },
            counterpartyUserId: handoff.counterpartyMessagingUserId,
            hasActiveConsumerBooking: hasActiveConsumerBooking,
            onShowLogin: onShowLogin
        )
        #if os(iOS)
        .interaNavigationShellBackgroundClear()
        #endif
    }

    private var bookingDetailScrollContent: some View {
        VStack(alignment: .center, spacing: isRequestChangeEditing ? 8 : 24) {
            requestChangeEditingHeroSection

            if !isRequestChangeEditing {
                bookingStatusAndPriceRow
            }

            if bookingRow.hasPendingRescheduleRequest {
                pendingRescheduleBanner
            }

            if showsPayForServiceCTA {
                bookingDetailPayForServiceBlock
            }

            if showsRebookCTA {
                bookingDetailRebookBlock
            }

            infoTimelineCard

            if !isRequestChangeEditing,
               bookingRow.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil {
                supplementaryDetailsCard
            }

            if !isRequestChangeEditing {
                bookingReferenceFooter
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var bookingDetailPayForServiceBlock: some View {
        VStack(spacing: 12) {
            Text(payForServiceSubtitle)
                .font(InteraFont.subheadline)
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

    private var bookingDetailRebookBlock: some View {
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

    private static let heroServiceDisplayFont = InteraFont.subheadline.weight(.semibold)
    private static let editBottomBarButtonFont = InteraFont.footnote.weight(.semibold)
    private static let bookingDetailCircularActionButtonSize: CGFloat = 44

    private var messageProviderCircularButton: some View {
        Button {
            Task { @MainActor in
                await openProviderConversation()
            }
        } label: {
            bookingDetailCircularIconButton(
                systemName: "message.fill",
                accessibilityLabel: "Message \(bookingRow.providerKindTag)",
                showsProgress: isOpeningMessaging
            )
        }
        .buttonStyle(.plain)
        .disabled(isOpeningMessaging)
        .opacity(isOpeningMessaging ? 0.55 : 1)
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
        let opened = await chatViewModel.presentBookingDetailMessagingThread(
            row: bookingRow,
            sessionManager: sessionManager
        )
        if !opened {
            showMessagingUnavailableAlert = true
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

    @ViewBuilder
    private var requestChangeEditingHeroSection: some View {
        if isRequestChangeEditing {
            heroSection
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissRequestChangeNotesKeyboard)
        } else {
            heroSection
        }
    }

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

            if showsMessageProviderCTA && !isEditing {
                messageProviderCircularButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var displayableServiceLine: String {
        if let local = localServiceName?.trimmingCharacters(in: .whitespacesAndNewlines), !local.isEmpty {
            return ConsumerBookingSimpleRow.displayableServiceLabel(local)
        }
        return bookingRow.displayServiceName
    }

    // private var displayableDraftServiceName: String {
    //     ConsumerBookingSimpleRow.displayableServiceLabel(draftServiceName)
    // }

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
                .font(InteraFont.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(BookingSelectorTheme.cream)
        }
    }

    // MARK: - Status

    private var confirmedFormattedDateLine: String {
        Self.dateOnlyDF.string(from: confirmedScheduledAt)
    }

    private var confirmedFormattedTimeLine: String {
        BookingPacificSchedule.displayTimeWithMinutes(from: confirmedScheduledAt)
    }

    private var proposedFormattedDateLine: String? {
        bookingRow.pendingRescheduleRequest?.proposedScheduledAtDate.map {
            Self.dateOnlyDF.string(from: $0)
        }
    }

    private var proposedFormattedTimeLine: String? {
        bookingRow.pendingRescheduleRequest?.proposedScheduledAtDate.map {
            BookingPacificSchedule.displayTimeWithMinutes(from: $0)
        }
    }

    private var confirmedBookingLocationLine: String? {
        let s = (bookingRow.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !Self.isCoordinateLocationPlaceholder(s) else { return nil }
        return s
    }

    private var pendingRequestedLocationLine: String? {
        let pending = bookingRow.pendingRescheduleRequest?.location?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !pending.isEmpty, !Self.isCoordinateLocationPlaceholder(pending) {
            return pending
        }
        return confirmedBookingLocationLine
    }

    private var pendingLocationDiffersFromConfirmed: Bool {
        let confirmed = normalizedRequestChangeDraft(confirmedBookingLocationLine ?? "")
        let requestedRaw = bookingRow.pendingRescheduleRequest?.location?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !requestedRaw.isEmpty, !Self.isCoordinateLocationPlaceholder(requestedRaw) else { return false }
        return normalizedRequestChangeDraft(requestedRaw) != confirmed
    }

    private var pendingRescheduleBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Schedule change pending approval")
                .font(InteraFont.subheadline.weight(.semibold))
                .foregroundStyle(BookingSelectorTheme.cream)

            Text("Your \(bookingRow.providerKindTag) must approve before your booking updates.")
                .font(InteraFont.caption)
                .foregroundStyle(BookingSelectorTheme.cream.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
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

    private var bookingStatusAndPriceRow: some View {
        HStack(alignment: .center, spacing: 12) {
            bookingDetailMetricButton(
                title: "Status",
                value: bookingRow.displayStatus
            )
            if let price = formattedPrice {
                bookingDetailMetricButton(title: "Price", value: price)
            }
        }
    }

    private func bookingDetailMetricButton(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Text(title)
                .bookingDetailFieldTitleStyle()
                .multilineTextAlignment(.center)
            Text(value)
                .font(InteraFont.body.weight(.semibold))
                .foregroundStyle(BookingSelectorTheme.cream)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
    }

    // MARK: - Timeline (date / time / location)

    private var infoTimelineCard: some View {
        VStack(alignment: .leading, spacing: (allowsBookingEdit && isEditing) ? 16 : 0) {
            if allowsBookingEdit && isEditing {
                requestChangeInstructions

                dateEditTimelineRow()
                timeEditTimelineRow()
                if !alternativeLocationNames.isEmpty {
                    locationPickerEditRow(isLast: false)
                }
                notesEditRow(isLast: true)
            } else if bookingRow.hasPendingRescheduleRequest {
                pendingScheduleComparisonTimeline(showLocation: showsReadOnlyLocationTimelineBlock)
            } else {
                let showLocation = showsReadOnlyLocationTimelineBlock
                timelineRow(
                    isLast: false,
                    label: "Date",
                    value: formattedDateLine,
                    isEditingChrome: false
                )
                timelineRow(
                    isLast: !showLocation,
                    label: "Time",
                    value: formattedTimeLine,
                    isEditingChrome: false
                )
                if showLocation {
                    readOnlyLocationBlock(isLast: true)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, isRequestChangeEditing ? 4 : 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            timelineCardBackground
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isEditing)
    }

    private enum PendingScheduleSnapshotStyle {
        case confirmed
        case requested
    }

    @ViewBuilder
    private func pendingScheduleComparisonTimeline(showLocation: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            pendingScheduleSnapshotSection(
                title: "Confirmed appointment",
                dateLine: confirmedFormattedDateLine,
                timeLine: confirmedFormattedTimeLine,
                locationLine: showLocation ? confirmedBookingLocationLine : nil,
                style: .confirmed
            )

            pendingScheduleSnapshotSection(
                title: "Requested change",
                dateLine: proposedFormattedDateLine ?? confirmedFormattedDateLine,
                timeLine: proposedFormattedTimeLine ?? confirmedFormattedTimeLine,
                locationLine: showLocation && pendingLocationDiffersFromConfirmed
                    ? pendingRequestedLocationLine
                    : nil,
                style: .requested
            )
        }
    }

    private func pendingScheduleSnapshotSection(
        title: String,
        dateLine: String,
        timeLine: String,
        locationLine: String?,
        style: PendingScheduleSnapshotStyle
    ) -> some View {
        let isRequested = style == .requested

        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(InteraFont.caption.weight(.semibold))
                .foregroundStyleOliveGreen()

            scheduleSnapshotField(label: "Date", value: dateLine, emphasized: isRequested)
            scheduleSnapshotField(label: "Time", value: timeLine, emphasized: isRequested)

            if let locationLine {
                scheduleSnapshotField(label: "Location", value: locationLine, emphasized: isRequested)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isRequested ? Color.oliveGreen.opacity(0.16) : Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isRequested ? Color.oliveGreen.opacity(0.55) : BookingSelectorTheme.cream.opacity(0.22),
                            lineWidth: isRequested ? 1.5 : 1
                        )
                }
        }
    }

    private func scheduleSnapshotField(label: String, value: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .bookingDetailFieldTitleStyle()
            Text(value)
                .font(InteraFont.body.weight(emphasized ? .semibold : .medium))
                .foregroundStyle(BookingSelectorTheme.cream.opacity(emphasized ? 1 : 0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                label: "Location",
                value: "—",
                isEditingChrome: false
            )
        }
    }

    /// Compact centered service menu under the provider name (no "SERVICE" label).
    // Service editing disabled during Request Change.
    /*
    private var serviceEditHeroRow: some View {
        Group {
            if isLoadingEditPickerOptions {
                ProgressView()
                    .tint(BookingSelectorTheme.cream)
                    .padding(.vertical, 8)
            } else {
                Picker(selection: $draftServiceName) {
                    ForEach(alternativeServiceNames, id: \.self) { name in
                        Text(ConsumerBookingSimpleRow.displayableServiceLabel(name))
                            .font(Self.heroServiceDisplayFont)
                            .tag(name)
                    }
                } label: {
                    HStack(alignment: .center, spacing: 6) {
                        Spacer(minLength: 0)
                        Text(displayableDraftServiceName)
                            .font(Self.heroServiceDisplayFont)
                            .foregroundStyle(Self.requestChangeEditableAccentColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(InteraFont.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.interaShellForegroundSecondary)
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
                .stroke(Self.requestChangeEditableAccentColor, lineWidth: 1.5)
        }
        .frame(maxWidth: .infinity)
    }
    */

    private var notesFieldPlaceholder: String {
        "Add a note for your \(bookingRow.providerKindTag)"
    }

    private var requestChangeInstructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You can edit your appointment date and time, and add an optional note for your \(bookingRow.providerKindTag).")
                .font(InteraFont.caption)
                .foregroundStyle(BookingSelectorTheme.cream.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                requestChangeInstructionLine("Tap 'Date' or 'Time' to edit either field")
            }

            Text("When you submit, your changes are sent to your \(bookingRow.providerKindTag) as a request. They must approve before your booking updates.")
                .font(InteraFont.caption)
                .foregroundStyle(BookingSelectorTheme.cream.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture {
            if isRequestChangeEditing {
                dismissRequestChangeNotesKeyboard()
            }
        }
    }

    private func requestChangeInstructionLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(InteraFont.caption.weight(.semibold))
                .foregroundStyle(BookingSelectorTheme.cream.opacity(0.72))
            Text(text)
                .font(InteraFont.caption)
                .foregroundStyle(BookingSelectorTheme.cream.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // private static let serviceEditHeroMaxWidth: CGFloat = 280

    private func notesEditRow(isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes (Optional)")
                .bookingDetailFieldTitleStyle()
            TextField(notesFieldPlaceholder, text: $draftNotes, axis: .vertical)
                .lineLimit(2 ... 4)
                .font(InteraFont.body.weight(.medium))
                .foregroundStyle(BookingSelectorTheme.cream)
                .textFieldStyle(.plain)
                .focused($isRequestChangeNotesFocused)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.clear)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BookingSelectorTheme.cream, lineWidth: 1)
        }
        .onTapGesture {
            isRequestChangeNotesFocused = true
        }
        .padding(.bottom, isLast ? 0 : 0)
    }

    private func dismissRequestChangeNotesKeyboard() {
        isRequestChangeNotesFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    /// Menu-style picker for provider preset locations (only shown when at least one exists).
    private func locationPickerEditRow(isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location")
                .bookingDetailFieldTitleStyle()
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
                            .font(InteraFont.body.weight(.medium))
                            .foregroundStyle(BookingSelectorTheme.cream)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(InteraFont.system(size: 11, weight: .bold))
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
        .simultaneousGesture(
            TapGesture().onEnded {
                dismissRequestChangeNotesKeyboard()
            }
        )
    }

    private static let requestChangeEditableAccentColor = Color.oliveGreen
    #if canImport(UIKit)
    private static let editableScheduleFieldValueUIFont = InteraFont.uiFont(size: 17, weight: .medium)
    private static let editableScheduleTextFillUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : .black
    }
    private static let editableScheduleTextStrokeUIColor = UIColor(Color.oliveGreen)
    /// Negative width applies olive stroke around the filled body-medium label text.
    private static let editableScheduleTextOutlineWidth: CGFloat = -2.5
    #endif

    private func dateEditTimelineRow() -> some View {
        editableScheduleFieldButton(
            label: "Date",
            value: formattedDraftDateLine,
            accessibilityHint: "Opens date picker to change your appointment date."
        ) {
            dismissRequestChangeNotesKeyboard()
            scheduleEditEntry = .date
            showScheduleEditSheet = true
        }
    }

    private func timeEditTimelineRow() -> some View {
        editableScheduleFieldButton(
            label: "Time",
            value: formattedDraftTimeLine,
            accessibilityHint: "Opens time picker to change your appointment time."
        ) {
            dismissRequestChangeNotesKeyboard()
            scheduleEditEntry = .time
            showScheduleEditSheet = true
        }
    }

    private func editableScheduleFieldButton(
        label: String,
        value: String,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .bookingDetailFieldTitleStyle()
                #if canImport(UIKit)
                OutlinedScheduleLabelText(
                    text: value,
                    font: Self.editableScheduleFieldValueUIFont,
                    fillColor: Self.editableScheduleTextFillUIColor,
                    strokeColor: Self.editableScheduleTextStrokeUIColor,
                    strokeWidth: Self.editableScheduleTextOutlineWidth
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(value)
                #else
                Text(value)
                    .font(InteraFont.body.weight(.medium))
                    .foregroundStyle(BookingSelectorTheme.cream)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            }
            .editableScheduleFieldChrome()
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
    }

    private var formattedDraftDateLine: String {
        Self.dateOnlyDF.string(from: draftScheduledAt)
    }

    private var formattedDraftTimeLine: String {
        BookingPacificSchedule.displayTimeWithMinutes(from: draftScheduledAt)
    }

    private func locationTimelineRow(isLast: Bool, locationText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location")
                .bookingDetailFieldTitleStyle()
            Text(locationText)
                .font(InteraFont.body.weight(.medium))
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
                .bookingDetailFieldTitleStyle()
            Text(value)
                .font(InteraFont.body.weight(.medium))
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

    // MARK: - Supplementary (notes)

    private var bookingReferenceFooter: some View {
        VStack(spacing: 6) {
            Text("Booking Reference")
                .bookingDetailFieldTitleStyle()
            Text(bookingRow.displayBookingReference)
                .font(InteraFont.subheadline.weight(.medium).monospaced())
                .foregroundStyle(BookingSelectorTheme.cream.opacity(0.82))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Booking reference, \(bookingRow.displayBookingReference)")
    }

    private var supplementaryDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let n = bookingRow.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .bookingDetailFieldTitleStyle()
                    Text(n)
                        .font(InteraFont.body)
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
        BookingPacificSchedule.displayTimeWithMinutes(from: scheduledAtForDisplay)
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
        // draftServiceName = effectiveServiceName
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
        requestChangeBaselinesReady = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            isEditing = true
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
    }

    private func cancelEditing() {
        dismissRequestChangeNotesKeyboard()
        requestChangeBaselinesReady = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            isEditing = false
            isConfirmingCancelBooking = false
        }
    }

    private func captureRequestChangeBaselines() {
        requestChangeBaselineScheduledAt = draftScheduledAt
        // requestChangeBaselineServiceName = draftServiceName
        requestChangeBaselineLocation = draftLocation
        requestChangeBaselineNotes = draftNotes
        requestChangeBaselinesReady = true
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

        guard hasRequestChangeDraftChanges else {
            AlertManager.shared.presentErrorToast("Change the date, time, location, or notes before submitting.")
            return
        }

        let scheduleDraftChanged = hasScheduleDraftChangesFromRequestBaseline
        // let serviceDraftChanged = hasServiceDraftChangeFromRequestBaseline

        let iso = BookingPacificSchedule.scheduledTimeStringForAPI(from: draftScheduledAt)
        let locRaw = draftLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let locForAPI: String? = {
            if locRaw.isEmpty || Self.isCoordinateLocationPlaceholder(locRaw) { return nil }
            return locRaw
        }()
        let notesForAPI = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        // let svcRaw = draftServiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        // let svcForAPI = svcRaw.isEmpty ? bookingRow.displayServiceName : svcRaw

        do {
            if scheduleDraftChanged {
                _ = try await ConsumerBookingsSimpleAPI.submitRescheduleRequest(
                    bookingId: bookingRow.id,
                    scheduledTimeISO: iso,
                    location: locForAPI,
                    notes: notesForAPI,
                    bearerToken: token
                )
            }
            // Service metadata updates disabled during Request Change.
            // if serviceDraftChanged {
            //     try await ConsumerBookingsSimpleAPI.updateConsumerBookingMetadata(
            //         bookingId: bookingRow.id,
            //         location: scheduleDraftChanged ? nil : locForAPI,
            //         serviceName: svcForAPI,
            //         bearerToken: token
            //     )
            // }
            // if serviceDraftChanged {
            //     localServiceName = draftServiceName
            // }
            await performBookingDetailRefresh()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isEditing = false
            }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            AlertManager.shared.present(
                scheduleDraftChanged
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

        // Service picker options disabled during Request Change.
        // func mergeServiceNames(_ apiNames: [String]) -> [String] {
        //     let trimmed = apiNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        //     var merged = trimmed.isEmpty ? [effectiveServiceName] : trimmed
        //     if !merged.contains(where: { $0.caseInsensitiveCompare(draftServiceName) == .orderedSame }) {
        //         merged.insert(draftServiceName, at: 0)
        //     }
        //     return merged
        // }

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
            // alternativeServiceNames = mergeServiceNames([])
            alternativeLocationNames = mergeLocationNames([])
            return
        }

        do {
            let provider = try await CampusCutsBarberDetailAPI.fetchServiceProvider(
                barberId: bid,
                bearerToken: sessionManager.currentSession?.token
            )
            // let serviceNames = (provider.services ?? []).map(\.name)
            // alternativeServiceNames = mergeServiceNames(serviceNames)
            let locs = provider.locations ?? []
            alternativeLocationNames = mergeLocationNames(locs)
            if normalizedRequestChangeDraft(draftLocation).isEmpty,
               let firstLocation = alternativeLocationNames.first {
                draftLocation = firstLocation
            }
        } catch {
            // alternativeServiceNames = mergeServiceNames([])
            alternativeLocationNames = mergeLocationNames([])
        }
    }

    // MARK: - Schedule edit availability (provider-published slots)

    @MainActor
    private func loadScheduleEditOpenDays(forMonth month: Date) async {
        let monthKey = BookingPacificSchedule.monthCacheKey(for: month)
        guard !monthKey.isEmpty, scheduleEditOpenDaysByMonthKey[monthKey] == nil else { return }

        scheduleEditLoadingOpenDaysMonthKeys.insert(monthKey)
        defer { scheduleEditLoadingOpenDaysMonthKeys.remove(monthKey) }

        let barberId = bookingRow.barberId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !barberId.isEmpty else {
            scheduleEditOpenDaysByMonthKey[monthKey] = []
            return
        }

        let days = BookingPacificSchedule.dayStartsInMonth(containing: month, clippedTo: scheduleEditRange)
        let open = await BookingOpenDaysLoader.loadOpenDayStarts(
            days: days,
            barberId: barberId,
            campusCutsBarberIntId: Int(barberId),
            bearerToken: sessionManager.currentSession?.token,
            campusCutsClient: campusCutsClient
        )
        scheduleEditOpenDaysByMonthKey[monthKey] = open
    }

    @MainActor
    private func loadScheduleEditDaySlots() async {
        scheduleEditSlotsLoading = true
        scheduleEditSlotsError = nil
        defer { scheduleEditSlotsLoading = false }

        let pacificDay = BookingPacificSchedule.pacificStartOfDay(for: draftScheduledAt)
        var slots = await fetchRibbonSlotsForEditDay(pacificDay)
        let currentKey = BookingPacificSchedule.pacificHHmmKey(from: draftScheduledAt)

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
        scheduleEditAvailableTimeKeys = Set(scheduleEditSlotRows.map(\.timeKey))
        if !currentKey.isEmpty {
            scheduleEditAvailableTimeKeys.insert(currentKey)
        }

        if scheduleEditSlotRows.isEmpty && currentKey.isEmpty {
            scheduleEditSlotsError = "No open times for this day."
        } else {
            scheduleEditSlotsError = nil
        }
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
        return BookingPacificSchedule.displayTimeWithMinutes(from: instant)
    }

    private func dedupeEditRibbonSlots(_ rows: [BookingRibbonSlot]) -> [BookingRibbonSlot] {
        var seen = Set<String>()
        let sorted = rows.sorted { $0.timeKey < $1.timeKey }
        return sorted.filter { seen.insert($0.timeKey).inserted }
    }

    // MARK: - Edit chrome (toolbar + CTA + schedule sheet)

    private var scheduleEditCalendarBlock: some View {
        BookingCalendarGridSelector(
            selectedDate: $draftScheduledAt,
            selectionCommitted: $draftCalendarCommitted,
            range: scheduleEditRange,
            allowedDayStarts: scheduleEditAllowedDayStarts,
            onDaySelected: {
                Task { await loadScheduleEditDaySlots() }
            },
            onDisplayedMonthChange: { month in
                scheduleEditDisplayedMonth = month
                Task { await loadScheduleEditOpenDays(forMonth: month) }
            }
        )
    }

    private var scheduleEditTimeSlotBlock: some View {
        let preservedKey = BookingPacificSchedule.pacificHHmmKey(from: draftScheduledAt)
        return BookingMinuteTimePicker(
            calendarDay: draftScheduledAt,
            availableTimeKeys: scheduleEditAvailableTimeKeys,
            selectedTime: $draftScheduledAt,
            isLoading: scheduleEditSlotsLoading,
            loadError: scheduleEditSlotsError,
            emptyMessage: scheduleEditSlotsError ?? "No open times for this day.",
            snapUnavailableToNearestOpen: false,
            alwaysAllowedTimeKeys: preservedKey.isEmpty ? [] : [preservedKey]
        )
    }

    private var confirmChangesInset: some View {
        VStack(spacing: 0) {
            if isConfirmingCancelBooking {
                Text("Your \(bookingRow.providerKindTag) will be notified. This can’t be undone.")
                    .font(InteraFont.caption)
                    .foregroundStyle(BookingSelectorTheme.cream.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                cancelBookingConfirmationButtons
            } else {
                requestChangeActionButtons
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isConfirmingCancelBooking)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isEditing)
    }

    private var requestChangeActionButtons: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                dismissRequestChangeNotesKeyboard()
                confirmEdits()
            } label: {
                HStack(spacing: 10) {
                    if isConfirmingEdits {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BookingSelectorTheme.deepCharcoal)
                    }
                    Text(submitRequestButtonTitle)
                        .font(Self.editBottomBarButtonFont)
                        .foregroundStyle(BookingSelectorTheme.deepCharcoal)
                }
                .contentTransition(.interpolate)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(BookingSelectorTheme.cream)
                }
            }
            .buttonStyle(BookButtonStyle())
            .disabled(isConfirmingEdits || isCancellingBooking || !hasRequestChangeDraftChanges)
            .opacity((isConfirmingEdits || isCancellingBooking || !hasRequestChangeDraftChanges) ? 0.55 : 1)
            .allowsHitTesting(hasRequestChangeDraftChanges && !isConfirmingEdits && !isCancellingBooking)
            .frame(maxWidth: .infinity)

            Button {
                dismissRequestChangeNotesKeyboard()
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    isConfirmingCancelBooking = true
                }
            } label: {
                Text("Cancel Booking")
                    .font(Self.editBottomBarButtonFont)
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.center)
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
    }

    private var cancelBookingConfirmationButtons: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                dismissRequestChangeNotesKeyboard()
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    isConfirmingCancelBooking = false
                }
            } label: {
                Text("Keep Booking")
                    .font(Self.editBottomBarButtonFont)
                    .foregroundStyle(BookingSelectorTheme.cream)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(BookingSelectorTheme.cream.opacity(0.55), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isCancellingBooking)
            .frame(maxWidth: .infinity)

            Button {
                dismissRequestChangeNotesKeyboard()
                Task { await performCancelBooking() }
            } label: {
                HStack(spacing: 8) {
                    if isCancellingBooking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text("Confirm Cancel")
                        .font(Self.editBottomBarButtonFont)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red)
                }
            }
            .buttonStyle(BookButtonStyle())
            .disabled(isCancellingBooking)
            .opacity(isCancellingBooking ? 0.75 : 1)
            .accessibilityLabel("Confirm cancel booking")
            .frame(maxWidth: .infinity)
        }
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
                if scheduleEditEntry == .time {
                    await loadScheduleEditDaySlots()
                } else {
                    await loadScheduleEditOpenDays(forMonth: scheduleEditDisplayedMonth)
                }
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
                    .font(InteraFont.body.weight(.semibold))
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

    private func bookingDetailToolbarIcon(systemName: String, accessibilityLabel: String) -> some View {
        Image(systemName: systemName)
            .font(InteraFont.system(size: 17, weight: .semibold))
            .foregroundStyle(BookingSelectorTheme.cream)
            .accessibilityLabel(accessibilityLabel)
    }

    private func bookingDetailCircularIconButton(
        systemName: String,
        accessibilityLabel: String,
        showsProgress: Bool = false
    ) -> some View {
        ZStack {
            Circle()
                .fill(Color.oliveGreen)
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: systemName)
                    .font(InteraFont.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: Self.bookingDetailCircularActionButtonSize, height: Self.bookingDetailCircularActionButtonSize)
        .shadow(color: Color.oliveGreen.opacity(0.28), radius: 7, y: 2)
        .accessibilityLabel(accessibilityLabel)
    }
}

#if canImport(UIKit)
/// Body-medium schedule value with an olive-green glyph outline and adaptive fill (matches read-only booking details).
private struct OutlinedScheduleLabelText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let fillColor: UIColor
    let strokeColor: UIColor
    let strokeWidth: CGFloat

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.backgroundColor = .clear
        label.isUserInteractionEnabled = false
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fillColor,
            .strokeColor: strokeColor,
            .strokeWidth: strokeWidth,
        ]
        label.attributedText = NSAttributedString(string: text, attributes: attributes)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        uiView.preferredMaxLayoutWidth = width
        return uiView.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
    }
}
#endif

private struct EditableScheduleFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.clear)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.oliveGreen, lineWidth: 1.5)
            }
    }
}

private extension View {
    func editableScheduleFieldChrome() -> some View {
        modifier(EditableScheduleFieldChrome())
    }

    func bookingDetailRequestChangeKeyboardHandling(
        isEditing: Bool,
        showScheduleEditSheet: Binding<Bool>,
        dismissNotesKeyboard: @escaping () -> Void
    ) -> some View {
        self
            .onChange(of: showScheduleEditSheet.wrappedValue) { _, isPresented in
                if isPresented {
                    dismissNotesKeyboard()
                }
            }
            .onChange(of: isEditing) { _, editing in
                if !editing {
                    dismissNotesKeyboard()
                }
            }
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
