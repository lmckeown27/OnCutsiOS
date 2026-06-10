//
//  ProfileBlockedMessagingUsersView.swift
//  Intera
//
//  Lists messaging blocks from `GET /messages/blocks` and supports `POST /messages/unblock`.
//

import SwiftUI

struct ProfileBlockedMessagingUsersView: View {
    let sessionManager: AppSessionManager

    @State private var blocked: [MessagingBlockedUserProfile] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var unblockTarget: MessagingBlockedUserProfile?
    @State private var unblockingUserId: String?
    @State private var unblockError: String?

    var body: some View {
        Group {
            if isLoading, blocked.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError, blocked.isEmpty {
                ContentUnavailableView(
                    "Couldn’t load list",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if blocked.isEmpty {
                ContentUnavailableView(
                    "No blocked people",
                    systemImage: "person.crop.circle.badge.checkmark",
                    description: Text("Accounts you block in messaging appear here. You can unblock them anytime.")
                )
            } else {
                List {
                    ForEach(blocked) { user in
                        HStack(alignment: .center, spacing: 14) {
                            AvatarView(
                                imageUrl: user.avatarUrl,
                                name: user.displayName,
                                size: 56,
                                fontSize: 22,
                                clipStyle: .square(cornerRadius: 12)
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if unblockingUserId == user.id {
                                ProgressView()
                                    .tint(Color.oliveGreen)
                            } else {
                                Button {
                                    unblockTarget = user
                                } label: {
                                    Text("Unblock")
                                        .font(.body.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .tint(Color.red)
                                .foregroundStyle(Color.red)
                                .disabled(unblockingUserId != nil)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationTitle("Blocked people")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(Color.oliveGreen)
        .task {
            await loadBlockedUsers()
        }
        .refreshable {
            await loadBlockedUsers()
        }
        .alert(
            "Unblock this person?",
            isPresented: Binding(
                get: { unblockTarget != nil },
                set: { if !$0 { unblockTarget = nil } }
            ),
            presenting: unblockTarget
        ) { user in
            Button("Cancel", role: .cancel) {
                unblockTarget = nil
            }
            Button("Unblock", role: .destructive) {
                let u = user
                unblockTarget = nil
                Task { await unblock(u) }
            }
        } message: { user in
            Text("\(user.displayName) will be able to send you messages again.")
        }
        .alert("Couldn’t unblock", isPresented: Binding(
            get: { unblockError != nil },
            set: { if !$0 { unblockError = nil } }
        )) {
            Button("OK", role: .cancel) { unblockError = nil }
        } message: {
            if let unblockError {
                Text(unblockError)
            }
        }
    }

    @MainActor
    private func loadBlockedUsers() async {
        guard sessionManager.isAuthenticated else {
            blocked = []
            loadError = "Sign in to manage blocked people."
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let rows = try await MessagingAPIService.fetchBlockedMessagingUsers(bearerToken: sessionManager.currentSession?.token)
            blocked = rows
            MessagingCommunitySafety.replaceLocallyBlockedUserIdsFromServer(rows.map(\.id))
        } catch {
            if MessagingAPIService.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
                loadError = "Your session expired. Sign in again."
            } else {
                loadError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func unblock(_ user: MessagingBlockedUserProfile) async {
        guard sessionManager.isAuthenticated else { return }
        unblockingUserId = user.id
        unblockError = nil
        defer { unblockingUserId = nil }
        do {
            try await MessagingAPIService.unblockMessagingUser(blockedUserId: user.id, bearerToken: sessionManager.currentSession?.token)
            let rows = try await MessagingAPIService.fetchBlockedMessagingUsers(bearerToken: sessionManager.currentSession?.token)
            MessagingCommunitySafety.replaceLocallyBlockedUserIdsFromServer(rows.map(\.id))
            NotificationCenter.default.post(name: .messagingBlockedUserDidChange, object: nil)
            blocked = rows
        } catch {
            if MessagingAPIService.isUnauthorizedHTTPError(error) {
                await sessionManager.recoverSessionAfterUnauthorized()
                unblockError = "Your session expired. Sign in again."
            } else {
                unblockError = error.localizedDescription
            }
        }
    }
}
