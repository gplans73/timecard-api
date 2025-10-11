import SwiftUI

struct OnCallSettingsView: View {
    @EnvironmentObject var store: TimecardStore

    var body: some View {
        List {
            Section(header: Text("On Call").font(.headline)) {
                Toggle(isOn: Binding(
                    get: { store.onCallEnabled },
                    set: { store.onCallEnabled = $0 }
                )) {
                    Label("Enable On Call", systemImage: "phone.badge.plus")
                }
#if os(macOS)
                .toggleStyle(.switch)
#else
                .toggleStyle(.switch)
#endif

                Text("When disabled, entries marked as On Call are treated as regular time and On Call amounts are hidden in summaries.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("On Call")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        OnCallSettingsView()
            .environmentObject(TimecardStore.sampleStore)
    }
}
