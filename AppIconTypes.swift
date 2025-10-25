import Foundation

// Represents an app icon option for display in settings
struct AppIconDescriptor: Identifiable, Hashable {
    // Use the alternate icon name (nil means primary) as the identifier
    let id = UUID()
    let name: String?          // The value to pass to UIApplication.setAlternateIconName
    let displayName: String    // Human-readable name for UI
    let previewImage: String   // Asset name for preview (falls back to GeneratedIconPreview if missing)
}

// Represents a selectable icon option in UI that maps to an alternate icon name
struct IconOption: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let iconNameForAPI: String? // nil means reset to primary icon
}
