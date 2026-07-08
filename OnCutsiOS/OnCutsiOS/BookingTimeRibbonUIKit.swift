//
//  BookingTimeRibbonUIKit.swift
//  Intera
//
//  Horizontal time-slot ribbon with UIScrollView center detection for selection haptics.
//

import SwiftUI

/// One slot in the ribbon (`timeKey` matches `HH:mm` for booking).
struct BookingRibbonSlot: Equatable {
    let timeKey: String
    let label: String
    let available: Bool
}

extension Array where Element == BookingRibbonSlot {
    /// Booked or blocked slots are omitted from the picker — only open times are shown.
    var availableOnly: [BookingRibbonSlot] {
        filter(\.available)
    }
}

// MARK: - Day period bucketing (morning / afternoon / evening)

enum BookingDayPeriod: String, CaseIterable, Identifiable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"

    var id: String { rawValue }

    /// Classifies a Pacific `HH:mm` slot key for horizontal period rows.
    static func from(timeKeyHHmm: String) -> BookingDayPeriod {
        let parts = timeKeyHHmm.split(separator: ":")
        guard let hour = Int(parts.first ?? "") else { return .afternoon }
        if hour < 12 { return .morning }
        if hour < 17 { return .afternoon }
        return .evening
    }
}

enum BookingRibbonSlotGrouping {
    /// Preserves period order; omits empty buckets.
    static func byPeriod(_ slots: [BookingRibbonSlot]) -> [(period: BookingDayPeriod, slots: [BookingRibbonSlot])] {
        var buckets: [BookingDayPeriod: [BookingRibbonSlot]] = [:]
        for slot in slots {
            let period = BookingDayPeriod.from(timeKeyHHmm: slot.timeKey)
            buckets[period, default: []].append(slot)
        }
        return BookingDayPeriod.allCases.compactMap { period in
            guard let rows = buckets[period], !rows.isEmpty else { return nil }
            return (period, rows)
        }
    }
}

extension BookingPacificSchedule {
    /// Wall-clock instant for a picked Pacific calendar day + `HH:mm` slot (availability keys).
    static func pacificInstant(selectedDay: Date, timeHHmm: String) -> Date? {
        let parts = timeHHmm.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacificTimeZone
        let dc = cal.dateComponents([.year, .month, .day], from: selectedDay)
        guard let y = dc.year, let mo = dc.month, let day = dc.day else { return nil }

        var full = DateComponents(calendar: cal, timeZone: pacificTimeZone)
        full.year = y
        full.month = mo
        full.day = day
        full.hour = hour
        full.minute = minute
        full.second = 0
        return cal.date(from: full)
    }
}

#if canImport(UIKit)
import UIKit

struct BookingTimeRibbonUIKit: UIViewRepresentable {
    var slots: [BookingRibbonSlot]
    var selectedKey: String?
    var onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .clear

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -14),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])

        context.coordinator.scrollView = scroll
        context.coordinator.stackView = stack
        context.coordinator.selectionGenerator.prepare()

        return scroll
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.selectedKey = selectedKey

        let signature = slots.map { "\($0.timeKey)|\($0.available)" }.joined(separator: ";")
        if context.coordinator.slotSignature != signature {
            context.coordinator.slotSignature = signature
            context.coordinator.lastCenteredIndex = nil
        }
        context.coordinator.slots = slots

        guard let stack = context.coordinator.stackView else { return }

        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, slot) in slots.enumerated() {
            let cell = makeCell(for: slot, index: index, coordinator: context.coordinator)
            stack.addArrangedSubview(cell)
            cell.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        }

        scrollView.layoutIfNeeded()
        context.coordinator.updateCenterHaptic(scrollView: scrollView)
    }

    private func makeCell(for slot: BookingRibbonSlot, index: Int, coordinator: Coordinator) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tag = index
        button.setTitle(slot.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.85
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        button.layer.cornerRadius = 14
        button.layer.masksToBounds = true

        let selected = coordinator.selectedKey == slot.timeKey
        if slot.available {
            button.isEnabled = true
            button.alpha = 1
            button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
            button.setTitleColor(.label, for: .normal)
            button.layer.borderWidth = selected ? 2 : 1
            button.layer.borderColor = (selected ? UIColor.white : UIColor.white.withAlphaComponent(0.25)).cgColor
        } else {
            button.isEnabled = false
            button.alpha = 0.2
            button.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            button.setTitleColor(.secondaryLabel, for: .normal)
            button.layer.borderWidth = 0
        }

        button.addAction(UIAction { [weak coordinator] _ in
            guard slot.available else { return }
            coordinator?.onSelect(slot.timeKey)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }, for: .touchUpInside)

        return button
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onSelect: (String) -> Void
        var slots: [BookingRibbonSlot] = []
        var selectedKey: String?
        weak var scrollView: UIScrollView?
        weak var stackView: UIStackView?

        let selectionGenerator = UISelectionFeedbackGenerator()
        var lastCenteredIndex: Int?
        var slotSignature: String = ""

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateCenterHaptic(scrollView: scrollView)
        }

        func updateCenterHaptic(scrollView: UIScrollView) {
            guard let stack = stackView, !stack.arrangedSubviews.isEmpty else { return }

            let centerX = scrollView.contentOffset.x + scrollView.bounds.width * 0.5
            var bestIndex: Int?
            var bestDistance: CGFloat = .greatestFiniteMagnitude

            for sub in stack.arrangedSubviews {
                let frame = sub.convert(sub.bounds, to: scrollView)
                let mid = frame.midX
                let d = abs(mid - centerX)
                if d < bestDistance {
                    bestDistance = d
                    bestIndex = sub.tag
                }
            }

            guard let idx = bestIndex, lastCenteredIndex != idx else { return }
            lastCenteredIndex = idx
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        }
    }
}

#endif
