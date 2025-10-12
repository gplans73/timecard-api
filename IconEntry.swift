import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private struct IconEntry: Identifiable {
    let id = UUID()
    let altName: String?   // nil = primary (AppIcon)
    let label: String
}

struct IconSettingsView: View {
    @SwiftUI.State private var icons: [IconEntry] = []
    @SwiftUI.State private var selected: String = {
        #if canImport(UIKit)
        UIApplication.shared.alternateIconName ?? "AppIcon"
        #else
        "AppIcon"
        #endif
    }()
    @SwiftUI.State private var showAlert = false
    @SwiftUI.State private var alertMessage = ""

    private var supportsAlternateIcons: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.supportsAlternateIcons
        #else
        return false
        #endif
    }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    var body: some View {
        List {
            Section(header: Text("App Icon").font(.headline)) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(icons) { entry in
                        IconCellView(image: iconUIImage(for: entry.altName), fallbackSymbol: fallbackSymbol(for: entry), label: entry.label, isSelected: isSelected(entry)) {
                            setIcon(named: entry.altName)
                        }
                        .disabled(!supportsAlternateIcons && entry.altName != nil)
                    }
                }
                .padding(.vertical, 4)

                Text("Tip: Alternate icons must be added to the Asset Catalog and registered in Info.plist (CFBundleIcons → CFBundleAlternateIcons). This list reflects what’s currently configured in your project.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                if !supportsAlternateIcons {
                    Text("This device doesn’t support switching to alternate icons. You can still use the default icon.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                if iconUIImage(for: nil) == nil {
                    Text("Primary App Icon not found. In your target → General → App Icons and Launch Images, set ‘App Icons Source’ to the ‘AppIcon’ asset, and ensure the icon images are filled in.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("App Icon")
        .onAppear { icons = loadIconsFromBundle() }
        .alert("App Icon", isPresented: $showAlert, actions: { Button("OK", role: .cancel) {} }, message: { Text(alertMessage) })
    }

    // MARK: - Selection
    private func isSelected(_ entry: IconEntry) -> Bool {
        #if canImport(UIKit)
        if let alt = entry.altName { return UIApplication.shared.alternateIconName == alt }
        return UIApplication.shared.alternateIconName == nil
        #else
        return (entry.altName == nil)
        #endif
    }

    // MARK: - Load icons from Info.plist
    private func loadIconsFromBundle() -> [IconEntry] {
        var results: [IconEntry] = []
        guard let iconsDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any] else {
            // Fallback: just show Default
            results.append(.init(altName: nil, label: "Default"))
            return results
        }

        // Primary (AppIcon)
        if let primary = iconsDict["CFBundlePrimaryIcon"] as? [String: Any] {
            let label = (primary["CFBundleIconName"] as? String).flatMap(humanizeName) ?? "Default"
            results.append(.init(altName: nil, label: label))
        } else {
            results.append(.init(altName: nil, label: "Default"))
        }

        // Alternates
        if let alts = iconsDict["CFBundleAlternateIcons"] as? [String: Any] {
            for (name, value) in alts {
                let dict = value as? [String: Any]
                let label = (dict?["CFBundleIconName"] as? String).flatMap(humanizeName) ?? humanizeName(name)
                results.append(.init(altName: name, label: label))
            }
        }
        return results
    }

    private func humanizeName(_ raw: String) -> String {
        // Insert spaces before capital letters and around numbers
        let pattern = "(?<!^)([A-Z]|[0-9]+)"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: raw.count)
        let spaced = regex?.stringByReplacingMatches(in: raw, options: [], range: range, withTemplate: " $1") ?? raw
        return spaced.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Resolve UIImage for icon
    private func iconUIImage(for altName: String?) -> UIImage? {
        #if canImport(UIKit)
        guard let iconsDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any] else { return nil }
        if let altName = altName, let alts = iconsDict["CFBundleAlternateIcons"] as? [String: Any], let alt = alts[altName] as? [String: Any], let files = alt["CFBundleIconFiles"] as? [String], let last = files.last {
            return UIImage(named: last)
        }
        if altName == nil, let primary = iconsDict["CFBundlePrimaryIcon"] as? [String: Any], let files = primary["CFBundleIconFiles"] as? [String], let last = files.last {
            return UIImage(named: last)
        }
        // Fallback to asset named "AppIcon" when primary icon files aren't listed in Info.plist (common with asset catalogs)
        if altName == nil {
            return UIImage(named: "AppIcon")
        }
        return nil
        #else
        return nil
        #endif
    }

    private func fallbackSymbol(for entry: IconEntry) -> String {
        if let name = entry.altName?.lowercased() {
            if name.contains("clock") { return "clock" }
            if name.contains("calendar") { return "calendar" }
        }
        return "doc.text"
    }

    // MARK: - Set icon
    private func setIcon(named altName: String?) {
        #if canImport(UIKit)
        // If selecting Default and alternates aren't supported, just mark as selected silently.
        if altName == nil && !supportsAlternateIcons {
            selected = "AppIcon"
            return
        }
        guard supportsAlternateIcons else {
            alertMessage = "Alternate app icons aren’t supported on this device."
            showAlert = true
            return
        }
        UIApplication.shared.setAlternateIconName(altName) { error in
            if let error = error {
                alertMessage = "Failed to set icon: \(error.localizedDescription)"
                showAlert = true
            } else {
                selected = altName ?? "AppIcon"
            }
        }
        #else
        alertMessage = "Alternate icons are only available on iOS."
        showAlert = true
        #endif
    }
}

// MARK: - Cell
private struct IconCellView: View {
    let image: UIImage?
    let fallbackSymbol: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .cornerRadius(14)
                    } else {
                        IconGeneratedPreview(colors: [Color.accentColor.opacity(0.4), Color.accentColor], symbol: fallbackSymbol)
                            .frame(width: 64, height: 64)
                    }
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.accentColor, lineWidth: 3)
                    }
                }
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct IconGeneratedPreview: View {
    let colors: [Color]
    let symbol: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.9))
                .frame(width: 44, height: 36)
                .offset(y: 2)
            VStack(spacing: 3) {
                Rectangle().fill(Color.black.opacity(0.25)).frame(width: 30, height: 3)
                Rectangle().fill(Color.black.opacity(0.15)).frame(width: 30, height: 3)
                Rectangle().fill(Color.black.opacity(0.15)).frame(width: 30, height: 3)
            }
            Image(systemName: symbol)
                .foregroundStyle(.black.opacity(0.7))
                .font(.system(size: 16, weight: .bold))
                .offset(x: 12, y: -12)
        }
    }
}

#Preview { NavigationStack { IconSettingsView() } }
