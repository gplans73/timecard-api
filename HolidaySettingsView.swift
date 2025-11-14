import SwiftUI

struct HolidaySettingsView: View {
    @EnvironmentObject var store: TimecardStore
    
    var body: some View {
        List {
            Section(header: Text("Automatic Holidays")) {
                Toggle(isOn: Binding(
                    get: { store.autoHolidaysEnabled },
                    set: { store.autoHolidaysEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-add Stat Holidays")
                            .font(.headline)
                        Text("Automatically add statutory holidays to your timecard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("Location Settings")) {
                Picker("Country", selection: Binding(
                    get: { store.holidayManager.selectedCountry },
                    set: { store.holidayManager.selectedCountry = $0 }
                )) {
                    ForEach(TimecardCountry.allCases, id: \.self) { country in
                        Text(country.displayName).tag(country)
                    }
                }
                
                if store.holidayManager.selectedCountry == .canada {
                    Picker("Province", selection: Binding(
                        get: { store.holidayManager.selectedProvince },
                        set: { store.holidayManager.selectedProvince = $0 }
                    )) {
                        ForEach(Province.allCases, id: \.self) { province in
                            Text(province.displayName).tag(province)
                        }
                    }
                } else {
                    Picker("State", selection: Binding(
                        get: { store.holidayManager.selectedState },
                        set: { store.holidayManager.selectedState = $0 }
                    )) {
                        ForEach(TimecardUSState.allCases, id: \.self) { state in
                            Text(state.displayName).tag(state)
                        }
                    }
                }
            }
            
            Section(header: Text("Current Pay Period Holidays")) {
                let holidays = getCurrentPayPeriodHolidays()
                if holidays.isEmpty {
                    Text("No holidays in current pay period")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(holidays, id: \.id) { holiday in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(holiday.name)
                                    .font(.headline)
                                Text(holiday.date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if hasHolidayEntry(for: holiday.date) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Button("Add") {
                                    addHolidayEntry(holiday)
                                }
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("Actions")) {
                Button("Refresh Holidays for Current Period") {
                    store.addStatHolidaysForCurrentPeriod()
                }
                .foregroundColor(.accentColor)
            }
        }
        .navigationTitle("Stat Holidays")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func getCurrentPayPeriodHolidays() -> [StatHoliday] {
        let calendar = Calendar.current
        let payPeriodRange = store.payPeriodRange
        
        let startYear = calendar.component(.year, from: payPeriodRange.lowerBound)
        let endYear = calendar.component(.year, from: payPeriodRange.upperBound)
        
        var holidays: [StatHoliday] = []
        for year in startYear...endYear {
            holidays.append(contentsOf: store.holidayManager.getStatHolidays(for: year))
        }
        
        return holidays.filter { holiday in
            payPeriodRange.contains(holiday.date)
        }.sorted { $0.date < $1.date }
    }
    
    private func hasHolidayEntry(for date: Date) -> Bool {
        let calendar = Calendar.current
        return store.entries.contains { entry in
            calendar.isDate(entry.date, inSameDayAs: date) &&
            (entry.code.uppercased() == "H" || entry.code.uppercased() == "STAT")
        }
    }
    
    private func addHolidayEntry(_ holiday: StatHoliday) {
        let holidayEntry = Entry(
            date: holiday.date,
            jobNumber: "",
            code: "H",
            hours: 8.0,
            notes: holiday.name,
            isOvertime: false,
            isNightShift: false
        )
        store.entries.append(holidayEntry)
        store.entries.sort { $0.date < $1.date }
    }
}

#Preview {
    NavigationStack {
        HolidaySettingsView()
            .environmentObject(TimecardStore.sampleStore)
    }
}
