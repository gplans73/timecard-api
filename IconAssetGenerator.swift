import SwiftUI

// MARK: - Icon Asset Creator
// This is a helper to generate icon assets for your project
struct IconAssetGenerator {
    
    /// Generates icon sets that match the AppIcon enum cases
    static func generateIconSets() -> [IconSet] {
        return [
            IconSet(name: "AppIcon", colors: [.blue, .cyan], isDefault: true),
            IconSet(name: "Applcon", colors: [.blue, .cyan]),
            IconSet(name: "Applcon2", colors: [.green, .mint]),
            IconSet(name: "Applcon3", colors: [.red, .orange]),
            IconSet(name: "Applcon4", colors: [.purple, .indigo]),
            IconSet(name: "Applcon5", colors: [.teal, .blue]),
            IconSet(name: "Applcon6", colors: [.orange, .yellow]),
            IconSet(name: "Applcon7", colors: [.pink, .purple]),
            IconSet(name: "Applcon8", colors: [.brown, .orange])
        ]
    }
    
    /// Generates all required icon sizes for each icon set
    static func generateAllAssets() -> [URL] {
        var urls: [URL] = []
        let iconSets = generateIconSets()
        
        for iconSet in iconSets {
            urls.append(contentsOf: generateIconSet(iconSet))
        }
        
        return urls
    }
    
    private static func generateIconSet(_ iconSet: IconSet) -> [URL] {
        var urls: [URL] = []
        
        // Standard icon sizes for iOS
        let sizes: [(size: CGFloat, suffix: String)] = [
            (1024, "@1x"), // App Store
            (180, "@3x"),  // iPhone
            (120, "@2x"),  // iPhone
            (167, "@2x"),  // iPad Pro
            (152, "@2x"),  // iPad
            (76, "@1x"),   // iPad
            (58, "@2x"),   // Settings
            (40, "@2x"),   // Spotlight
            (29, "@1x")    // Settings
        ]
        
        for (size, suffix) in sizes {
            if let url = generateIcon(iconSet: iconSet, size: size, suffix: suffix) {
                urls.append(url)
            }
        }
        
        return urls
    }
    
    private static func generateIcon(iconSet: IconSet, size: CGFloat, suffix: String) -> URL? {
        #if canImport(UIKit)
        let controller = UIHostingController(
            rootView: IconArt(colors: iconSet.colors, symbol: "doc.text")
        )
        
        let bounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        controller.view.bounds = bounds
        controller.view.backgroundColor = Color.clear
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024))
        let baseImage = renderer.image { ctx in
            controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        
        // Scale to requested size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let scaledRenderer = UIGraphicsImageRenderer(
            size: CGSize(width: size, height: size), 
            format: format
        )
        
        let finalImage = scaledRenderer.image { _ in
            baseImage.draw(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
        }
        
        // Save to temporary directory
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeneratedIcons", isDirectory: true)
            .appendingPathComponent(iconSet.name, isDirectory: true)
        
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        
        let fileName = "\(iconSet.name)_\(Int(size))\(suffix).png"
        let fileURL = tmp.appendingPathComponent(fileName)
        
        if let data = finalImage.pngData() {
            try? data.write(to: fileURL)
            return fileURL
        }
        
        return nil
        #else
        return nil
        #endif
    }
}

struct IconSet {
    let name: String
    let colors: [Color]
    let isDefault: Bool
    
    init(name: String, colors: [Color], isDefault: Bool = false) {
        self.name = name
        self.colors = colors
        self.isDefault = isDefault
    }
}
