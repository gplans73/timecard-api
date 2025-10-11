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
            // Current pay period info
            Section(header: Text("Current Pay Period").font(.headline)) {
                LabeledContent("Start") { Text(dateString(store.payPeriodRange.lowerBound)) }
                LabeledContent("End") { Text(dateString(store.payPeriodRange.upperBound)) }
                LabeledContent("Pay Period #") {
                    Stepper(value: Binding(
                        get: { store.payPeriodNumber },
                        set: { store.payPeriodNumber = $0 }
                    ), in: 1...30) {
                        Text("\(store.payPeriodNumber)")
                    }
                }
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
                    let weekOfYear = cal.component(.weekOfYear, from: startOfWeek)
                    store.payPeriodNumber = (weekOfYear / 2) + 1
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
