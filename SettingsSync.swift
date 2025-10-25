import Foundation
import Combine

/// Simple settings synchronization helper.
/// Currently uses iCloud KVS (NSUbiquitousKeyValueStore) to keep settings in sync.
final class SettingsSync {
    static let shared = SettingsSync()

    private var observation: AnyCancellable?
    private var kvs: NSUbiquitousKeyValueStore { NSUbiquitousKeyValueStore.default }

    private init() {}

    /// Start syncing settings. Safe to call multiple times.
    func start() {
        guard UbiquitousSettingsSync.isAvailable else { return }

        // Attempt an initial sync
        _ = kvs.synchronize()

        // Observe changes pushed from iCloud KVS
        observation = NotificationCenter.default
            .publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kvs)
            .sink { notification in
                // Handle incoming changes as needed. For now, we just resync.
                _ = self.kvs.synchronize()
                // You can inspect notification.userInfo for changed keys and reasons.
                // print("[SettingsSync] KVS change: \(notification.userInfo ?? [:])")
            }
    }

    /// Stop syncing and tear down observers.
    func stop() {
        observation?.cancel()
        observation = nil
    }
}
