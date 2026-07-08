//
//  ConsumerBookingsHubView.swift
//  OnCuts
//
//  Consumer bookings from `GET /api/v1/bookings-simple` — unified timeline continuum
//  (Upcoming / Today / Past) instead of segmented tabs.
//

import SwiftUI

struct ConsumerBookingsHubView: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator
    var onShowLogin: () -> Void = {}
    /// Reports `detailNavigationPath.count` for hub paging sync after pop; the hub bar stays visible over Bookings pushes so payment **Pay later** does not strand the user without hub navigation.
    var onNavigationDepthChange: ((Int) -> Void)? = nil

    @EnvironmentObject private var chatViewModel: ChatViewModel

    @State private var detailNavigationPath = NavigationPath()
    @State private var rows: [ConsumerBookingSimpleRow] = []
    @State private var isLoading = false
    @State private var error: String?
    /// Incremented after each successful fetch so `UnifiedTimelineView` can re-scroll to the anchor.
    @State private var timelineScrollEpoch = 0
    /// After a new booking request, scroll to the **Upcoming** header (see `OnCutsBookingsUserInfoKeys.focusUpcomingSection`).
    @State private var scrollAnchorOverride: String?
    /// `GET /bookings-simple` can briefly omit a booking that we already have from `GET …/:id` (notification deep link). Keep a copy so `hubRow` still resolves while detail is on-stack.
    @State private var supplementalDetailRowsByNormalizedId: [String: ConsumerBookingSimpleRow] = [:]
    /// Cancels superseded follow-up depth reports so rapid reminder → detail → back cannot apply a stale count.
    @State private var navigationDepthFollowUpTask: Task<Void, Never>?
    private var projection: ConsumerBookingsTimelineProjection {
        ConsumerBookingsTimelineProjection.build(from: rows)
    }

    private var hasAnyBooking: Bool {
        !rows.isEmpty
    }

    private var hasActiveConsumerBooking: Bool {
        rows.contains { row in
            let u = row.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard u == "PENDING" || u == "ACCEPTED" else { return false }
            return row.scheduleSegment() != .past
        }
    }

    /// Split from `body` so the compiler can type-check the navigation stack in reasonable time.
    @ViewBuilder
    private var hubTimelineRoot: some View {
        ZStack {
            #if os(iOS)
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            OnCutsLiquidMeshBackground()
            #endif
            Group {
                if !sessionManager.isAuthenticated {
                    ContentUnavailableView(
                        "Sign in required",
                        systemImage: "calendar.badge.clock",
                        description: Text("Sign in to see your appointments.")
                    )
                } else                 if isLoading && rows.isEmpty {
                    ScrollView {
                        VStack {
                            Spacer(minLength: 120)
                            ProgressView()
                                .tint(Color.oliveGreen)
                            Spacer(minLength: 120)
                        }
                        .frame(maxWidth: .infinity)
                        .onCutsHubBarScrollContentBottomInset()
                    }
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .onCutsHubBarScrollOffsetReporting(pageIndex: 2)
                    .refreshable { await reloadBookingsListForPullToRefresh() }
                } else if !hasAnyBooking {
                    ScrollView {
                        ContentUnavailableView(
                            "No bookings yet",
                            systemImage: "calendar",
                            description: Text("When you book a provider, your timeline appears here.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                        .onCutsHubBarScrollContentBottomInset()
                    }
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .onCutsHubBarScrollOffsetReporting(pageIndex: 2)
                    .refreshable { await reloadBookingsListForPullToRefresh() }
                } else {
                    UnifiedTimelineView(
                        projection: projection,
                        sessionManager: sessionManager,
                        coordinator: coordinator,
                        scrollEpoch: timelineScrollEpoch,
                        scheduleLine: formattedSchedule,
                        hasActiveConsumerBooking: hasActiveConsumerBooking,
                        onShowLogin: onShowLogin,
                        onOpenBookingDetail: { row in
                            openBookingDetailFromTimeline(row)
                        },
                        onRemovePastBooking: { row in
                            Task { await removePastBookingFromList(row) }
                        },
                        scrollAnchorOverride: $scrollAnchorOverride,
                        onPullToRefresh: { await reloadBookingsListForPullToRefresh() }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func hubBookingDetailDestination(_ row: ConsumerBookingSimpleRow, presentationID: UUID? = nil) -> some View {
        ConsumerBookingDetailView(
            row: row,
            sessionManager: sessionManager,
            coordinator: coordinator,
            bookingDetailPresentationID: presentationID,
            hasActiveConsumerBooking: hasActiveConsumerBooking,
            onShowLogin: onShowLogin
        )
        #if os(iOS)
        .onCutsNavigationShellBackgroundClear()
        #endif
    }

    private static func normalizedBookingIdKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func rememberSupplementalDetailRow(_ row: ConsumerBookingSimpleRow) {
        let k = Self.normalizedBookingIdKey(row.id)
        guard !k.isEmpty else { return }
        supplementalDetailRowsByNormalizedId[k] = row
    }

    private func hubRow(bookingId: String) -> ConsumerBookingSimpleRow? {
        let key = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let r = rows.first(where: { $0.id.caseInsensitiveCompare(key) == .orderedSame }) {
            return r
        }
        return supplementalDetailRowsByNormalizedId[Self.normalizedBookingIdKey(key)]
    }

    @ViewBuilder
    private func hubBookingStackRouteDestination(_ route: ConsumerHomeBookingStackRoute) -> some View {
        switch route {
        case .detail(let bookingId, let presentationID):
            if let row = hubRow(bookingId: bookingId) {
                hubBookingDetailDestination(row, presentationID: presentationID)
                    .id(presentationID)
                    .onAppear { rememberSupplementalDetailRow(row) }
            } else {
                ContentUnavailableView(
                    "Booking unavailable",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Return to the list and try again after refresh.")
                )
            }
        case .messagingThread:
            EmptyView()
        }
    }

    private func reportBookingsNavigationDepth() {
        let notify = onNavigationDepthChange
        notify?(detailNavigationPath.count)
        // Re-read after a yield so SwiftUI has committed `NavigationPath` — must NOT capture the count in an async
        // closure or repeat reminder→detail cycles can deliver stale values and leave the hub tab bar hidden.
        navigationDepthFollowUpTask?.cancel()
        navigationDepthFollowUpTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            notify?(detailNavigationPath.count)
        }
    }

    var body: some View {
        NavigationStack(path: $detailNavigationPath) {
            hubTimelineRoot
                .navigationDestination(for: ConsumerHomeBookingStackRoute.self) { route in
                    hubBookingStackRouteDestination(route)
                }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(Color.oliveGreen)
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .task {
            await reloadBookingsList()
        }
        .onReceive(NotificationCenter.default.publisher(for: .onCutsNavigateToBookingsAfterBookingRequest)) { notification in
            if (notification.userInfo?[OnCutsBookingsUserInfoKeys.focusUpcomingSection] as? Bool) == true {
                scrollAnchorOverride = ConsumerBookingsTimelineProjection.upcomingHeaderID
            }
            scheduleReloadBookingsList()
        }
        .onReceive(NotificationCenter.default.publisher(for: .consumerBookingsListShouldRefresh)) { _ in
            scheduleReloadBookingsList()
        }
        .onReceive(NotificationCenter.default.publisher(for: .onCutsNavigateToConsumerHomeAfterPayment)) { _ in
            detailNavigationPath = NavigationPath()
            reportBookingsNavigationDepth()
        }
        .onReceive(NotificationCenter.default.publisher(for: .consumerBookingsHubShouldPopToRoot)) { _ in
            detailNavigationPath = NavigationPath()
            chatViewModel.pendingOpenBookingDetailId = nil
            reportBookingsNavigationDepth()
        }
        /// `onChange` misses the first assignment when this tab wasn’t mounted yet; `task(id:)` runs when the
        /// pending id appears after switching to the Bookings tab (same as notification deep links).
        .task(id: chatViewModel.pendingOpenBookingDetailId) {
            guard let raw = chatViewModel.pendingOpenBookingDetailId,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let bid = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            await openBookingDetailFromPendingPush(bookingId: bid)
        }
        .alert("Couldn’t load bookings", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .onAppear {
            reportBookingsNavigationDepth()
        }
        .onChange(of: detailNavigationPath.count) { _, count in
            if count == 0 {
                supplementalDetailRowsByNormalizedId.removeAll()
            }
            reportBookingsNavigationDepth()
        }
        .onDisappear {
            navigationDepthFollowUpTask?.cancel()
            navigationDepthFollowUpTask = nil
        }
    }

    @MainActor
    private func removePastBookingFromList(_ row: ConsumerBookingSimpleRow) async {
        guard sessionManager.isAuthenticated else { return }
        guard row.scheduleSegment() == .past else { return }
        error = nil
        do {
            _ = try await ConsumerBookingsSimpleAPI.hidePastBookingFromConsumerList(
                bookingId: row.id,
                bearerToken: sessionManager.currentSession?.token
            )
            // Always record locally so ``mergeSupplementalDetailRowsIntoListIfMissing`` cannot resurrect a stale
            // snapshot (e.g. still **PENDING** from before cancel) after `GET` omits the hidden booking.
            if let uid = sessionManager.currentSession?.userId {
                ConsumerHiddenBookingsStore.recordHidden(bookingId: row.id, consumerUserId: uid)
            }
            supplementalDetailRowsByNormalizedId[Self.normalizedBookingIdKey(row.id)] = nil
            rows.removeAll { $0.id == row.id }
            timelineScrollEpoch += 1
            NotificationCenter.default.post(name: .consumerBookingsListShouldRefresh, object: nil)
        } catch {
            if ConsumerBookingsSimpleAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
            } else if !OnCutsRefreshCancellation.isBenignCancellation(error) {
                self.error = error.localizedDescription
            }
        }
    }

    /// After a list refresh, re-attach any booking row we’re still showing in `NavigationStack` if the API list omitted it (race with push-notification `fetchConsumerBookingById`).
    private func mergeSupplementalDetailRowsIntoListIfMissing() {
        guard !supplementalDetailRowsByNormalizedId.isEmpty else { return }
        let uid = sessionManager.currentSession?.userId
        for (_, row) in supplementalDetailRowsByNormalizedId {
            if ConsumerHiddenBookingsStore.isBookingHidden(bookingId: row.id, consumerUserId: uid) {
                continue
            }
            if rows.first(where: { $0.id.caseInsensitiveCompare(row.id) == .orderedSame }) == nil {
                rows.append(row)
            }
        }
    }

    /// Single implementation shared by the toolbar, notifications, and `.task`. Performs `GET /bookings-simple?role=consumer`.
    @MainActor
    private func reloadBookingsList() async {
        guard sessionManager.isAuthenticated else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            rows = try await ConsumerBookingsSimpleAPI.fetchConsumerBookings(
                bearerToken: sessionManager.currentSession?.token,
                consumerUserId: sessionManager.currentSession?.userId
            )
            mergeSupplementalDetailRowsIntoListIfMissing()
            chatViewModel.syncPaymentTakeover(withBookings: rows)
            timelineScrollEpoch += 1
        } catch {
            if ConsumerBookingsSimpleAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
            } else if !OnCutsRefreshCancellation.isBenignCancellation(error) {
                self.error = error.localizedDescription
            }
        }
    }

    /// Pull-to-refresh must not call ``reloadBookingsList()`` directly inside `.refreshable`: SwiftUI can cancel
    /// that structured task during scroll updates before `URLSession` issues the request, so the backend never
    /// logs `GET /bookings-simple`. The toolbar uses unstructured `Task { await reloadBookingsList() }` and
    /// avoids that cancellation path. This runs the same fetch on the main actor inside `Task.detached` so the
    /// network call reliably runs while still awaiting completion for the refresh control.
    @MainActor
    private func reloadBookingsListForPullToRefresh() async {
        await OnCutsPullToRefresh.runMainActorAsyncIsolatedFromRefreshableCancellation {
            await reloadBookingsList()
        }
    }

    /// Same async work as the toolbar; `Button` cannot be `async` so it schedules an unstructured `Task`.
    private func scheduleReloadBookingsList() {
        Task { await reloadBookingsList() }
    }

    private static let displayDateDF: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private func formattedSchedule(_ row: ConsumerBookingSimpleRow) -> String {
        guard let d = row.scheduledAtDate else { return "—" }
        let datePart = Self.displayDateDF.string(from: d)
        let timePart = BookingPacificSchedule.displayTimeWithMinutes(from: d)
        return "\(datePart), \(timePart)"
    }

    /// Push notification asked for a specific booking — prefer a fresh `GET /bookings-simple/:id` row so status
    /// matches the server (list can still show **PENDING** briefly after “Booking Confirmed” / accept).
    @MainActor
    private func openBookingDetailFromTimeline(_ row: ConsumerBookingSimpleRow) {
        rememberSupplementalDetailRow(row)
        detailNavigationPath.append(ConsumerHomeBookingStackRoute.bookingsTabDetailPush(for: row))
        reportBookingsNavigationDepth()
    }

    @MainActor
    private func openBookingDetailFromPendingPush(bookingId: String) async {
        let bid = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bid.isEmpty else {
            chatViewModel.pendingOpenBookingDetailId = nil
            return
        }
        guard sessionManager.isAuthenticated else {
            chatViewModel.pendingOpenBookingDetailId = nil
            return
        }
        do {
            let fresh = try await ConsumerBookingsSimpleAPI.fetchConsumerBookingById(
                bookingId: bid,
                bearerToken: sessionManager.currentSession?.token
            )
            chatViewModel.pendingOpenBookingDetailId = nil
            rememberSupplementalDetailRow(fresh)
            if let idx = rows.firstIndex(where: { $0.id.caseInsensitiveCompare(fresh.id) == .orderedSame }) {
                rows[idx] = fresh
            } else {
                rows.append(fresh)
            }
            timelineScrollEpoch += 1
            detailNavigationPath.append(ConsumerHomeBookingStackRoute.bookingsTabDetailPush(for: fresh))
            // Reload after the stack commits; an immediate `await` here can rebuild `hubTimelineRoot` and
            // confuse `NavigationPath` / depth reporting so the unified hub bar never un-hides after back.
            Task { await reloadBookingsList() }
            return
        } catch {
            if ConsumerBookingsSimpleAPI.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
                chatViewModel.pendingOpenBookingDetailId = nil
                return
            }
        }
        if rows.isEmpty || rows.first(where: { $0.id.caseInsensitiveCompare(bid) == .orderedSame }) == nil {
            await reloadBookingsList()
        }
        guard let row = rows.first(where: { $0.id.caseInsensitiveCompare(bid) == .orderedSame }) else {
            chatViewModel.pendingOpenBookingDetailId = nil
            return
        }
        chatViewModel.pendingOpenBookingDetailId = nil
        rememberSupplementalDetailRow(row)
        detailNavigationPath.append(ConsumerHomeBookingStackRoute.bookingsTabDetailPush(for: row))
    }
}

#if DEBUG
#Preview {
    ConsumerBookingsHubView(sessionManager: AppSessionManager(), coordinator: MainCoordinator(sessionManager: AppSessionManager()))
        .environmentObject(ChatViewModel())
}
#endif
