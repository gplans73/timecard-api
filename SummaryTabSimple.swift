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

    var body: some View {
        NavigationStack {
            List {
                header
                Section(currentSegmentTitle + " Totals") {
                    totalRow("Regular Time", totals.regular)
                    totalRow("OT", totals.ot)
                    totalRow("DT", totals.dt)
                    totalRow("Vacation (VP)", totals.vacation)
                    totalRow("Night Shift (NS)", totals.night)
                    totalRow("STAT Holiday", totals.stat)
                    if store.onCallEnabled {
                        totalRow("On Call", totals.onCall, formatAsCurrency: true)
                        HStack {
                            Text("# of On Call")
                            Spacer()
                            Text(totals.onCallBonus, format: .currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
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
