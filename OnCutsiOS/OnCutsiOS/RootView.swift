//
//  RootView.swift
//  Intera
//
//  Created by Liam McKeown on 3/8/26.
//

import SwiftUI
import OnCutsModule

/// The root orchestrator view that switches between login and main content
/// based on authentication state
struct RootView: View {
    let sessionManager: AppSessionManager
    let coordinator: MainCoordinator

    @StateObject private var chatViewModel = ChatViewModel()
    /// Lives on `RootView` so it is not recreated when `mainChrome` swaps the guest vs authenticated
    /// `UnifiedProviderHomeScreen` branch (which would reset `@StateObject` and tear down Apple legal-name UI).
    @StateObject private var appleOAuthPostSignInCoordinator = AppleOAuthPostSignInCoordinator()
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif
    
    var body: some View {
        Group {
            #if os(iOS)
            ZStack {
                InteraShellBackground()

                VStack(spacing: 0) {
                    if AppConfiguration.onCutsProductionLiveDataMode {
                        OnCutsLiveDataModeBanner()
                    }
                    mainChrome
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .environmentObject(chatViewModel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            }
            #else
            VStack(spacing: 0) {
                if AppConfiguration.onCutsProductionLiveDataMode {
                    OnCutsLiveDataModeBanner()
                }
                mainChrome
                    .environmentObject(chatViewModel)
            }
            #endif
        }
        .interaConsumerShellAppearance()
        .task {
            await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .interaOpenMessagingConversation)) { output in
            guard sessionManager.userRole == .student else { return }
            guard let cid = InteraPushNavigationPayload.conversationId(from: output.userInfo) else { return }
            chatViewModel.pendingPushConversationId = cid
        }
        .onChange(of: sessionManager.isAuthenticated) { wasAuthed, isAuthed in
            Task { await chatViewModel.refreshUnreadMessageCount(sessionManager: sessionManager) }
            #if os(iOS) || os(visionOS)
            // Only refresh push when transitioning to signed-in — not on arbitrary re-renders while typing.
            if isAuthed, wasAuthed == false {
                PushDeviceRegistration.refreshRemoteRegistrationAndRetryBackend(bearerToken: sessionManager.currentSession?.token)
            }
            #endif
        }
        #if os(iOS)
        /// Provider marked complete → `booking-completed` may be missed if Socket.IO connected late; refetch sets `activePaymentRequest` via `syncPaymentTakeover`.
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard sessionManager.isAuthenticated, sessionManager.userRole == .student else { return }
            if newPhase == .active, oldPhase != .active {
                Task { await chatViewModel.refreshConsumerBookingsAndSyncPayment(sessionManager: sessionManager) }
            }
        }
        #endif
        .fullScreenCover(item: $chatViewModel.activePaymentRequest) { payload in
            ConsumerPaymentTakeoverView(
                payload: payload,
                sessionManager: sessionManager
            )
            .environmentObject(chatViewModel)
        }
        #if os(iOS)
        .fullScreenCover(item: $chatViewModel.postPaymentReviewContext) { ctx in
            ConsumerPostPaymentReviewView(
                context: ctx,
                sessionManager: sessionManager
            )
            .environmentObject(chatViewModel)
        }
        #endif
        .onAppear {
            OnCutsSessionSync.appSessionManager = sessionManager
            IntegratedSignUpBootstrap.installDefaultFlowsIfNeeded()
        }
        .animation(nil, value: sessionManager.isAuthenticated)
        .animation(nil, value: coordinator.selectedService)
        .task {
            guard !sessionManager.isAuthenticated else { return }
            await GoogleSignInAppSupport.restorePreviousSignIn(sessionManager: sessionManager)
        }
    }

    @ViewBuilder
    private var mainChrome: some View {
        Group {
            // Keep consumer `UnifiedProviderHomeScreen` in a **single** branch for guest → student so SwiftUI
            // does not tear it down when `isAuthenticated` flips (which dismissed the OAuth sheet + legal cover).
            if sessionManager.isAuthenticated,
               sessionManager.userRole == .barber || sessionManager.userRole == .admin {
                MainTabView(
                    coordinator: coordinator,
                    sessionManager: sessionManager
                )
            } else {
                UnifiedProviderHomeScreen(
                    sessionManager: sessionManager,
                    coordinator: coordinator,
                    appleOAuthPostSignIn: appleOAuthPostSignInCoordinator
                )
            }
        }
    }
}

#Preview("Root View - Logged Out") {
    let sessionManager = AppSessionManager()
    let coordinator = MainCoordinator(sessionManager: sessionManager)
    
    return RootView(
        sessionManager: sessionManager,
        coordinator: coordinator
    )
}

#Preview("Root View - Logged In") {
    let sessionManager = AppSessionManager()
    sessionManager.mockLogin()
    
    let coordinator = MainCoordinator(sessionManager: sessionManager)
    
    return RootView(
        sessionManager: sessionManager,
        coordinator: coordinator
    )
}
