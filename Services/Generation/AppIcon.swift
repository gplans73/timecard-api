import UIKit
import SwiftUI

enum AppIcon: String, CaseIterable {

    case primary
    case Applcon = "Applcon"
    case Applcon2 = "Applcon2"
    case Applcon3 = "Applcon3"
    case Applcon4 = "Applcon4"
    case Applcon5 = "Applcon5"
    case Applcon6 = "Applcon6"
    case Applcon7 = "Applcon7"
    case Applcon8 = "Applcon8"
    
    
    var iconName: String? {
        switch self {
        case .primary:
            return nil // nil = primary icon
        default:
            return rawValue
        }
    }
    var displayName: String {
        switch self {
        case .primary:
            return "Default"
        default:
            return rawValue
        }
    }
    
    var previewImage: String {
        switch self {
        case .primary:
            return "AppIcon"
        case .Applcon:
            return "Applcon"  // Use consistent naming
        case .Applcon2:
            return "Applcon2"
        case .Applcon3:
            return "Applcon3"
        case .Applcon4:
            return "Applcon4"
        case .Applcon5:
            return "Applcon5"
        case .Applcon6:
            return "Applcon6"
        case .Applcon7:
            return "Applcon7"
        case .Applcon8:
            return "Applcon8"
        }
    }
}

class AppIconManager {
    static let shared = AppIconManager()
    
    private init() {}
    
    var currentIcon: AppIcon {
        guard let iconName = UIApplication.shared.alternateIconName else {
            return .primary
        }
        return AppIcon(rawValue: iconName) ?? .primary
    }
    
    func setIcon(_ icon: AppIcon, completion: ((Bool) -> Void)? = nil) {
        print("🔧 AppIconManager: Attempting to set icon to \(icon.displayName)")
        print("🔧 Icon name for system: \(icon.iconName ?? "nil (primary)")")
        print("🔧 Supports alternate icons: \(UIApplication.shared.supportsAlternateIcons)")
        print("🔧 Current alternate icon name: \(UIApplication.shared.alternateIconName ?? "nil")")
        
        guard UIApplication.shared.supportsAlternateIcons else {
            print("❌ Device doesn't support alternate icons")
            completion?(false)
            return
        }
        
        // Check if the asset exists
        if let iconName = icon.iconName, UIImage(named: iconName) == nil {
            print("⚠️ Warning: Icon asset '\(iconName)' not found in bundle")
        }
        
        UIApplication.shared.setAlternateIconName(icon.iconName) { error in
            if let error = error {
                print("❌ Error setting alternate icon: \(error.localizedDescription)")
                print("❌ Error details: \(error)")
                completion?(false)
            } else {
                print("✅ Successfully set icon to \(icon.displayName)")
                print("✅ Current icon name is now: \(UIApplication.shared.alternateIconName ?? "nil")")
                completion?(true)
            }
        }
    }
    
    /// Validate that all icon assets exist
    func validateIconAssets() -> [String] {
        var missingAssets: [String] = []
        
        // Check primary icon
        if UIImage(named: "AppIcon") == nil {
            missingAssets.append("AppIcon")
        }
        
        // Check alternate icons
        for icon in AppIcon.allCases where icon != .primary {
            if let iconName = icon.iconName, UIImage(named: iconName) == nil {
                missingAssets.append(iconName)
            }
        }
        
        return missingAssets
    }
    
    /// Diagnostic function to check Icon configuration
    func diagnoseIconConfiguration() {
        print("\n📋 APP ICON DIAGNOSTIC REPORT")
        print(String(repeating: "=", count: 50))
        
        // Check device support
        print("Device Support:")
        print("  Supports alternate icons: \(UIApplication.shared.supportsAlternateIcons)")
        print("  Current alternate icon: \(UIApplication.shared.alternateIconName ?? "nil (using primary)")")
        
        // Check Info.plist configuration
        print("\nInfo.plist Configuration:")
        if let iconsDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any] {
            print("  ✅ CFBundleIcons found")
            
            // Check primary icon
            if let primary = iconsDict["CFBundlePrimaryIcon"] as? [String: Any] {
                print("  ✅ CFBundlePrimaryIcon configured")
                if let iconName = primary["CFBundleIconName"] as? String {
                    print("    Primary icon name: \(iconName)")
                }
                if let iconFiles = primary["CFBundleIconFiles"] as? [String] {
                    print("    Primary icon files: \(iconFiles)")
                }
            } else {
                print("  ⚠️ CFBundlePrimaryIcon missing")
            }
            
            // Check alternate icons
            if let alternates = iconsDict["CFBundleAlternateIcons"] as? [String: Any] {
                print("  ✅ CFBundleAlternateIcons found with \(alternates.keys.count) entries:")
                let sortedKeys = alternates.keys.sorted()
                for key in sortedKeys {
                    print("    - \(key)")
                    if let altDict = alternates[key] as? [String: Any],
                       let files = altDict["CFBundleIconFiles"] as? [String] {
                        print("      Files: \(files)")
                    }
                }
                
                // Specifically check for our problematic icons
               
                print("\n  🔍 Checking for specific expected icons:")
                let expectedIcons = AppIcon.allCases.compactMap { $0.iconName }
                for iconName in expectedIcons {
                    let found = alternates.keys.contains(iconName)
                    print("    \(iconName): \(found ? "✅ Found" : "❌ Missing")")
                }
            } else {
                print("  ❌ CFBundleAlternateIcons missing")
            }
        } else {
            print("  ❌ CFBundleIcons not found in Info.plist")
        }
        
        // Check asset availability
        print("\nAsset Availability:")
        print("  Primary icon (AppIcon): \(UIImage(named: "AppIcon") != nil ? "✅" : "❌")")
        for icon in AppIcon.allCases {
            if icon != .primary {
                let available = UIImage(named: icon.previewImage) != nil
                let iconName = icon.iconName ?? "nil"
                print("  \(icon.displayName) (iconName: \(iconName)): \(available ? "✅" : "❌")")
                
                // Additional debug for timecard icons
                if icon.rawValue.contains("Timecard") {
                    print("    Raw value: \(icon.rawValue)")
                    print("    Looking for asset named: \(icon.previewImage)")
                }
            }
        }
        
        print(String(repeating: "=", count: 50))
        print("END DIAGNOSTIC REPORT\n")
    }
}

