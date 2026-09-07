//
//  DiscoverOperatorsPullUpSheet.swift
//  OnCuts
//
//  Bottom pull-up for Discover operators. A clear swipe up/down always finishes
//  open or closed — it does not spring back mid-transition.
//

import SwiftUI

struct DiscoverOperatorsPullUpSheet: View {
    let title: String
    let providers: [ServiceProvider]
    var isLoading: Bool = false
    var showsDistance: Bool = false
    var bottomInset: CGFloat = 0
    /// Increment to force the sheet open when an operator area is tapped on the map.
    var reopenToken: Int = 0
    /// When non-`nil` (signed-out Discover), open state follows guest sign-in idle (`true`) vs active (`false`).
    var preferredIsOpen: Bool? = nil
    /// Fired when the sheet settles open (e.g. dismiss guest email keyboard).
    var onOpened: (() -> Void)? = nil
    let onProviderTap: (ServiceProvider) -> Void

    @State private var isOpen: Bool = true
    @State private var sheetHeight: CGFloat = 0
    @State private var dragStartHeight: CGFloat = 0
    @State private var isDragging: Bool = false

    private var closedHeight: CGFloat { 52 + bottomInset }
    private var openHeight: CGFloat { 240 + bottomInset }

    private var renderedSheetHeight: CGFloat {
        if sheetHeight > 1 { return sheetHeight }
        return isOpen ? openHeight : closedHeight
    }

    private var openProgress: CGFloat {
        let span = max(1, openHeight - closedHeight)
        return min(1, max(0, (renderedSheetHeight - closedHeight) / span))
    }

    private var restingHeight: CGFloat {
        isOpen ? openHeight : closedHeight
    }

    private var sheetSpring: Animation {
        .interactiveSpring(response: 0.28, dampingFraction: 0.9, blendDuration: 0.1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header owns vertical open/close — highPriority so map can't cancel mid-swipe.
            header
                .highPriorityGesture(sheetDragGesture)

            VStack(spacing: 0) {
                if isLoading && providers.isEmpty {
                    ProgressView()
                        .tint(Color.oliveGreen)
                        .frame(maxWidth: .infinity)
                        .frame(height: 132)
                } else if providers.isEmpty {
                    Text("No operators here yet")
                        .font(OnCutsFont.bodyMedium)
                        .foregroundStyle(Color.neutral500)
                        .frame(maxWidth: .infinity)
                        .frame(height: 132)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(providers) { provider in
                                BarberPhotoTile(
                                    provider: provider,
                                    showsDistance: showsDistance,
                                    onTap: { onProviderTap(provider) }
                                )
                                .frame(width: 168, height: 168)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }
                    .frame(height: 168)
                    .scrollDisabled(isDragging)
                    // Simultaneous so horizontal tile scroll still works.
                    .simultaneousGesture(sheetDragGesture)
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(Double(openProgress))
            .allowsHitTesting(openProgress > 0.45 && !isDragging)

            Spacer(minLength: 0)
                .frame(height: max(0, bottomInset))
                .contentShape(Rectangle())
                .highPriorityGesture(sheetDragGesture)
        }
        .frame(maxWidth: .infinity)
        .frame(height: renderedSheetHeight, alignment: .top)
        .clipped()
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 20, bottomLeading: 0, bottomTrailing: 0, topTrailing: 20),
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay {
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 20, bottomLeading: 0, bottomTrailing: 0, topTrailing: 20),
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.35), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: -4)
        }
        .contentShape(Rectangle())
        .onAppear {
            if let preferredIsOpen {
                settle(open: preferredIsOpen, animated: false)
            } else if sheetHeight <= 1 {
                sheetHeight = restingHeight
            }
        }
        .onChange(of: bottomInset) { _, _ in
            settle(open: isOpen, animated: false)
        }
        .onChange(of: reopenToken) { _, _ in
            settle(open: true)
        }
        .onChange(of: preferredIsOpen) { _, preferred in
            guard let preferred else { return }
            settle(open: preferred)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.28))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)

            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(OnCutsFont.headlineSmall.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !providers.isEmpty {
                    Text("\(providers.count)")
                        .font(OnCutsFont.caption.weight(.semibold))
                        .foregroundStyle(Color.neutral500)
                        .opacity(Double(openProgress))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOpen ? "Operators, open" : "Operators, closed")
        .accessibilityHint(isOpen ? "Swipe down to close" : "Swipe up to open")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(isOpen ? "Close" : "Open")) {
            settle(open: !isOpen)
        }
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                let dx = abs(value.translation.width)
                let dy = abs(value.translation.height)

                if !isDragging {
                    // Lock only on a clearly vertical drag. Horizontal carousel pans
                    // share this gesture via simultaneousGesture and must not steal.
                    guard dy >= 10, dy > dx * 1.15 else { return }
                    isDragging = true
                    dragStartHeight = sheetHeight > 1 ? sheetHeight : restingHeight
                }

                let proposed = dragStartHeight - value.translation.height
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    sheetHeight = rubberBand(proposed)
                }
            }
            .onEnded { value in
                let translationY = value.translation.height
                let predictedY = value.predictedEndTranslation.height
                let velocityY = value.velocity.height
                let locked = isDragging
                let movedSheet = abs(renderedSheetHeight - restingHeight) > 4

                isDragging = false

                // Do not settle from incidental vertical noise on a horizontal scroll.
                // `clearSwipe` used to fire here and snap the sheet closed mid-pan.
                guard locked || movedSheet else { return }

                settle(
                    open: resolvedOpen(
                        translationY: translationY,
                        predictedY: predictedY,
                        velocityDownPositive: velocityY
                    )
                )
            }
    }

    private func rubberBand(_ proposed: CGFloat) -> CGFloat {
        let minH = closedHeight
        let maxH = openHeight
        if proposed < minH {
            let overflow = minH - proposed
            return minH - overflow * 0.16
        }
        if proposed > maxH {
            let overflow = proposed - maxH
            return maxH + overflow * 0.12
        }
        return proposed
    }

    /// Positive translationY / velocityY = finger moving down.
    /// Translation direction wins over release-velocity flick — otherwise a swipe-up
    /// that ends with a tiny downward lift incorrectly snaps closed.
    private func resolvedOpen(
        translationY: CGFloat,
        predictedY: CGFloat,
        velocityDownPositive: CGFloat
    ) -> Bool {
        let effectiveY: CGFloat = {
            // Prefer predicted end when it amplifies the same direction.
            if abs(predictedY) > abs(translationY),
               (predictedY < 0) == (translationY < 0) || abs(translationY) < 8 {
                return predictedY
            }
            return translationY
        }()

        // Any clear finger travel completes that direction.
        if effectiveY < -4 { return true }
        if effectiveY > 4 { return false }

        // Near-zero travel: fling velocity decides.
        if velocityDownPositive < -80 { return true }
        if velocityDownPositive > 80 { return false }

        // Still ambiguous: finish to the nearer detent.
        let mid = (openHeight + closedHeight) * 0.5
        return renderedSheetHeight >= mid
    }

    private func settle(open: Bool, animated: Bool = true) {
        let target = open ? openHeight : closedHeight
        let apply = {
            isOpen = open
            sheetHeight = target
        }
        if animated {
            withAnimation(sheetSpring, apply)
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, apply)
        }
        if open {
            onOpened?()
        }
    }
}
