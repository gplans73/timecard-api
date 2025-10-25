// LGSummary_FIX_internal.swift
import SwiftUI

/// Summary screen that reads from the same source of truth as the Time tab (`TimecardStore.entries`)
/// and shows Week 1 / Week 2 / Pay-Period totals.
struct Summary_FIX_internal: View {
    @EnvironmentObject var store: TimecardStore
    @State private var segmentIndex: Int = 0

    private var segmentTitles: [String] {
        let weeks = max(1, store.payPeriodWeeks)
        return (0..<weeks).map { "Week \($0 + 1)" } + ["PP Total"]
    }

    private var currentSegmentTitle: String {
        let idx = min(max(0, segmentIndex), segmentTitles.count - 1)
        return segmentTitles[idx]
    }

    // MARK: - Derived values

    private var selectedRange: ClosedRange<Date> {
        let weeks = max(1, store.payPeriodWeeks)
        if segmentIndex < weeks {
            return store.weekRange(offset: segmentIndex)
        } else {
            return store.payPeriodRange
        }
    }

    private var totals: SummaryTotals {
        store.totals(for: selectedRange)
    }

    private var rangeLabel: String {
        let df = DateFormatter(); df.dateStyle = .medium
        return "\(df.string(from: selectedRange.lowerBound)) – \(df.string(from: selectedRange.upperBound))"
    }

    // MARK: - View

    var body: some View {
        NavigationStack {
            List {
                header

                Section("\(currentSegmentTitle) Totals") {
                    totalRow("Regular Time", totals.regular)
                    totalRow("OT", totals.ot)
                    totalRow("DT", totals.dt)
                    totalRow("Vacation (VP)", totals.vacation)
                    totalRow("Night Shift (NS)", totals.night)
                    totalRow("STAT Holiday", totals.stat)
                    // On Call row added as currency
                    if store.onCallEnabled {
                        onCallRow("On Call", totals.onCall)
                    }
                }

                Section("Total") {
                    totalRow("Total Hours", totals.totalHours, style: .bold)
                }

                // Optional: show the raw entries included in this range
                if !entriesInSelectedRange.isEmpty {
                    Section("Included Entries") {
                        ForEach(entriesInSelectedRange) { e in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.code).font(.subheadline.weight(.semibold))
                                    Text(e.date, style: .date)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                Spacer()
                                Text(e.hours, format: .number.precision(.fractionLength(0...2)))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
#if os(iOS)
            .listStyle(.insetGrouped)
#else
            .listStyle(.inset)
#endif
            .navigationTitle("Summary")
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $segmentIndex) {
                ForEach(Array(segmentTitles.enumerated()), id: \.offset) { idx, title in
                    Text(title).tag(idx)
                }
            }
            .pickerStyle(.segmented)

            Text(rangeLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func totalRow(_ title: String, _ value: Double, style: Font.Weight? = nil) -> some View {
        HStack {
            Text(title).fontWeight(style == .bold ? .semibold : .regular)
            Spacer()
            Text(value, format: .number.precision(.fractionLength(0...2)))
                .monospacedDigit()
                .fontWeight(style == .bold ? .semibold : .regular)
        }
    }

    // Added helper for formatting currency without cents
    private func currencyNoCents(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 0
        return nf.string(from: NSNumber(value: value)) ?? ""
    }

    // Added helper for On Call row with currency formatting
    private func onCallRow(_ title: String, _ value: Double, style: Font.Weight? = nil) -> some View {
        HStack {
            Text(title).fontWeight(style == .bold ? .semibold : .regular)
            Spacer()
            Text(currencyNoCents(value))
                .fontWeight(style == .bold ? .semibold : .regular)
        }
    }

    // MARK: - Helpers

    private var entriesInSelectedRange: [Entry] {
        store.entries.filter { selectedRange.contains($0.date) }
    }
}

#Preview {
    Summary_FIX_internal()
        .environmentObject(TimecardStore.sampleStore)
}
