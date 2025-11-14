import SwiftUI

struct SummaryTabSimple: View {
    @EnvironmentObject var store: TimecardStore
    @SwiftUI.State private var segmentIndex: Int = 0

    private var segmentTitles: [String] {
        let weeks = max(1, store.payPeriodWeeks)
        return (0..<weeks).map { "Week \($0 + 1)" } + ["PP Total"]
    }

    private var currentSegmentTitle: String {
        let idx = min(max(0, segmentIndex), segmentTitles.count - 1)
        return segmentTitles[idx]
    }

    private var selectedRange: ClosedRange<Date> {
        let weeks = max(1, store.payPeriodWeeks)
        if segmentIndex < weeks {
            return store.weekRange(offset: segmentIndex)
        } else {
            return store.payPeriodRange
        }
    }

    private var totals: SummaryTotals { store.totals(for: selectedRange) }
    
    // Count # of weeks in selectedRange that contain On Call entries
    private var onCallWeeks: Int {
        let cal = Calendar.current
        var count = 0
        var start = cal.startOfDay(for: selectedRange.lowerBound)
        let end = cal.startOfDay(for: selectedRange.upperBound)
        while start <= end {
            let weekEnd = cal.date(byAdding: .day, value: 6, to: start) ?? start
            let weekRange = start...(min(weekEnd, end))
            let foundOnCall = store.entries(in: weekRange).contains { store.category(for: $0.code) == .onCall }
            if foundOnCall { count += 1 }
            start = cal.date(byAdding: .day, value: 7, to: start) ?? end.addingTimeInterval(1)
        }
        return count
    }

    private var rangeLabel: String {
        let df = DateFormatter(); df.dateStyle = .medium
        return "\(df.string(from: selectedRange.lowerBound)) – \(df.string(from: selectedRange.upperBound))"
    }

    // MARK: - Policy-based OT/DT computation that includes On Call in daily totals
    private func weekDates(from start: Date) -> [Date] {
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: s) }
    }

    private func computeWeekOTDT(weekDates: [Date]) -> [Date: (ot: Double, dt: Double)] {
        let cal = Calendar.current
        // Step 1: total worked hours per day including onCall
        var dayWorked: [Date: Double] = [:]
        for d in weekDates {
            let start = cal.startOfDay(for: d)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let range = start..<end
            let entries = store.entries.filter { e in
                range.contains(e.date) && e.hours != 600 && !e.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let worked = entries.reduce(0.0) { sum, e in
                let cat: PayCategory = e.isNightShift ? .night : store.category(for: e.code)
                if cat == .regular || cat == .night || cat == .ot || cat == .dt || cat == .onCall { return sum + e.hours }
                return sum
            }
            dayWorked[start] = worked
        }
        // Step 2: apply daily thresholds from policy
        var result: [Date: (ot: Double, dt: Double)] = [:]
        for d in weekDates {
            let key = cal.startOfDay(for: d)
            let hours = dayWorked[key] ?? 0
            let p = store.overtimePolicy
            let regularCap = p.dailyRegularCap ?? Double.greatestFiniteMagnitude
            let otUpper = p.dailyOTCap ?? regularCap
            let dtStart = p.dailyDTCap ?? otUpper
            let dailyOT = max(0.0, min(hours, dtStart) - regularCap)
            let dailyDT = max(0.0, hours - dtStart)
            result[key] = (dailyOT, dailyDT)
        }
        // Step 3: Sunday rule (weekly rest) — ensure Sunday hours are at least OT up to DT start
        if let sunday = weekDates.first {
            let sKey = cal.startOfDay(for: sunday)
            let hours = dayWorked[sKey] ?? 0
            let current = result[sKey] ?? (0,0)
            let dtStart = store.overtimePolicy.dailyDTCap ?? (store.overtimePolicy.dailyOTCap ?? Double.greatestFiniteMagnitude)
            let ensuredOT = max(current.ot, max(0.0, min(hours, dtStart)))
            result[sKey] = (ensuredOT, current.dt)
        }
        // Step 4: Weekly rule — hours beyond weekly cap become OT after daily rules
        if let weeklyCap = store.overtimePolicy.weeklyRegularCap {
            let totalWorked = dayWorked.values.reduce(0.0, +)
            let weeklyExcess = max(0.0, totalWorked - weeklyCap)
            if weeklyExcess > 0 {
                var remaining = weeklyExcess
                for d in weekDates.reversed() {
                    if remaining <= 0 { break }
                    let key = cal.startOfDay(for: d)
                    let hours = dayWorked[key] ?? 0
                    var current = result[key] ?? (0,0)
                    let already = current.ot + current.dt
                    let regLeft = max(0.0, hours - already)
                    if regLeft > 0 {
                        let alloc = min(regLeft, remaining)
                        current.ot += alloc
                        remaining -= alloc
                        result[key] = current
                    }
                }
            }
        }
        return result
    }

    private func computedOTDTForSelectedRange() -> (ot: Double, dt: Double) {
        let cal = Calendar.current
        let weeks = max(1, store.payPeriodWeeks)
        var sumOT: Double = 0
        var sumDT: Double = 0
        if segmentIndex < weeks {
            let days = weekDates(from: store.weekRange(offset: segmentIndex).lowerBound)
            let map = computeWeekOTDT(weekDates: days)
            for d in days {
                let key = cal.startOfDay(for: d)
                let v = map[key] ?? (0,0)
                sumOT += min(v.ot, 4.0)
                sumDT += v.dt
            }
        } else {
            // Pay period: iterate each constituent week
            for w in 0..<weeks {
                let days = weekDates(from: store.weekRange(offset: w).lowerBound)
                let map = computeWeekOTDT(weekDates: days)
                for d in days {
                    let key = cal.startOfDay(for: d)
                    let v = map[key] ?? (0,0)
                    sumOT += min(v.ot, 4.0)
                    sumDT += v.dt
                }
            }
        }
        return (sumOT, sumDT)
    }

    private func onCallAmountsForSelectedRange() -> (stipend: Double, occurrencesAmount: Double) {
        let cal = Calendar.current
        let range = selectedRange
        // Stipend: $300 per week with any On Call in that week
        var stipendWeeks = 0
        var start = cal.startOfDay(for: range.lowerBound)
        let end = cal.startOfDay(for: range.upperBound)
        while start <= end {
            let weekEnd = cal.date(byAdding: .day, value: 6, to: start) ?? start
            let weekRange = start...(min(weekEnd, end))
            let hasOnCall = store.entries(in: weekRange).contains { store.category(for: $0.code) == .onCall }
            if hasOnCall { stipendWeeks += 1 }
            start = cal.date(byAdding: .day, value: 7, to: start) ?? end.addingTimeInterval(1)
        }
        let stipend = Double(stipendWeeks) * 300.0
        // Occurrences: $50 per On Call entry in the selected range
        let occurrences = store.entries(in: range).filter { store.category(for: $0.code) == .onCall }.count
        let occurrencesAmount = Double(occurrences) * 50.0
        return (stipend, occurrencesAmount)
    }

    var body: some View {
        NavigationStack {
            List {
                header
                Section(currentSegmentTitle + " Totals") {
                    totalRow("Regular Time", totals.regular)
                    let comp = computedOTDTForSelectedRange()
                    totalRow("OT", comp.ot)
                    totalRow("DT", comp.dt)
                    totalRow("Vacation (VP)", totals.vacation)
                    totalRow("Night Shift (NS)", totals.night)
                    totalRow("STAT Holiday", totals.stat)
                    if store.onCallEnabled {
                        let oc = onCallAmountsForSelectedRange()
                        totalRow("On Call", oc.stipend, formatAsCurrency: true)
                        HStack {
                            Text("# of On Call")
                            Spacer()
                            Text(oc.occurrencesAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
                                .monospacedDigit()
                        }
                    }
                }
                Section("Total") {
                    totalRow("Total Hours", totals.totalHours, style: .bold)
                }
#if canImport(UIKit)
                Section("History") {
                    NavigationLink(destination: HistoryView().environmentObject(store)) {
                        Label("Pay Period History", systemImage: "clock.arrow.circlepath")
                    }
                }
#endif
            }
#if os(iOS)
            .listStyle(.insetGrouped)
#else
            .listStyle(.inset)
#endif
            .navigationTitle("Summary")
        }
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: self.$segmentIndex) {
                ForEach(Array(segmentTitles.enumerated()), id: \.offset) { idx, title in
                    Text(title).tag(idx as Int)
                }
            }
            .pickerStyle(.segmented)
            Text(rangeLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func totalRow(_ title: String, _ value: Double, style: Font.Weight? = nil, formatAsCurrency: Bool = false) -> some View {
        HStack {
            Text(title).fontWeight(style == .bold ? .semibold : .regular)
            Spacer()
            if formatAsCurrency {
                Text(value, format: .currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
                    .monospacedDigit()
                    .fontWeight(style == .bold ? .semibold : .regular)
            } else {
                Text(value, format: .number.precision(.fractionLength(0...2)))
                    .monospacedDigit()
                    .fontWeight(style == .bold ? .semibold : .regular)
            }
        }
    }
}

#Preview {
    SummaryTabSimple()
        .environmentObject(TimecardStore.sampleStore)
}
