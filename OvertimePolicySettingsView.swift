import Combine
import SwiftUI

enum OvertimePolicyOption: String, CaseIterable, Identifiable {
    case canadaBC8_12 = "Canada BC 8/12"
    case usWeekly40 = "US Weekly 40"
    case custom = "Custom"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .canadaBC8_12:
            return "Overtime after 8 hours per day, double time after 12 hours per day"
        case .usWeekly40:
            return "Overtime after 40 hours per week"
        case .custom:
            return "Define your own overtime thresholds"
        }
    }

    var thresholdsDescription: String {
        switch self {
        case .canadaBC8_12:
            return "Overtime after 8 hours, double time after 12 hours per day"
        case .usWeekly40:
            return "Overtime after 40 hours per week"
        case .custom:
            return "Custom thresholds"
        }
    }
}

enum OvertimeCountry: String, CaseIterable, Identifiable {
    case canada = "Canada"
    case unitedStates = "United States"
    var id: String { rawValue }
}

enum CanadianProvince: String, CaseIterable, Identifiable {
    case alberta = "Alberta"
    case britishColumbia = "British Columbia"
    case manitoba = "Manitoba"
    case newBrunswick = "New Brunswick"
    case newfoundlandAndLabrador = "Newfoundland and Labrador"
    case northwestTerritories = "Northwest Territories"
    case novScotia = "Nova Scotia"
    case nunavut = "Nunavut"
    case ontario = "Ontario"
    case princeEdwardIsland = "Prince Edward Island"
    case quebec = "Quebec"
    case saskatchewan = "Saskatchewan"
    case yukon = "Yukon"
    var id: String { rawValue }

    var overtimePolicy: OvertimePolicyOption {
        switch self {
        case .alberta, .britishColumbia, .manitoba, .ontario, .saskatchewan:
            return .canadaBC8_12
        case .quebec:
            return .usWeekly40
        default:
            return .canadaBC8_12
        }
    }
}

enum USState: String, CaseIterable, Identifiable {
    case alabama = "Alabama"
    case alaska = "Alaska"
    case arizona = "Arizona"
    case arkansas = "Arkansas"
    case california = "California"
    case colorado = "Colorado"
    case connecticut = "Connecticut"
    case delaware = "Delaware"
    case florida = "Florida"
    case georgia = "Georgia"
    case hawaii = "Hawaii"
    case idaho = "Idaho"
    case illinois = "Illinois"
    case indiana = "Indiana"
    case iowa = "Iowa"
    case kansas = "Kansas"
    case kentucky = "Kentucky"
    case louisiana = "Louisiana"
    case maine = "Maine"
    case maryland = "Maryland"
    case massachusetts = "Massachusetts"
    case michigan = "Michigan"
    case minnesota = "Minnesota"
    case mississippi = "Mississippi"
    case missouri = "Missouri"
    case montana = "Montana"
    case nebraska = "Nebraska"
    case nevada = "Nevada"
    case newHampshire = "New Hampshire"
    case newJersey = "New Jersey"
    case newMexico = "New Mexico"
    case newYork = "New York"
    case northCarolina = "North Carolina"
    case northDakota = "North Dakota"
    case ohio = "Ohio"
    case oklahoma = "Oklahoma"
    case oregon = "Oregon"
    case pennsylvania = "Pennsylvania"
    case rhodeIsland = "Rhode Island"
    case southCarolina = "South Carolina"
    case southDakota = "South Dakota"
    case tennessee = "Tennessee"
    case texas = "Texas"
    case utah = "Utah"
    case vermont = "Vermont"
    case virginia = "Virginia"
    case washington = "Washington"
    case westVirginia = "West Virginia"
    case wisconsin = "Wisconsin"
    case wyoming = "Wyoming"
    case districtOfColumbia = "District of Columbia"
    var id: String { rawValue }

    var overtimePolicy: OvertimePolicyOption {
        switch self {
        case .california, .alaska:
            return .canadaBC8_12
        default:
            return .usWeekly40
        }
    }
}

final class OvertimeSettingsStore: ObservableObject {
    @Published var overtimePolicy: OvertimePolicyOption = .canadaBC8_12
    @Published var selectedCountry: OvertimeCountry = .canada
    @Published var selectedProvince: CanadianProvince = .britishColumbia
    @Published var selectedState: USState = .california

    @AppStorage("customDailyOTThreshold") var customDailyOTThreshold: Double = 8
    @AppStorage("customDailyDTThreshold") var customDailyDTThreshold: Double = 12
    @AppStorage("customWeeklyOTThreshold") var customWeeklyOTThreshold: Double = 40

    @AppStorage("selectedCountry") var selectedCountryRaw: String = OvertimeCountry.canada.rawValue
    @AppStorage("selectedProvince") var selectedProvinceRaw: String = CanadianProvince.britishColumbia.rawValue
    @AppStorage("selectedState") var selectedStateRaw: String = USState.california.rawValue

    // Additional custom overtime properties for the new UI:
    @Published var useCustomOvertimePolicy: Bool = false
    @Published var customRegularHours: Double = 8
    @Published var customOvertimeHours: Double = 8
    @Published var customDoubleTimeAfter: Double = 12

    init() {
        selectedCountry = OvertimeCountry(rawValue: selectedCountryRaw) ?? .canada
        selectedProvince = CanadianProvince(rawValue: selectedProvinceRaw) ?? .britishColumbia
        selectedState = USState(rawValue: selectedStateRaw) ?? .california
        updatePolicyFromRegion()
    }

    func updatePolicyFromRegion() {
        switch selectedCountry {
        case .canada: overtimePolicy = selectedProvince.overtimePolicy
        case .unitedStates: overtimePolicy = selectedState.overtimePolicy
        }
    }
}

struct OvertimePolicySelectorView: View {
    @EnvironmentObject var timecardStore: TimecardStore
    @EnvironmentObject var holidayManager: HolidayManager

    @State private var regText: String = ""
    @State private var otText: String = ""
    @State private var dtText: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 1) Current policy summary
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select Overtime Policy")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Policy is automatically set based on your selected region below.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Policy:")
                                .font(.subheadline).fontWeight(.medium)
                            Text(policySummary(timecardStore.overtimePolicy))
                                .font(.body)
                            Divider().padding(.vertical, 6)
                            Toggle(isOn: Binding(
                                get: { timecardStore.useCustomOvertimePolicy },
                                set: { newVal in
                                    timecardStore.useCustomOvertimePolicy = newVal
                                    if newVal {
                                        timecardStore.overtimePolicy = OvertimePolicy(
                                            dailyRegularCap: timecardStore.customRegularHours,
                                            dailyOTCap: timecardStore.customDoubleTimeAfter,
                                            weeklyRegularCap: holidayManager.inferredOvertimePolicy().weeklyRegularCap
                                        )
                                        regText = String(format: "%g", timecardStore.customRegularHours)
                                        otText = String(format: "%g", timecardStore.customOvertimeHours)
                                        dtText = String(format: "%g", timecardStore.customDoubleTimeAfter)
                                    } else {
                                        timecardStore.overtimePolicy = holidayManager.inferredOvertimePolicy()
                                    }
                                }
                            )) {
                                Text("Use custom thresholds")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #else
                            .toggleStyle(.switch)
                            #endif

                            if timecardStore.useCustomOvertimePolicy {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Regular up to (h)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            TextField("8", text: Binding(
                                                get: { regText },
                                                set: { newVal in
                                                    regText = newVal
                                                    if let v = Double(newVal.replacingOccurrences(of: ",", with: ".")) {
                                                        timecardStore.customRegularHours = max(0, v)
                                                        timecardStore.overtimePolicy = OvertimePolicy(
                                                            dailyRegularCap: timecardStore.customRegularHours,
                                                            dailyOTCap: timecardStore.customDoubleTimeAfter,
                                                            weeklyRegularCap: holidayManager.inferredOvertimePolicy().weeklyRegularCap
                                                        )
                                                    }
                                                }
                                            ))
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(maxWidth: 120)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("OT after (h)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            TextField("8", text: Binding(
                                                get: { otText },
                                                set: { newVal in
                                                    otText = newVal
                                                    if let v = Double(newVal.replacingOccurrences(of: ",", with: ".")) {
                                                        timecardStore.customOvertimeHours = max(0, v)
                                                        // Note: policy currently derives OT between regular and DT thresholds; keeping this for future use.
                                                    }
                                                }
                                            ))
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(maxWidth: 120)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("DT after (h)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            TextField("12", text: Binding(
                                                get: { dtText },
                                                set: { newVal in
                                                    dtText = newVal
                                                    if let v = Double(newVal.replacingOccurrences(of: ",", with: ".")) {
                                                        timecardStore.customDoubleTimeAfter = max(timecardStore.customRegularHours, v)
                                                        timecardStore.overtimePolicy = OvertimePolicy(
                                                            dailyRegularCap: timecardStore.customRegularHours,
                                                            dailyOTCap: timecardStore.customDoubleTimeAfter,
                                                            weeklyRegularCap: holidayManager.inferredOvertimePolicy().weeklyRegularCap
                                                        )
                                                    }
                                                }
                                            ))
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(maxWidth: 120)
                                        }
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                                    Text("Your custom thresholds override the region’s daily limits. Weekly limits still come from the selected region.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
                    )

                    // 2) Region selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select Your Region")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Choose your country and province/state to automatically set the appropriate overtime rules.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        // Country
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Country").font(.subheadline).fontWeight(.medium)
                            Picker("Country", selection: Binding(
                                get: { holidayManager.selectedCountry },
                                set: { holidayManager.selectedCountry = $0 }
                            )) {
                                ForEach(TimecardCountry.allCases, id: \.self) { c in
                                    Text(c.displayName).tag(c)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // Province / State
                        if holidayManager.selectedCountry == .canada {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Province/Territory").font(.subheadline).fontWeight(.medium)
                                Picker("Province", selection: Binding(
                                    get: { holidayManager.selectedProvince },
                                    set: { holidayManager.selectedProvince = $0 }
                                )) {
                                    ForEach(Province.allCases, id: \.self) { p in
                                        Text(p.displayName).tag(p)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("State").font(.subheadline).fontWeight(.medium)
                                Picker("State", selection: Binding(
                                    get: { holidayManager.selectedState },
                                    set: { holidayManager.selectedState = $0 }
                                )) {
                                    ForEach(TimecardUSState.allCases, id: \.self) { s in
                                        Text(s.displayName).tag(s)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )

                    // 3) Overtime rules explanation (relocated section)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Overtime Rules for Selected Region")
                            .font(.title2)
                            .fontWeight(.semibold)
                        ScrollView {
                            Text(holidayManager.overtimeRulesExplanation)
                                .font(.body)
                                .padding()
                        }
                        .frame(minHeight: 200, maxHeight: 300)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemBackground))
                        )
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                    )
                }
                .padding()
                .onAppear {
                    regText = String(format: "%g", timecardStore.customRegularHours)
                    otText = String(format: "%g", timecardStore.customOvertimeHours)
                    dtText = String(format: "%g", timecardStore.customDoubleTimeAfter)
                }
                .onReceive(NotificationCenter.default.publisher(for: .regionDidChange)) { _ in
                    if timecardStore.useCustomOvertimePolicy {
                        timecardStore.overtimePolicy = OvertimePolicy(
                            dailyRegularCap: timecardStore.customRegularHours,
                            dailyOTCap: timecardStore.customDoubleTimeAfter,
                            weeklyRegularCap: holidayManager.inferredOvertimePolicy().weeklyRegularCap
                        )
                    } else {
                        timecardStore.overtimePolicy = holidayManager.inferredOvertimePolicy()
                    }
                }
            }
            .navigationTitle("Overtime Policy")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func policySummary(_ p: OvertimePolicy) -> String {
        if let wk = p.weeklyRegularCap, p.dailyRegularCap == nil, p.dailyOTCap == nil {
            return "Weekly OT after \(Int(wk))h"
        }
        let reg = p.dailyRegularCap ?? 0
        let otCap = p.dailyOTCap ?? reg
        if p.dailyRegularCap != nil && p.dailyOTCap != nil {
            return "Daily: OT after \(Int(reg))h, DT after \(Int(otCap))h"
        }
        if p.dailyRegularCap != nil {
            return "Daily OT after \(Int(reg))h"
        }
        return "Custom"
    }
}

struct OvertimePolicySelectorView_Previews: PreviewProvider {
    static var previews: some View {
        OvertimePolicySelectorView()
            .environmentObject(TimecardStore.sampleStore)
            .frame(width: 350)
    }
}
