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

final class OvertimeSettingsStore: ObservableObject {
    @Published var overtimePolicy: OvertimePolicyOption = .canadaBC8_12

    // Persist custom thresholds so user settings survive app restarts
    @AppStorage("customDailyOTThreshold") var customDailyOTThreshold: Double = 8
    @AppStorage("customDailyDTThreshold") var customDailyDTThreshold: Double = 12
    @AppStorage("customWeeklyOTThreshold") var customWeeklyOTThreshold: Double = 40
}

struct OvertimePolicySelectorView: View {
    @EnvironmentObject var store: OvertimeSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Select Overtime Policy")
                .font(.headline)

            Picker("Overtime Policy", selection: $store.overtimePolicy) {
                ForEach(OvertimePolicyOption.allCases) { policy in
                    Text(policy.rawValue).tag(policy)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text("Thresholds:")
                    .font(.subheadline)
                    .bold()
                Text(store.overtimePolicy.thresholdsDescription)
                    .font(.body)
                    .foregroundColor(store.overtimePolicy == .custom ? .secondary : .primary)

                if store.overtimePolicy == .custom {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Daily OT after (hours)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("8", value: $store.customDailyOTThreshold, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Daily DT after (hours)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("12", value: $store.customDailyDTThreshold, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Weekly OT after (hours)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("40", value: $store.customWeeklyOTThreshold, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text("Set any fields you need. Leave a value as 0 if your policy doesn't use it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        {
#if os(iOS)
                            Color(UIColor.secondarySystemBackground)
#else
                            Color.secondary.opacity(0.12)
#endif
                        }(), in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
            }
        }
        .padding()
        .onChange(of: store.customDailyOTThreshold) { _, newVal in
            if newVal < 0 { store.customDailyOTThreshold = 0 }
        }
        .onChange(of: store.customDailyDTThreshold) { _, newVal in
            if newVal < 0 { store.customDailyDTThreshold = 0 }
        }
        .onChange(of: store.customWeeklyOTThreshold) { _, newVal in
            if newVal < 0 { store.customWeeklyOTThreshold = 0 }
        }
    }
}

struct OvertimePolicySelectorView_Previews: PreviewProvider {
    static var previews: some View {
        let store = OvertimeSettingsStore()
        store.overtimePolicy = .custom
        return OvertimePolicySelectorView()
            .environmentObject(store)
            .frame(width: 350)
    }
}
