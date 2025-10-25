import UIKit
import SwiftUI

enum AppIcon: String, CaseIterable {
    case primary

    // Existing icons
    
    
    
    case AppIconLGWhite = "AppIconLGWhite"
    
    
    case LGTimeCardWhite = "LGTimeCardWhite"
    case LGTimeCardDark = "LGTimeCardDark"
    
    case AppIconRedWhite = "AppIconRedWhite"
    case AppIconRedDark = "AppIconRedDark"
    
    case AppIconBlackWhite = "AppIconBlackWhite"
    case AppIconBlackDark = "AppIconBlackDark"
    
    case AppIconGreenWhite = "AppIconGreenWhite"
    case AppIconGreenDark = "AppIconGreenDark"
    
    case AppIconGrey = "AppIconGrey"
        
    case AppIconOrangeWhite = "AppIconOrangeWhite"
    case AppIconOrangeDark = "AppIconOrangeDark"
    
    case AppIconPurpleWhite = "AppIconPurpleWhite"
    case AppIconPurpleDark = "AppIconPurpleDark"
    
    case ApplconYellowWhite = "ApplconYellowWhite"
    case ApplconYellowDark = "ApplconYellowDark"
    
    case AppIconMCWhite = "AppIconMCWhite"
    case AppIconMCDark = "AppIconMCDark"
    
    case AppIconMCMWhite = "AppIconMCMWhite"
    case AppIconMCMDark = "AppIconMCMDark"

   
    var iconName: String? {
        switch self {
        case .primary: return nil
        default: return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .primary: return "Logical Group Dark"
            
        case .LGTimeCardWhite: return "LG Time Card Light"
        case .LGTimeCardDark: return "LG Time Card Dark"
        
        case .AppIconLGWhite: return "Logical Group Light"
        
      
        case .AppIconRedWhite: return "Red Light"
        case .AppIconRedDark: return "Red Card"
            
        case .AppIconBlackWhite: return "Black Light"
        case .AppIconBlackDark: return "Black Dark"
            
        case .AppIconGreenWhite: return "Green Light"
        case .AppIconGreenDark: return "Green Dark"
            
        case .AppIconGrey: return "Grey Icon"
            
        case .AppIconOrangeWhite: return "Orange Light"
        case .AppIconOrangeDark: return "Orange Dark"
            
        case .AppIconPurpleWhite: return "Purple Light"
        case .AppIconPurpleDark: return "Purple Dark"
            
        case .ApplconYellowWhite: return "Yellow Light"
        case .ApplconYellowDark: return "Yellow Dark"
            
        case .AppIconMCWhite: return "Multi Multi Light"
        case .AppIconMCDark: return "Multi Multi Dark"
            
        case .AppIconMCMWhite: return "Multi Colour Light"
        case .AppIconMCMDark: return "Multi Colour Dark"
            
        }
    }

    // The asset name to use for a square preview in the picker. Usually the last entry in CFBundleIconFiles.
    var previewImage: String {
        switch self {
        case .primary: return "AppIconLGWhite"
        
        
            
        case .AppIconLGWhite: return "AppIconLGWhite"
        
        
        case .LGTimeCardWhite: return "LGTimeCardWhite"
        case .LGTimeCardDark: return "LGTimeCardDark"
            
        case .AppIconRedWhite: return "AppIconRedWhite"
        case .AppIconRedDark: return "AppIconRedDark"
        
        case .AppIconBlackWhite: return "AppIconBlackWhite"
        case .AppIconBlackDark: return "AppIconBlackDark"
            
        case .AppIconGreenWhite: return "AppIconGreenWhite"
        case .AppIconGreenDark: return "AppIconGreenDark"
            
        case .AppIconGrey: return "AppIconGrey"
            
        case .AppIconOrangeWhite: return "AppIconOrangeWhite"
        case .AppIconOrangeDark: return "AppIconOrangeDark"
            
        case .AppIconPurpleWhite: return "AppIconPurpleWhite"
        case .AppIconPurpleDark: return "AppIconPurpleDark"
            
        case .ApplconYellowWhite: return "AppIconYellowWhite"
        case .ApplconYellowDark: return "AppIconYellowDark"
        
        case .AppIconMCWhite: return "AppIconMCWhite"
        case .AppIconMCDark: return "AppIconMCDark"
            
        case .AppIconMCMWhite: return "AppIconMCMWhite"
        case .AppIconMCMDark: return "AppIconMCMDark"
            
        }
    }
}

final class AppIconManager {
    static let shared = AppIconManager()
    
    private init() {}
    
    /// Returns the list of alternate icon names defined in the app's Info.plist (CFBundleAlternateIcons keys).
    /// If none are defined or the plist can't be parsed, returns an empty array.
    static func alternateIconNamesFromPlist() -> [String] {
        guard
            let info = Bundle.main.infoDictionary,
            let icons = info["CFBundleIcons"] as? [String: Any],
            let alternates = icons["CFBundleAlternateIcons"] as? [String: Any]
        else {
            return []
        }
        return Array(alternates.keys)
    }

    /// Returns the list of available alternate icon names from Info.plist (keys of CFBundleAlternateIcons)
    /// The primary icon is represented by `nil` and listed first.
    var availableAlternateIcons: [String?] {
        var result: [String?] = [nil] // primary first
        if let iconsDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let alternates = iconsDict["CFBundleAlternateIcons"] as? [String: Any] {
            // Sort to keep a stable order in UI
            let names = alternates.keys.sorted()
            result.append(contentsOf: names.map { Optional($0) })
        }
        return result
    }
    
    /// Returns the current app icon as an `AppIcon` enum (.primary when no alternate is set or name doesn't match)
    var currentIcon: AppIcon {
        #if canImport(UIKit)
        if let name = UIApplication.shared.alternateIconName, let icon = AppIcon(rawValue: name) {
            return icon
        } else {
            return .primary
        }
        #else
        return .primary
        #endif
    }

    /// Set icon by raw alternate name (nil = primary). This is convenient when icons are generated dynamically.
    func setIcon(named altName: String?, completion: ((Bool) -> Void)? = nil) {
        guard UIApplication.shared.supportsAlternateIcons else {
            completion?(false)
            return
        }
        UIApplication.shared.setAlternateIconName(altName) { error in
            if let error = error {
                print("❌ Error setting alternate icon: \(error)")
                completion?(false)
            } else {
                completion?(true)
            }
        }
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
                
                // Specifically check for our expected icons
               
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
        
        // Discovered alternates (dynamic)
        print("\nDiscovered alternates (dynamic):")
        for name in availableAlternateIcons {
            if let name { print("  • \(name)") } else { print("  • primary (nil)") }
        }
        
        print(String(repeating: "=", count: 50))
        print("END DIAGNOSTIC REPORT\n")
    }
}

