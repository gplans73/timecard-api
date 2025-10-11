import SwiftUI
import Foundation

// MARK: - Helpers
extension DateFormatter {
    static let shortMDY: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM/dd/yy"
        return df
    }()
}

// MARK: - Keyboard Dismiss Modifier
struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(action: {
                        #if canImport(UIKit)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                    }) {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .foregroundColor(.accentColor)
                    }
                }
            }
    }
}

extension View {
    func withKeyboardDismissButton() -> some View {
        modifier(KeyboardDismissModifier())
    }
}

// MARK: - Main View
struct TimeEntryView_FULL_SunSatFriday_ALIGNED: View {
    @EnvironmentObject var store: TimecardStore

    private var weekDays: [Date] {
        let cal = Calendar.current
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: store.selectedWeekStart) }
    }
    private var currentWeekRange: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.startOfDay(for: store.selectedWeekStart)
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
        return start ... endOfDay
    }
    private var weeklyTotal: Double {
        store.entries.filter { currentWeekRange.contains($0.date) }.reduce(0) { $0 + $1.hours }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.payPeriodWeeks > 1 {
                        Picker("Week", selection: $store.selectedWeekIndex) {
                            ForEach(0..<(max(1, store.payPeriodWeeks)), id: \.self) { idx in
                                Text("Week \(idx + 1)").tag(idx)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    headerBlock
                    daySections
                    weeklyTotalRow
                }
                .padding(.bottom, 24)
            }
            .withKeyboardDismissButton()  // Add keyboard dismiss button here
            .navigationBarTitleDisplayMode(.inline)
            .onTapGesture {
#if canImport(UIKit)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
            }
            .onAppear {
                if store.autoHolidaysEnabled {
                    store.addStatHolidaysForCurrentPeriod()
                }
            }
        }
    }

    // MARK: Header (tight PP#, slim chip, full range visible)
    private var headerBlock: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Time Card")
                        .font(.system(size: 34, weight: .bold))

                    HStack(spacing: 6) {
                        Text("PP#:").foregroundStyle(.secondary)
                        Text("\(store.payPeriodNumber)")
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                    }
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                }

                Spacer()

                if let img = store.companyLogoImage {
                    img
                        .resizable()
                        .scaledToFit()
                        .frame(width: 118, height: 118)
                        .padding(.top, 2)
                }
            }

            dateRow
        }
        .padding(.horizontal)
        .padding(.top, 2)
    }

    private var dateRow: some View {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 6, to: store.selectedWeekStart) ?? store.selectedWeekStart

        return HStack(spacing: 12) {
            DatePicker(
                "Week",
                selection: Binding(
                    get: { store.selectedWeekStart },
                    set: { newDate in
                        let d = Calendar.current.startOfDay(for: newDate)
                        let pp = store.currentPayPeriod
                        // Simple logic for week selection based on current pay period structure
                        let weekStartDiff = Calendar.current.dateComponents([.day], from: pp.start, to: d).day ?? 0
                        let idx = max(0, min(max(0, store.payPeriodWeeks - 1), weekStartDiff / 7))
                        store.selectedWeekIndex = idx
                    }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray6), in: Capsule())

            Text("\(DateFormatter.shortMDY.string(from: store.selectedWeekStart)) – \(DateFormatter.shortMDY.string(from: end))")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)
        }
    }

    private var daySections: some View {
        VStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                DaySection(day: day).environmentObject(store)
            }
        }
    }

    private var weeklyTotalRow: some View {
        HStack {
            Text("Weekly Total:").font(.headline)
            Spacer()
            Text(weeklyTotal, format: .number.precision(.fractionLength(2)))
                .font(.headline)
                .monospacedDigit()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: One Day Section
private struct DaySection: View {
    @EnvironmentObject var store: TimecardStore
    let day: Date
    @State private var expanded: Bool

    init(day: Date) {
        self.day = day
        let weekday = Calendar.current.component(.weekday, from: day) // Sunday = 1, Saturday = 7
        self._expanded = State(initialValue: !(weekday == 1 || weekday == 7))
    }

    private var dayEntries: [Entry] {
        let cal = Calendar.current
        return store.entries.filter { cal.isDate($0.date, inSameDayAs: day) }
    }
    private func isHolidayEntry(_ e: Entry) -> Bool {
        e.code.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("H") == .orderedSame ||
        e.jobNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "stat"
    }
    private var visibleEntries: [Entry] {
        return dayEntries
    }
    private var dayTitle: String {
        let df = DateFormatter(); df.dateFormat = "EEEE, MMM d"
        let base = df.string(from: day).uppercased()
        if store.isStatHoliday(day) {
            if let name = store.holidayName(for: day), !name.isEmpty {
                return "STAT HOLIDAY – \(name.uppercased()) \(base)"
            } else {
                return "STAT HOLIDAY \(base)"
            }
        }
        return base
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Centered title
                Text(dayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                // Trailing chevron button
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(store.accentColor.opacity(0.92))

            if expanded {
                VStack(spacing: 10) {
                    if visibleEntries.isEmpty {
                        if store.isStatHoliday(day) {
                            // Ensure holidays are present for this period; do not add a blank row
                            if store.autoHolidaysEnabled {
                                EmptyView()
                                    .onAppear {
                                        store.addStatHolidaysForCurrentPeriod()
                                    }
                            } else {
                                EmptyView()
                            }
                        } else {
                            // Do not auto-insert a blank entry for non-holiday empty days.
                            // Users can tap "Add job for this day" to create the first row.
                            EmptyView()
                        }
                    } else {
                        ForEach(visibleEntries) { entry in
                            let b = bindingForEntry(id: entry.id)
                            SwipeToDeleteRow(onDelete: {
                                if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
                                    store.entries.remove(at: idx)
                                }
                            }) {
                                EntryRow(
                                    jobNumber: Binding(get: { b.wrappedValue.jobNumber }, set: { b.wrappedValue.jobNumber = $0 }),
                                    hours:    Binding(get: { b.wrappedValue.hours },      set: { b.wrappedValue.hours = $0 }),
                                    code:     Binding(get: { b.wrappedValue.code },       set: { b.wrappedValue.code = $0 }),
                                    notes:    Binding(get: { b.wrappedValue.notes },      set: { b.wrappedValue.notes = $0 }),
                                    isOvertime: Binding(get: { b.wrappedValue.isOvertime }, set: { b.wrappedValue.isOvertime = $0 }),
                                    isNightShift: Binding(get: { b.wrappedValue.isNightShift }, set: { b.wrappedValue.isNightShift = $0 }),
                                    onDelete: {
                                        if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
                                            store.entries.remove(at: idx)
                                        }
                                    }
                                )
                                .environmentObject(store)
                                .padding(.horizontal)
                            }
                        }
                    }

                    HStack {
                        Button {
                            appendEntry(for: day)
                        } label: {
                            Label("Add job for this day", systemImage: "plus.circle")
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
#if os(iOS)
                                .background(Color(UIColor.secondarySystemBackground), in: Capsule())
#else
                                .background(Color.secondary.opacity(0.25), in: Capsule())
#endif
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
            }
        }
        .background(Color(.systemGray5))
    }

    private func appendEntry(for date: Date) {
        let entryToAdd = Entry(
            date: date,
            jobNumber: "",
            code: "",
            hours: 0,
            notes: ""
        )
        store.entries.append(entryToAdd)
    }
    private func removeLastEntry(for date: Date) {
        let cal = Calendar.current
        if let idx = store.entries.lastIndex(where: { cal.isDate($0.date, inSameDayAs: date) }) {
            store.entries.remove(at: idx)
        }
    }
    private func bindingForEntry(id: UUID) -> Binding<Entry> {
        Binding<Entry>(
            get: {
                if let existingEntry = store.entries.first(where: { $0.id == id }) {
                    return existingEntry
                } else {
                    // Create a new Entry with the same structure as store.entries
                    return Entry(
                        date: day,
                        jobNumber: "",
                        code: "",
                        hours: 0,
                        notes: ""
                    )
                }
            },
            set: { newValue in
                if let i = store.entries.firstIndex(where: { $0.id == id }) {
                    store.entries[i] = newValue
                }
            }
        )
    }
}

// MARK: - Swipe-to-delete wrapper for non-List rows
private struct SwipeToDeleteRow<Content: View>: View {
    @State private var offsetX: CGFloat = 0
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    private let threshold: CGFloat = 80
    private let maxSwipe: CGFloat = 140
    private let swipeHotZoneHeight: CGFloat = 48

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background
            Rectangle()
                .fill(Color.red)
                .overlay(
                    Label("Delete", systemImage: "trash")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.trailing, 20),
                    alignment: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opacity(offsetX < -2 ? 1 : 0)

            // Foreground content that slides
            content()
                .offset(x: offsetX)
                .overlay(alignment: .bottom) {
                    // A narrow swipe hot zone so the rest of the card scrolls normally
                    Color.clear
                        .frame(height: swipeHotZoneHeight)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                                .onChanged { value in
                                    // Only handle leftward horizontal drags; let vertical drags fall through to ScrollView
                                    let absX = abs(value.translation.width)
                                    let absY = abs(value.translation.height)
                                    guard absX > absY, value.translation.width < 0 else { return }

                                    let dx = min(0, value.translation.width)
                                    let clamped = max(dx, -maxSwipe)
                                    withAnimation(.interactiveSpring()) { offsetX = clamped }
                                }
                                .onEnded { _ in
                                    if offsetX < -threshold {
                                        withAnimation(.easeIn) { offsetX = -maxSwipe }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { onDelete() }
                                    } else {
                                        withAnimation(.spring()) { offsetX = 0 }
                                    }
                                }
                        )
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    TimeEntryView_FULL_SunSatFriday_ALIGNED()
        .environmentObject(TimecardStore.sampleStore)
}
