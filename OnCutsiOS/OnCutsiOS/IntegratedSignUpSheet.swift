//
//  IntegratedSignUpSheet.swift
//  Intera
//
//  Presents one or more registered package sign-up flows.
//

import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct IntegratedSignUpSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sessionManager: AppSessionManager
    let onFinished: () -> Void

    @State private var path: [String] = []

    var body: some View {
        let flows = IntegratedSignUpFlowRegistry.allFlows
        ZStack {
            // Single flow (`LiquidGlassSignupFlowView`) paints its own lava; avoid stacking two lamps.
            if flows.count != 1 {
                InteraShellBackground()
            }

            NavigationStack(path: $path) {
                Group {
                    if flows.isEmpty {
                        ContentUnavailableView(
                            "Sign-up unavailable",
                            systemImage: "person.crop.circle.badge.xmark",
                            description: Text("No sign-up flows are registered. Add packages in IntegratedSignUpBootstrap.")
                        )
                        .foregroundStyle(Color.lavaShellCream)
                        .tint(Color.lavaShellCream)
                    } else if flows.count == 1, let only = flows.first {
                        only.hostView(sessionManager: sessionManager) {
                            onFinished()
                            dismiss()
                        }
                    } else {
                        List(flows) { flow in
                            Button {
                                path.append(flow.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(flow.title)
                                        .font(InteraFont.headline)
                                        .foregroundStyle(Color.lavaShellCream)
                                    if let subtitle = flow.subtitle, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(InteraFont.caption)
                                            .foregroundStyle(Color.lavaShellCreamSecondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .navigationTitle("Sign up")
                    }
                }
                .toolbar {
                    if flows.isEmpty || flows.count > 1 {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                dismiss()
                            }
                            .tint(Color.lavaShellCream)
                        }
                    }
                }
                .navigationDestination(for: String.self) { flowId in
                    if let flow = IntegratedSignUpFlowRegistry.flow(id: flowId) {
                        flow.hostView(sessionManager: sessionManager) {
                            onFinished()
                            dismiss()
                        }
                    } else {
                        Text("Missing sign-up flow.")
                            .foregroundStyle(Color.lavaShellCream)
                    }
                }
            }
            #if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            .interaNavigationShellBackgroundClear()
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .presentationBackground(.clear)
        #endif
    }
}
