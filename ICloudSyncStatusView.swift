import SwiftUI
import Network
import SwiftData

/// Lightweight status indicators for iCloud KVS syncing.
/// - Account: shows whether an iCloud account appears available to the app
/// - Connection: shows basic internet reachability
/// - Quota: approximate remaining size for KVS payload (1 MB total)
struct ICloudSyncStatusView: View {
    @State private var isSignedIn: Bool = false
    @State private var isOnline: Bool = true
    @State private var kvsBytesUsed: Int = 0

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: TimecardStore
    @State private var isBusy: Bool = false
    @State private var alertMessage: String? = nil
    @State private var log: [String] = []

    private let totalKVSBytes = 1_000_000 // NSUbiquitousKeyValueStore guideline ~1 MB
    private let monitor = NWPathMonitor()

    var body: some View {
        Section("Status") {
            statusRow(title: "Account", ok: isSignedIn)
            statusRow(title: "Connection", ok: isOnline)
            quotaRow()

            // Actions
            Button {
                isBusy = true
                let summary = CloudActions.syncAll(modelContext: modelContext, store: store)
                isBusy = false
                alertMessage = summary
                refreshQuota()
                reloadLog()
            } label: {
                Text("Sync Now").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)

            Button(role: .destructive) {
                isBusy = true
                let summary = CloudActions.resetCloud(modelContext: modelContext)
                isBusy = false
                alertMessage = summary
                refreshQuota()
                reloadLog()
            } label: {
                Text("Reset iCloud Database").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)
        }

        // Error Log section
        Section("Error Log") {
            if log.isEmpty {
                Text("No recent errors").foregroundStyle(.secondary)
            } else {
                ForEach(log.indices, id: \.self) { i in
                    Text(log[i]).font(.caption)
                }
                Button("Clear Log") {
                    CloudLog.clear()
                    reloadLog()
                }
            }
        }

        .alert("iCloud", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            refreshAccount()
            refreshQuota()
            startNetworkMonitoring()
            reloadLog()
        }
        .onDisappear { monitor.cancel() }
    }

    @ViewBuilder
    private func statusRow(title: String, ok: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: "circle.fill")
                .foregroundStyle(ok ? .green : .red)
                .font(.system(size: 12))
                .accessibilityLabel(ok ? "OK" : "Problem")
        }
    }

    @ViewBuilder
    private func quotaRow() -> some View {
        let remaining = max(0, totalKVSBytes - kvsBytesUsed)
        let ok = remaining > 50_000 // arbitrary comfort threshold
        HStack {
            Text("Quota")
            Spacer()
            Image(systemName: "circle.fill")
                .foregroundStyle(ok ? .green : .yellow)
                .font(.system(size: 12))
                .accessibilityLabel(ok ? "OK" : "Low")
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(remaining / 1_000) KB left")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func refreshAccount() {
        // If a ubiquityIdentityToken exists, the user is signed into iCloud for this device
        #if canImport(UIKit)
        isSignedIn = FileManager.default.ubiquityIdentityToken != nil
        #else
        isSignedIn = FileManager.default.ubiquityIdentityToken != nil
        #endif
    }

    private func refreshQuota() {
        let kvs = NSUbiquitousKeyValueStore.default
        var used = 0
        for (key, _) in kvs.dictionaryRepresentation {
            // Use JSON size approximation for each value
            if let value = kvs.object(forKey: key) {
                if let data = try? JSONSerialization.data(withJSONObject: value, options: []) {
                    used += data.count + key.utf8.count
                } else {
                    // Fallback: rough estimate for non-JSON-serializable values
                    used += key.utf8.count + 64
                }
            }
        }
        kvsBytesUsed = used
    }

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "ICloudSyncStatusView.Network"))
    }

    private func reloadLog() {
        self.log = CloudLog.recent()
    }
}

#Preview {
    NavigationStack {
        List {
            ICloudSyncStatusView()
        }
        .navigationTitle("iCloud Sync")
    }
}
