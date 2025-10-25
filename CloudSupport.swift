import Foundation
import SwiftData
import SwiftUI

// MARK: - CloudLog
/// Simple persistent log for cloud-related messages (diagnostics, errors, actions).
/// Stores a small rolling buffer in UserDefaults so it survives app relaunches.
@MainActor
enum CloudLog {
    private static let key = "cloudErrorLog"
    private static let maxEntries = 50

    /// Append a message with timestamp. Keeps the most recent `maxEntries`.
    static func append(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)"
        var arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        arr.append(line)
        if arr.count > maxEntries { arr.removeFirst(arr.count - maxEntries) }
        UserDefaults.standard.set(arr, forKey: key)
    }

    /// Returns the most recent messages (newest last).
    static func recent() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Clears all stored log messages.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - CloudActions
/// Convenience helpers for iCloud Key-Value Store and SwiftData content resets used by settings UI.
enum CloudActions {
    /// Triggers an immediate iCloud Key-Value Store sync.
    /// Returns true if synchronize() reported success.
    @discardableResult
    static func syncNow() -> Bool {
        let ok: Bool
        if UbiquitousSettingsSync.isAvailable {
            ok = NSUbiquitousKeyValueStore.default.synchronize()
        } else {
            ok = false
        }
        Task { @MainActor in
            CloudLog.append(ok ? "KVS synchronize() OK" : "KVS synchronize() SKIPPED")
        }
        return ok
    }

    /// Persists in-memory timecard history to SwiftData and saves the context to trigger CloudKit sync.
    /// Also performs a KVS synchronize. Returns a summary string.
    @MainActor
    static func syncAll(modelContext: ModelContext?, store: TimecardStore?) -> String {
        var parts: [String] = []

        // iCloud KVS: check account and sync if available
        var kvsSummary: String
        if UbiquitousSettingsSync.isAvailable {
            let kvs = NSUbiquitousKeyValueStore.default
            if let store {
                if let jobsData = try? JSONEncoder().encode(store.jobs),
                   let jobsJSON = String(data: jobsData, encoding: .utf8) {
                    kvs.set(jobsJSON, forKey: "jobsJSON")
                }
                if let labourData = try? JSONEncoder().encode(store.labourCodes),
                   let labourJSON = String(data: labourData, encoding: .utf8) {
                    kvs.set(labourJSON, forKey: "labourCodesJSON")
                }
                kvs.set(UserDefaults.standard.string(forKey: "emailSubjectTemplate") ?? "", forKey: "emailSubjectTemplate")
                kvs.set(UserDefaults.standard.string(forKey: "emailBodyTemplate") ?? "", forKey: "emailBodyTemplate")
            }
            var ok = kvs.synchronize()
            if !ok { Thread.sleep(forTimeInterval: 0.2); ok = kvs.synchronize() }
            kvsSummary = ok ? "KVS sync=OK" : "KVS sync=FAILED"
        } else {
            kvsSummary = "KVS sync=SKIPPED (no iCloud account)"
        }
        parts.append(kvsSummary)

        // Persist in-memory store to SwiftData if available
        if let store {
            store.persistCurrentDataToSwiftData()
            parts.append("Persisted TimecardStore → SwiftData")
        } else {
            parts.append("No TimecardStore available")
        }

        // Save SwiftData context to flush changes to CloudKit
        if let ctx = modelContext {
            do {
                try ctx.save()
                parts.append("SwiftData save=OK")
            } catch {
                parts.append("SwiftData save failed: \(error.localizedDescription)")
            }
        } else {
            parts.append("No ModelContext available")
        }

        let summary = parts.joined(separator: "; ")
        CloudLog.append("Sync All: \(summary)")
        return summary
    }

    /// Clears all keys in iCloud KVS and deletes all SwiftData records for known models.
    /// This is a "soft reset" to rebuild from scratch on next launch; it does not purge
    /// CloudKit zones directly (SwiftData manages those). Returns a human-readable summary.
    @MainActor
    static func resetCloud(modelContext: ModelContext?) -> String {
        var messages: [String] = []

        if UbiquitousSettingsSync.isAvailable {
            let kvs = NSUbiquitousKeyValueStore.default
            let keys = Array(kvs.dictionaryRepresentation.keys)
            for k in keys { kvs.removeObject(forKey: k) }
            let kvsOK = kvs.synchronize()
            messages.append("Cleared \(keys.count) KVS keys (sync=\(kvsOK ? "OK" : "FAILED"))")
        } else {
            messages.append("KVS reset skipped (no iCloud account)")
        }

        // 2) Delete SwiftData objects locally (EntryModel, LabourCodeModel)
        if let ctx = modelContext {
            do {
                let entries = try ctx.fetch(FetchDescriptor<EntryModel>())
                let labour = try ctx.fetch(FetchDescriptor<LabourCodeModel>())
                entries.forEach { ctx.delete($0) }
                labour.forEach { ctx.delete($0) }
                try ctx.save()
                messages.append("Deleted SwiftData: \(entries.count) EntryModel, \(labour.count) LabourCodeModel")
            } catch {
                messages.append("SwiftData delete failed: \(error.localizedDescription)")
            }
        } else {
            messages.append("No ModelContext available; skipped SwiftData delete")
        }

        let summary = messages.joined(separator: "; ")
        CloudLog.append("Reset iCloud Database: \(summary)")
        return summary
    }
}

