//
//  BookingSelectorsViews.swift
//  Intera
//
//  Date (month calendar grid), time (period-grouped horizontal rows), and location rows aligned with Service & pricing UX.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Date (calendar grid)

/// Full month grid: cream text on transparent circles; selected day fills cream with charcoal text.
struct BookingCalendarGridSelector: View {
    @Binding var selectedDate: Date
    @Binding var selectionCommitted: Bool
    let range: ClosedRange<Date>
    /// When non-`nil`, only these start-of-day instants (`Calendar.current`) are tappable; other in-range days are dimmed.
    var allowedDayStarts: Set<Date>? = nil
    /// Called after the user picks a selectable day (including the first commitment).
    var onDaySelected: () -> Void = {}
    /// Called when the visible month changes (including on appear).
    var onDisplayedMonthChange: (Date) -> Void = { _ in }

    @State private var displayedMonth: Date

    private let calendar = Calendar.current

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private let weekdayColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    init(
        selectedDate: Binding<Date>,
        selectionCommitted: Binding<Bool>,
        range: ClosedRange<Date>,
        allowedDayStarts: Set<Date>? = nil,
        onDaySelected: @escaping () -> Void = {},
        onDisplayedMonthChange: @escaping (Date) -> Void = { _ in }
    ) {
        self._selectedDate = selectedDate
        self._selectionCommitted = selectionCommitted
        self.range = range
        self.allowedDayStarts = allowedDayStarts
        self.onDaySelected = onDaySelected
        self.onDisplayedMonthChange = onDisplayedMonthChange
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate.wrappedValue))
            ?? selectedDate.wrappedValue
        _displayedMonth = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 22) {
            monthNavigationHeader
            weekdayHeaderRow

            LazyVGrid(columns: weekdayColumns, spacing: 12) {
                ForEach(gridDates, id: \.self) { day in
                    calendarDayCell(for: day)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            }
        }
        .onAppear {
            displayedMonth = startOfMonth(selectedDate)
            onDisplayedMonthChange(displayedMonth)
        }
        .onChange(of: selectedDate) { _, newValue in
            displayedMonth = startOfMonth(newValue)
        }
    }

    private var monthNavigationHeader: some View {
        HStack {
            Button {
                guard canGoPreviousMonth else { return }
                withAnimation(BookingSelectorTheme.selectionSpring) {
                    displayedMonth = addMonths(-1, to: displayedMonth)
                }
                onDisplayedMonthChange(displayedMonth)
            } label: {
                Image(systemName: "chevron.left")
                    .font(InteraFont.body.weight(.semibold))
                    .foregroundStyle(BookingSelectorTheme.cream)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")
            .disabled(!canGoPreviousMonth)
            .opacity(canGoPreviousMonth ? 1 : 0.35)

            Spacer(minLength: 8)

            Text(Self.monthYearFormatter.string(from: displayedMonth))
                .font(BookingSelectorTheme.todayBoldFont)
                .foregroundStyle(BookingSelectorTheme.cream)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                guard canGoNextMonth else { return }
                withAnimation(BookingSelectorTheme.selectionSpring) {
                    displayedMonth = addMonths(1, to: displayedMonth)
                }
                onDisplayedMonthChange(displayedMonth)
            } label: {
                Image(systemName: "chevron.right")
                    .font(InteraFont.body.weight(.semibold))
                    .foregroundStyle(BookingSelectorTheme.cream)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
            .disabled(!canGoNextMonth)
            .opacity(canGoNextMonth ? 1 : 0.35)
        }
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(orderedWeekdayInitials.enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .bookingCalendarWeekdayLabelStyle()
                    .foregroundStyle(BookingSelectorTheme.cream)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var orderedWeekdayInitials: [String] {
        let syms = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return (0 ..< 7).map { syms[($0 + offset) % 7] }
    }

    private var gridDates: [Date] {
        let first = startOfMonth(displayedMonth)
        guard let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count else { return [] }

        let padStart = weekdayColumnIndex(for: first)
        var cells: [Date] = []

        for i in 0 ..< padStart {
            if let d = calendar.date(byAdding: .day, value: i - padStart, to: first) {
                cells.append(d)
            }
        }
        for d in 0 ..< daysInMonth {
            if let date = calendar.date(byAdding: .day, value: d, to: first) {
                cells.append(date)
            }
        }
        var next = calendar.date(byAdding: .day, value: daysInMonth, to: first) ?? first
        while cells.count % 7 != 0 {
            cells.append(next)
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
        }
        return cells
    }

    @ViewBuilder
    private func calendarDayCell(for day: Date) -> some View {
        let dayStart = calendar.startOfDay(for: day)
        let rangeLower = calendar.startOfDay(for: range.lowerBound)
        let rangeUpper = calendar.startOfDay(for: range.upperBound)
        let inSelectableRange = (dayStart >= rangeLower) && (dayStart <= rangeUpper)
        let passesAvailability =
            allowedDayStarts == nil || allowedDayStarts!.contains(dayStart)
        let selectable = inSelectableRange && passesAvailability
        let inDisplayedMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let selected = selectionCommitted && calendar.isDate(day, inSameDayAs: selectedDate)

        let labelOpacity: Double = {
            if !inSelectableRange { return 0.22 }
            if allowedDayStarts != nil && !passesAvailability { return 0.22 }
            if !inDisplayedMonth { return 0.38 }
            return 1
        }()

        Button {
            guard selectable else { return }
            let wasSameDaySelected =
                selectionCommitted && calendar.isDate(day, inSameDayAs: selectedDate)
            BookingSelectorTheme.triggerSelectionChangedIfNewSelection(wasSelected: wasSameDaySelected)
            selectionCommitted = true
            withAnimation(BookingSelectorTheme.selectionSpring) {
                let preservedTimeKey = BookingPacificSchedule.pacificHHmmKey(from: selectedDate)
                let pacificDay = BookingPacificSchedule.pacificStartOfDay(for: day)
                if let merged = BookingPacificSchedule.pacificInstant(
                    selectedDay: pacificDay,
                    timeHHmm: preservedTimeKey
                ) {
                    selectedDate = merged
                } else {
                    selectedDate = pacificDay
                }
            }
            onDaySelected()
        } label: {
            ZStack {
                Circle()
                    .fill(selected ? BookingSelectorTheme.cream : Color.clear)
                    .animation(BookingSelectorTheme.selectionSpring, value: selected)

                Text("\(calendar.component(.day, from: day))")
                    .font(InteraFont.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? BookingSelectorTheme.deepCharcoal : BookingSelectorTheme.cream)
                    .opacity(labelOpacity)
            }
            .scaleEffect(selected ? 1.06 : 1.0)
            .animation(BookingSelectorTheme.selectionSpring, value: selected)
            .frame(width: 44, height: 44)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
    }

    private var canGoPreviousMonth: Bool {
        startOfMonth(displayedMonth) > startOfMonth(range.lowerBound)
    }

    private var canGoNextMonth: Bool {
        startOfMonth(displayedMonth) < startOfMonth(range.upperBound)
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func addMonths(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: n, to: date) ?? date
    }

    private func weekdayColumnIndex(for date: Date) -> Int {
        let wd = calendar.component(.weekday, from: date)
        let first = calendar.firstWeekday
        return (wd - first + 7) % 7
    }
}

// MARK: - Time (period-grouped horizontal rows)

private enum BookingTimeSlotChipMetrics {
    static let chipHeight: CGFloat = 46
    static let scrollRowHeight: CGFloat = 52
    static let chipMinWidth: CGFloat = 88
}

private struct BookingTimeSlotChip: View {
    let label: String
    let isSelected: Bool
    let isUrgent: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(InteraFont.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(
                    isSelected && !isDisabled
                        ? BookingSelectorTheme.deepCharcoal
                        : Color.lavaShellCream.opacity(isDisabled ? 0.35 : 0.88)
                )
                .padding(.horizontal, 16)
                .frame(minWidth: BookingTimeSlotChipMetrics.chipMinWidth)
                .frame(height: BookingTimeSlotChipMetrics.chipHeight)
                .background {
                    if isSelected && !isDisabled {
                        Capsule(style: .continuous)
                            .fill(BookingSelectorTheme.cream)
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected && !isDisabled
                                ? BookingSelectorTheme.cream
                                : BookingSelectorTheme.cream.opacity(isDisabled ? 0.28 : (isUrgent ? 0.95 : 0.55)),
                            lineWidth: isUrgent && !isSelected && !isDisabled ? 2 : 1.25
                        )
                }
                .shadow(
                    color: isSelected && !isDisabled ? BookingSelectorTheme.cream.opacity(0.35) : .clear,
                    radius: 6,
                    y: 1
                )
                .scaleEffect(isSelected && !isDisabled ? 1.04 : 1.0)
        }
        .buttonStyle(BookButtonStyle())
        .disabled(isDisabled)
        .animation(BookingSelectorTheme.selectionSpring, value: isSelected)
    }
}

struct BookingTimeSlotGrid: View {
    let slots: [BookingRibbonSlot]
    @Binding var selectedTimeKey: String?
    /// When the selected day is today (Pacific), slots starting within two hours get an urgent stroke.
    var selectedCalendarDay: Date? = nil

    private var visibleSlots: [BookingRibbonSlot] {
        slots.availableOnly
    }

    private var periodSections: [(period: BookingDayPeriod, slots: [BookingRibbonSlot])] {
        BookingRibbonSlotGrouping.byPeriod(visibleSlots)
    }

    private var urgentTimeKeys: Set<String> {
        guard let day = selectedCalendarDay else { return [] }
        let now = Date()
        let horizon: TimeInterval = 2 * 60 * 60
        var keys = Set<String>()
        for slot in visibleSlots {
            guard let instant = BookingPacificSchedule.pacificInstant(selectedDay: day, timeHHmm: slot.timeKey) else { continue }
            let delta = instant.timeIntervalSince(now)
            if delta > 0, delta <= horizon {
                keys.insert(slot.timeKey)
            }
        }
        return keys
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(periodSections, id: \.period.id) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.period.rawValue)
                        .font(InteraFont.caption.weight(.bold))
                        .foregroundStyle(Color.lavaShellCreamTertiary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(section.slots, id: \.timeKey) { slot in
                                let selected = selectedTimeKey == slot.timeKey
                                BookingTimeSlotChip(
                                    label: slot.label,
                                    isSelected: selected,
                                    isUrgent: urgentTimeKeys.contains(slot.timeKey),
                                    isDisabled: false
                                ) {
                                    BookingSelectorTheme.triggerSelectionChangedIfNewSelection(wasSelected: selected)
                                    withAnimation(BookingSelectorTheme.selectionSpring) {
                                        selectedTimeKey = slot.timeKey
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 3)
                        .frame(height: BookingTimeSlotChipMetrics.scrollRowHeight)
                    }
                    .clipped()
                }
            }
        }
    }
}

// MARK: - Minute-level time picker (hour + minute wheel)

struct BookingMinuteTimePicker: View {
    let calendarDay: Date
    let availableTimeKeys: Set<String>
    @Binding var selectedTime: Date
    var isLoading: Bool = false
    var loadError: String? = nil
    var emptyMessage: String = "No open times for this day. Try another date."
    /// When false, keep the wheel on the chosen minute even if it is not in `availableTimeKeys` (e.g. editing an existing booking).
    var snapUnavailableToNearestOpen: Bool = true
    /// Minutes always treated as selectable (typically the appointment currently being edited).
    var alwaysAllowedTimeKeys: Set<String> = []

    @State private var selectedSlotKey = ""
    @State private var isSyncingSelection = false

    private var pacificDay: Date {
        BookingPacificSchedule.pacificStartOfDay(for: calendarDay)
    }

    private var allowedKeys: Set<String> {
        availableTimeKeys.union(alwaysAllowedTimeKeys)
    }

    private var sortedSlotKeys: [String] {
        allowedKeys.sorted()
    }

    private var hasOpenTimes: Bool {
        snapUnavailableToNearestOpen ? !availableTimeKeys.isEmpty : !allowedKeys.isEmpty
    }

    var body: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView()
                        .tint(Color.oliveGreen)
                    Text("Loading times…")
                        .font(InteraFont.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let err = loadError {
                Text(err)
                    .font(InteraFont.body)
                    .foregroundStyle(.secondary)
            } else if !hasOpenTimes {
                Text(emptyMessage)
                    .font(InteraFont.body)
                    .foregroundStyle(.secondary)
            } else {
                Group {
                    #if canImport(UIKit)
                    BookingAvailableTimeWheelUIKit(
                        slotKeys: sortedSlotKeys,
                        labels: sortedSlotKeys.map { slotDisplayLabel(for: $0) },
                        selectedKey: $selectedSlotKey
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: BookingTimeWheelMetrics.pickerHeight)
                    #else
                    Picker("Time", selection: $selectedSlotKey) {
                        ForEach(sortedSlotKeys, id: \.self) { key in
                            Text(slotDisplayLabel(for: key))
                                .font(BookingSelectorTheme.timeWheelFont)
                                .tag(key)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    #endif
                }
                .onAppear { syncSelectionFromBinding() }
                .onChange(of: selectedTime) { _, _ in syncSelectionFromBinding() }
                .onChange(of: availableTimeKeys) { _, _ in syncSelectionFromBinding() }
                .onChange(of: alwaysAllowedTimeKeys) { _, _ in syncSelectionFromBinding() }
                .onChange(of: calendarDay) { _, _ in syncSelectionFromBinding() }
                .onChange(of: selectedSlotKey) { _, newKey in
                    guard !isSyncingSelection, !newKey.isEmpty else { return }
                    applySlotSelection(newKey)
                }
            }
        }
    }

    private func slotDisplayLabel(for key: String) -> String {
        guard let instant = BookingPacificSchedule.pacificInstant(selectedDay: pacificDay, timeHHmm: key) else {
            return key
        }
        return BookingPacificSchedule.displayTimeWithMinutes(from: instant)
    }

    private func syncSelectionFromBinding() {
        isSyncingSelection = true
        defer { isSyncingSelection = false }

        let currentKey = BookingPacificSchedule.pacificHHmmKey(from: selectedTime)
        if allowedKeys.contains(currentKey) {
            selectedSlotKey = currentKey
            return
        }

        guard snapUnavailableToNearestOpen else {
            if !currentKey.isEmpty {
                selectedSlotKey = currentKey
            } else if let first = sortedSlotKeys.first {
                selectedSlotKey = first
            }
            return
        }

        var adjusted = selectedTime
        BookingPacificSchedule.reconcileAppointmentTime(
            &adjusted,
            calendarDay: pacificDay,
            availableKeys: allowedKeys
        )
        selectedTime = adjusted
        selectedSlotKey = BookingPacificSchedule.pacificHHmmKey(from: adjusted)
    }

    private func applySlotSelection(_ key: String) {
        guard let instant = BookingPacificSchedule.pacificInstant(selectedDay: pacificDay, timeHHmm: key) else { return }
        if allowedKeys.contains(key) || !snapUnavailableToNearestOpen {
            selectedTime = instant
        }
    }
}

#if canImport(UIKit)

private enum BookingTimeWheelMetrics {
    static let pickerHeight: CGFloat = 216
    static let rowHeight: CGFloat = 44
}

/// Wheel picker with explicit row typography (SwiftUI `.wheel` ignores `.font()` on many OS versions).
private struct BookingAvailableTimeWheelUIKit: UIViewRepresentable {
    let slotKeys: [String]
    let labels: [String]
    @Binding var selectedKey: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedKey: $selectedKey)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ pickerView: UIPickerView, context: Context) {
        let coordinator = context.coordinator
        let keysChanged = coordinator.slotKeys != slotKeys
        coordinator.slotKeys = slotKeys
        coordinator.labels = labels

        if keysChanged {
            pickerView.reloadAllComponents()
            coordinator.lastSyncedRow = nil
        }

        guard let row = slotKeys.firstIndex(of: selectedKey) else { return }
        guard coordinator.lastSyncedRow != row else { return }
        coordinator.isProgrammaticScroll = true
        pickerView.selectRow(row, inComponent: 0, animated: keysChanged ? false : true)
        coordinator.isProgrammaticScroll = false
        coordinator.lastSyncedRow = row
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var slotKeys: [String] = []
        var labels: [String] = []
        @Binding var selectedKey: String
        var isProgrammaticScroll = false
        var lastSyncedRow: Int?

        init(selectedKey: Binding<String>) {
            _selectedKey = selectedKey
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            slotKeys.count
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            BookingTimeWheelMetrics.rowHeight
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.text = row < labels.count ? labels[row] : ""
            label.font = InteraFont.uiFont(size: BookingSelectorTheme.timeWheelUIFontSize, weight: .semibold)
            label.textAlignment = .center
            label.textColor = UIColor(Color.lavaShellCream)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.85
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard !isProgrammaticScroll, row < slotKeys.count else { return }
            let key = slotKeys[row]
            guard selectedKey != key else { return }
            BookingSelectorTheme.triggerSelectionChangedIfNewSelection(wasSelected: false)
            selectedKey = key
            lastSyncedRow = row
        }
    }
}

#endif
