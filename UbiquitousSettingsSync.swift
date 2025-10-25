import Foundation
import SwiftUI

/// Simple iCloud KVS sync helper for a few lightweight settings.
/// iOS 17+
final class UbiquitousSettingsSync {
    /// Global toggle to enable iCloud KVS integration. Leave false to avoid entitlement warnings.
    static var enabled: Bool = false
    private static var kvsReady: Bool = false

    static let shared = UbiquitousSettingsSync()
    private var kvs: NSUbiquitousKeyValueStore { NSUbiquitousKeyValueStore.default }

    static var isAvailable: Bool {
        enabled && kvsReady && FileManager.default.ubiquityIdentityToken != nil
    }

    // Keys we mirror
    private enum Key: String, CaseIterable {
        case appTheme
        case accentColorHex
        case emailRecipients // comma-separated
        case emailSubjectTemplate
        case emailBodyTemplate
        case toolbarButtonsB64
    }

    private init() {
        if Self.isAvailable {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(kvsChanged(_:)),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: kvs
            )
        }
    }

    func start() {
        // Probe KVS availability. This also fails gracefully when the KVS entitlement is missing.
        Self.kvsReady = NSUbiquitousKeyValueStore.default.synchronize()
        guard UbiquitousSettingsSync.enabled, FileManager.default.ubiquityIdentityToken != nil, Self.kvsReady else { return }
        kvs.synchronize()
        // Pull once on start to ensure local defaults match cloud
        applyFromCloud()
        if let localTB = UserDefaults.standard.data(forKey: "toolbarButtons"), !localTB.isEmpty {
            pushToolbarButtons(data: localTB)
        }
    }

    // MARK: - Push

    func pushTheme(appThemeRaw: String) {
        guard UbiquitousSettingsSync.enabled, Self.kvsReady else { return }
        kvs.set(appThemeRaw, forKey: Key.appTheme.rawValue)
        kvs.synchronize()
    }

    func pushAccent(hex: String) {
        guard UbiquitousSettingsSync.enabled, Self.kvsReady else { return }
        kvs.set(hex, forKey: Key.accentColorHex.rawValue)
        kvs.synchronize()
    }

    func pushEmail(recipients: [String], subjectTemplate: String?, bodyTemplate: String?) {
        guard UbiquitousSettingsSync.enabled, Self.kvsReady else { return }
        kvs.set(recipients.joined(separator: ","), forKey: Key.emailRecipients.rawValue)
        if let subjectTemplate { kvs.set(subjectTemplate, forKey: Key.emailSubjectTemplate.rawValue) }
        if let bodyTemplate { kvs.set(bodyTemplate, forKey: Key.emailBodyTemplate.rawValue) }
        kvs.synchronize()
    }

    func pushToolbarButtons(data: Data) {
        guard UbiquitousSettingsSync.enabled, Self.kvsReady else { return }
        let b64 = data.base64EncodedString()
        kvs.set(b64, forKey: Key.toolbarButtonsB64.rawValue)
        kvs.synchronize()
    }

    // MARK: - Pull/apply
    @objc private func kvsChanged(_ note: Notification) { applyFromCloud() }

    private func applyFromCloud() {
        guard UbiquitousSettingsSync.enabled, Self.kvsReady else { return }
        // Theme
        if let theme = kvs.string(forKey: Key.appTheme.rawValue) {
            UserDefaults.standard.set(theme, forKey: "appTheme")
        }
        if let hex = kvs.string(forKey: Key.accentColorHex.rawValue) {
            UserDefaults.standard.set(hex, forKey: "accentColorHex")
        }
        // Email templates
        if let rec = kvs.string(forKey: Key.emailRecipients.rawValue) {
            let list = rec.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            UserDefaults.standard.set(list, forKey: "emailRecipients")
        }
        if let subj = kvs.string(forKey: Key.emailSubjectTemplate.rawValue) {
            UserDefaults.standard.set(subj, forKey: "emailSubjectTemplate")
        }
        if let body = kvs.string(forKey: Key.emailBodyTemplate.rawValue) {
            UserDefaults.standard.set(body, forKey: "emailBodyTemplate")
        }
        if let b64 = kvs.string(forKey: Key.toolbarButtonsB64.rawValue), let data = Data(base64Encoded: b64) {
            UserDefaults.standard.set(data, forKey: "toolbarButtons")
        }
    }
}

// MARK: - Convenience property wrappers for views/stores to call push
extension View {
    func syncAppTheme(_ themeRaw: String) {
        UbiquitousSettingsSync.shared.pushTheme(appThemeRaw: themeRaw)
    }
    func syncAccent(_ hex: String) {
        UbiquitousSettingsSync.shared.pushAccent(hex: hex)
    }
    func syncEmail(recipients: [String], subjectTemplate: String?, bodyTemplate: String?) {
        UbiquitousSettingsSync.shared.pushEmail(recipients: recipients, subjectTemplate: subjectTemplate, bodyTemplate: bodyTemplate)
    }
    func syncToolbarButtons(_ data: Data) {
        UbiquitousSettingsSync.shared.pushToolbarButtons(data: data)
    }
}
