import Foundation
import SwiftUI

/// Simple iCloud KVS sync helper for a few lightweight settings.
/// iOS 17+
final class UbiquitousSettingsSync {
    static let shared = UbiquitousSettingsSync()
    private let kvs = NSUbiquitousKeyValueStore.default

    // Keys we mirror
    private enum Key: String, CaseIterable {
        case appTheme
        case accentColorHex
        case emailRecipients // comma-separated
        case emailSubjectTemplate
        case emailBodyTemplate
    }

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvsChanged(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs
        )
    }

    func start() {
        kvs.synchronize()
        // Pull once on start to ensure local defaults match cloud
        applyFromCloud()
    }

    // MARK: - Push

    func pushTheme(appThemeRaw: String) {
        kvs.set(appThemeRaw, forKey: Key.appTheme.rawValue)
        kvs.synchronize()
    }

    func pushAccent(hex: String) {
        kvs.set(hex, forKey: Key.accentColorHex.rawValue)
        kvs.synchronize()
    }

    func pushEmail(recipients: [String], subjectTemplate: String?, bodyTemplate: String?) {
        kvs.set(recipients.joined(separator: ","), forKey: Key.emailRecipients.rawValue)
        if let subjectTemplate { kvs.set(subjectTemplate, forKey: Key.emailSubjectTemplate.rawValue) }
        if let bodyTemplate { kvs.set(bodyTemplate, forKey: Key.emailBodyTemplate.rawValue) }
        kvs.synchronize()
    }

    // MARK: - Pull/apply
    @objc private func kvsChanged(_ note: Notification) { applyFromCloud() }

    private func applyFromCloud() {
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
}
