import SwiftUI

struct ICloudSettingsView: View {
    @AppStorage("icloudSyncEnabled") private var icloudSyncEnabled: Bool = false
    @AppStorage("appTheme") private var appThemeRaw: String = ThemeType.system.rawValue
    @AppStorage("accentColorHex") private var accentColorHex: String = ""

    var body: some View {
        List {
            Section(header: Text("iCloud").font(.headline)) {
                Toggle(isOn: $icloudSyncEnabled) {
                    Label("iCloud Sync", systemImage: "icloud")
                }
#if os(macOS)
                .toggleStyle(.switch)
#else
                .toggleStyle(.switch)
#endif

                Text("When enabled, your settings and templates sync between devices using your iCloud account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("What syncs").font(.headline)) {
                LabeledContent("Theme") {
                    Text(appThemeRaw.capitalized)
                }
                LabeledContent("Accent Color") {
                    Text(accentColorHex.isEmpty ? "System" : accentColorHex)
                }
                Text("Email settings and templates")
                Text("Jobs (names & numbers)")
                Text("Codes (labour codes list)")
            }

            Section(header: Text("Status").font(.headline)) {
                ICloudSyncStatusView()
            }
        }
        .navigationTitle("iCloud")
        .onAppear {
            if icloudSyncEnabled {
                UbiquitousSettingsSync.shared.start()
            }
        }
        .onChange(of: icloudSyncEnabled) { _, newValue in
            if newValue {
                UbiquitousSettingsSync.shared.start()
            }
        }
        .onChange(of: appThemeRaw) { _, newVal in
            if icloudSyncEnabled {
                UbiquitousSettingsSync.shared.pushTheme(appThemeRaw: newVal)
            }
        }
        .onChange(of: accentColorHex) { _, newVal in
            if icloudSyncEnabled {
                UbiquitousSettingsSync.shared.pushAccent(hex: newVal)
            }
        }
    }
}

#Preview {
    NavigationStack { ICloudSettingsView() }
}
