import SwiftUI
import Network
import SwiftData

/// Lightweight status indicators for iCloud KVS syncing.
/// - Account: shows whether an iCloud account appears available to the app
/// - Connection: shows basic internet reachability
/// - Quota: approximate remaining size for KVS payload (1 MB total)
/// - KVS: availability of NSUbiquitousKeyValueStore
struct ICloudSyncStatusView: View {
    @State private var isSignedIn: Bool = false
    @State private var isOnline: Bool = true
    @State private var kvsBytesUsed: Int = 0
    @State private var isKVSAvailable: Bool = true

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
            statusRow(title: "KVS", ok: isKVSAvailable)
            quotaRow()

            // Actions
            Button {
                isBusy = true
                let summary = CloudActions.syncAll(modelContext: modelContext, store: store)
                isBusy = false
                alertMessage = summary
                refreshQuota()
                refreshKVSAvailability()
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
                refreshKVSAvailability()
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
            refreshKVSAvailability()
            startNetworkMonitoring()
            reloadLog()
        }
        .onDisappear { monitor.cancel() }
    }

    private func refreshKVSAvailability() {
        // Use synchronize as a lightweight availability proxy
        // KVS is considered available when synchronize succeeds and account/network look OK
        let success = NSUbiquitousKeyValueStore.default.synchronize()
        self.isKVSAvailable = success && self.isSignedIn && self.isOnline
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
            // Center the text in a fixed trailing area so it doesn't collide with the status dot
            Text("\(remaining / 1_000) KB left")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .center)
            Image(systemName: "circle.fill")
                .foregroundStyle(ok ? .green : .yellow)
                .font(.system(size: 12))
                .accessibilityLabel(ok ? "OK" : "Low")
        }
    }

    private func refreshAccount() {
        // If a ubiquityIdentityToken exists, the user is signed into iCloud for this device
        #if canImport(UIKit)
        isSignedIn = FileManager.default.ubiquityIdentityToken != nil
        #else
        isSignedIn = FileManager.default.ubiquityIdentityToken != nil
        #endif
        refreshKVSAvailability()
    }

    private func kvsValueSize(_ value: Any) -> Int {
        // Safely approximate size for supported KVS types without risking Objective-C exceptions
        switch value {
        case let s as String:
            return s.utf8.count
        case let d as Data:
            return d.count
        case let n as NSNumber:
            // Approximate numeric storage; use 8 bytes for numbers/bools
            return 8
        case let arr as [Any]:
            // Sum of element sizes plus minimal separators
            return arr.reduce(2) { $0 + kvsValueSize($1) + 1 } // brackets + commas
        case let dict as [String: Any]:
            // Sum of key/value sizes plus minimal separators
            return dict.reduce(2) { partial, pair in
                let (k, v) = pair
                return partial + k.utf8.count + kvsValueSize(v) + 2 // quotes/colon/comma approx
            }
        case let date as Date:
            // Store ISO8601 string length approximation
            let iso = ISO8601DateFormatter().string(from: date)
            return iso.utf8.count
        default:
            // Fallback for unsupported types
            return 64
        }
    }

    private func refreshQuota() {
        let kvs = NSUbiquitousKeyValueStore.default
        var used = 0
        for (key, value) in kvs.dictionaryRepresentation {
            used += key.utf8.count
            used += kvsValueSize(value)
        }
        kvsBytesUsed = used
    }

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isOnline = path.status == .satisfied
                self.refreshKVSAvailability()
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
