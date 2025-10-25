//
//  App.swift
//  Timecard
//
import SwiftUI
import SwiftData
import Combine
import CloudKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@main
struct TimecardApp: App {
    @StateObject private var store = TimecardStore()
    private let settingsSync = SettingsSync.shared

    #if os(iOS)
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    #endif

    // MARK: - Theme
    @AppStorage("appTheme") private var appThemeRaw: String = ThemeType.system.rawValue
    private var selectedTheme: ThemeType { ThemeType(rawValue: appThemeRaw) ?? .system }

    // MARK: - iCloud & Data Model
    private let modelContainer: ModelContainer
    private let iCloudContainerID: String

    init() {
        // Match the container configured under Signing & Capabilities
        iCloudContainerID = "iCloud.gstrench"

        // IMPORTANT: Avoid blocking launch on device by creating a cloud-backed container synchronously.
        // We initialize a local ModelContainer immediately to keep the main thread responsive.
        // If you want to enable CloudKit sync later, do it after launch and avoid blocking the UI.
        do {
            let cloudConfig = ModelConfiguration(
                cloudKitDatabase: .private(iCloudContainerID)
            )
            modelContainer = try ModelContainer(
                for: EntryModel.self, LabourCodeModel.self, JobModel.self,
                configurations: cloudConfig
            )
            print("[SwiftData] ✅ Using CloudKit-backed ModelContainer (\(iCloudContainerID))")
        } catch {
            print("[SwiftData] 💥 FATAL: Failed to create local ModelContainer: \(error)")
            print("[SwiftData] Error details: \(error.localizedDescription)")
            fatalError("Failed to create SwiftData ModelContainer (cloud)")
        }

        // NOTE: This build uses a CloudKit-backed container. Ensure the iCloud capability
        // is enabled and the container (iCloud.gstrench) exists in CloudKit Console.
    }

    // MARK: - Cloud Diagnostics
    private func runCloudDiagnostics() {
        // Enable diagnostics in Debug by default. To enable in other configs, add `-D CLOUD_DIAG` to Other Swift Flags.
        #if CLOUD_DIAG && !targetEnvironment(simulator)
        Task {
            // If there's no iCloud identity, skip CloudKit diagnostics to avoid noisy errors.
            guard FileManager.default.ubiquityIdentityToken != nil else {
                print("[CloudDiag] No iCloud identity. Skipping CloudKit diagnostics.")
                return
            }

            print("[CloudDiag] Using container identifier: \(iCloudContainerID)")
            
            // Safely attempt to create and check CloudKit container
            do {
                // Use the explicit container identifier derived in init.
                let container = CKContainer(identifier: iCloudContainerID)
                
                // Check account status asynchronously with timeout
                let (status, error) = await withCheckedContinuation { continuation in
                    container.accountStatus { status, error in
                        continuation.resume(returning: (status, error))
                    }
                }
                
                let statusDesc: String
                switch status {
                case .available: statusDesc = "AVAILABLE"
                case .noAccount: statusDesc = "NO ACCOUNT"
                case .restricted: statusDesc = "RESTRICTED"
                case .couldNotDetermine: statusDesc = "COULD NOT DETERMINE"
                case .temporarilyUnavailable: statusDesc = "TEMPORARILY UNAVAILABLE"
                @unknown default: statusDesc = "UNKNOWN CASE (raw: \(status.rawValue))"
                }
                
                if let error = error {
                    print("[CloudDiag] CloudKit account: \(statusDesc), error: \(error.localizedDescription)")
                } else {
                    print("[CloudDiag] CloudKit account: \(statusDesc)")
                }
                
            } catch {
                print("[CloudDiag] Failed to initialize CloudKit container: \(error.localizedDescription)")
                print("[CloudDiag] This usually means the container ID '\(iCloudContainerID)' doesn't exist in CloudKit Dashboard")
            }

            // iCloud KVS availability (separate from CloudKit)
            do {
                let ok = NSUbiquitousKeyValueStore.default.synchronize()
                print("[CloudDiag] iCloud KVS synchronize(): \(ok ? "OK" : "FAILED")")
            } catch {
                print("[CloudDiag] iCloud KVS error: \(error.localizedDescription)")
            }
        }
        #endif
    }

    // MARK: - Scene
    var body: some Scene {
        WindowGroup {
            MainContentView(store: store)
                .preferredColorScheme(selectedTheme.colorScheme)
                .modelContainer(modelContainer)
                .onAppear {
                    print("[App] Main window appeared; scheduling settings sync and diagnostics...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.settingsSync.start()
                        #if CLOUD_DIAG
                        self.runCloudDiagnostics()
                        #endif
                        print("[App] Settings sync started and diagnostics triggered")
                        #if os(iOS)
                        PushNotificationManager.registerForRemoteNotifications()
                        #endif
                    }
                }
        }
    }
}

// Inline replacement for BootstrapView to resolve the compilation error
struct MainContentView: View {
    @StateObject var store: TimecardStore
    @Environment(\.modelContext) private var modelContext

    init(store: TimecardStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        MainTabView()
            .environmentObject(store)
            .onAppear {
                if #available(iOS 17, macOS 14, *) {
                    store.attach(modelContext: modelContext)
                    // Defer holiday preload to avoid any potential launch hitches on device
                    Task.detached {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // ~1s
                        await store.preloadHolidaysForCurrentPeriod()
                        print("[App] Holiday preload completed")
                    }
                }
            }
    }
}

