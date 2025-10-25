import SwiftUI

struct PayPeriodSettingsView: View {
    @EnvironmentObject var store: TimecardStore

    private func dateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: date)
    }

    var body: some View {
        List {
            Section(header: Text("Current Pay Period").font(.headline)) {
                let pp = OddPayPeriodCalc.period(containing: store.weekStart)
                LabeledContent("Start") { Text(dateString(pp.start)) }
                LabeledContent("End") { Text(dateString(pp.end)) }
                LabeledContent("Pay Period #") { Text("\(pp.numberOdd)") }
            }

            Section(header: Text("Previous Pay Period").font(.headline)) {
                let curr = OddPayPeriodCalc.period(containing: store.weekStart)
                let prevRef = Calendar.current.date(byAdding: .day, value: -14, to: curr.start) ?? curr.start
                let prev = OddPayPeriodCalc.period(containing: prevRef)
                LabeledContent("Start") { Text(dateString(prev.start)) }
                LabeledContent("End") { Text(dateString(prev.end)) }
                LabeledContent("Pay Period #") { Text("\(prev.numberOdd)") }
            }

            // Adjustments
            Section(header: Text("Adjust").font(.headline)) {
                DatePicker(
                    "Start Date",
                    selection: Binding(
                        get: { store.weekStart },
                        set: { store.weekStart = Calendar.current.startOfDay(for: $0) }
                    ),
                    displayedComponents: [.date]
                )

                Picker("Weeks in Pay Period", selection: Binding(
                    get: { store.payPeriodWeeks },
                    set: { store.payPeriodWeeks = $0 }
                )) {
                    Text("Week 1").tag(1)
                    Text("Week 1 & Week 2").tag(2)
                    Text("Week 1, Week 2 & Week 3 & Week 4").tag(4)
                }

                Picker("Default Week", selection: Binding(
                    get: { min(store.selectedWeekIndex, max(0, store.payPeriodWeeks - 1)) },
                    set: { store.selectedWeekIndex = $0 }
                )) {
                    ForEach(0..<(max(1, store.payPeriodWeeks)), id: \.self) { idx in
                        Text("Week #\(idx+1)").tag(idx)
                    }
                }

                Toggle("Auto Stat Holidays", isOn: Binding(
                    get: { store.autoHolidaysEnabled },
                    set: { store.autoHolidaysEnabled = $0 }
                ))
            }

            Section {
                Button {
                    let cal = Calendar.current
                    let now = Date()
                    let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
                    let startOfWeek = cal.date(from: comps).map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: now)
                    store.weekStart = startOfWeek
                    let bc = OddPayPeriodCalc.period(containing: startOfWeek)
                    store.payPeriodNumber = bc.numberOdd
                } label: {
                    Label("Jump to Current Pay Period", systemImage: "arrow.clockwise.circle")
                }
            }
        }
        .navigationTitle("Pay Period")
    }
}

#Preview {
    NavigationStack {
        PayPeriodSettingsView()
            .environmentObject(TimecardStore.sampleStore)
    }
}
