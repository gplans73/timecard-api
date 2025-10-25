import Foundation
import UserNotifications
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Centralized helper to request notification authorization and register for APNs.
/// Call `PushNotificationManager.registerForRemoteNotifications()` on app launch (recommended)
/// or when enabling cloud sync so the app can receive CloudKit/SwiftData pushes.
@MainActor
enum PushNotificationManager {
    /// Request user authorization for alerts/badges/sounds (optional for silent pushes)
    /// and register with APNs.
    static func registerForRemoteNotifications() {
        #if canImport(UIKit)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            // Request authorization only if not determined. Silent pushes do not require user auth,
            // but requesting helps if you plan to show alerts or badges.
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    if let error {
                        Task { @MainActor in
                            CloudLog.append("Push auth error: \(error.localizedDescription)")
                        }
                    }
                    Task { @MainActor in
                        CloudLog.append("Push auth granted=\(granted)")
                    }
                    DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
                }
            } else {
                // Already determined; just register for remote notifications
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
        #else
        // Non-UIKit platforms: no-op
        #endif
    }
}

#if canImport(UIKit)
/// App delegate shim to surface APNs registration results to the log.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        CloudLog.append("APNs device token: \(token.prefix(16))…")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        CloudLog.append("APNs registration failed: \(error.localizedDescription)")
    }
}
#endif

