import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: TimecardStore

    private var pastPeriodStarts: [Date] {
        let cal = Calendar.current
        let now = Date()
        guard let oneYearAgo = cal.date(byAdding: .year, value: -1, to: now) else {
            return []
        }
        let starts = store.payPeriodStarts(from: oneYearAgo, to: now)
        return starts.sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            List(pastPeriodStarts, id: \.self) { start in
                NavigationLink(value: start) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(start, style: .date)
                            .font(.headline)
                        Text(start.weekRangeLabel())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(for: Date.self) { start in
                HistoryDetailView(periodStart: start, store: store)
            }
            .navigationTitle("History")
        }
    }
}

private struct HistoryDetailView: View {
    let periodStart: Date
    let store: TimecardStore
    
    @State private var snapshot: TimecardStore?

    var body: some View {
        Group {
            if let snapshot = snapshot {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 16) {
                        GroupBox(label: Label("Week 1", systemImage: "calendar").font(.headline)) {
                            TimecardPDFView(weekOffset: 0)
                                .environmentObject(snapshot)
                                .background(Color.white)
                        }
                        GroupBox(label: Label("Week 2", systemImage: "calendar").font(.headline)) {
                            TimecardPDFView(weekOffset: 1)
                                .environmentObject(snapshot)
                                .background(Color.white)
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
            } else {
                ProgressView("Loading...")
            }
        }
        .navigationTitle("Pay Period")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            snapshot = store.clonedStoreForPayPeriod(start: periodStart)
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
            .environmentObject(TimecardStore.sampleStore)
    }
}
