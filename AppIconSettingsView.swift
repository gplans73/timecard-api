import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AppIconSettingsView: View {
    @State private var current: AppIcon = .primary
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        List {
            Section(header: Text("App Icon").font(.headline)) {
                // Current selection header card
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(current.displayName)
                            .font(.title3).fontWeight(.semibold)
                            .lineLimit(1)
                        Text("Currently Selected")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let img = image(for: current) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .cornerRadius(16)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Current icon \(current.displayName)"))

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AppIcon.allCases, id: \.self) { icon in
                        IconChoiceCell(icon: icon, isSelected: icon == current) {
                            set(icon)
                        }
                        .disabled(!supportsAlternateIcons && icon != .primary)
                    }
                }
                .padding(.vertical, 4)

                if !supportsAlternateIcons {
                    Text("This device doesn’t support switching to alternate icons. You can still use the default icon.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("App Icon")
        .onAppear { current = AppIconManager.shared.currentIcon }
    }

    private var supportsAlternateIcons: Bool {
        #if canImport(UIKit)
        UIApplication.shared.supportsAlternateIcons
        #else
        false
        #endif
    }

    private func set(_ icon: AppIcon) {
        #if canImport(UIKit)
        AppIconManager.shared.setIcon(icon) { success in
            if success { current = icon }
        }
        #endif
    }
    
    private func image(for icon: AppIcon) -> UIImage? {
        #if canImport(UIKit)
        if icon == .primary {
            if let iconsDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
               let primary = iconsDict["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String],
               let last = files.last, let ui = UIImage(named: last) {
                return ui
            }
            return UIImage(named: "AppIcon")
        } else {
            if let iconsDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
               let alts = iconsDict["CFBundleAlternateIcons"] as? [String: Any],
               let alt = alts[icon.rawValue] as? [String: Any],
               let files = alt["CFBundleIconFiles"] as? [String],
               let last = files.last, let ui = UIImage(named: last) {
                return ui
            }
            return UIImage(named: icon.previewImage)
        }
        #else
        return nil
        #endif
    }
}

private struct IconChoiceCell: View {
    let icon: AppIcon
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if let image = previewImage() {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .cornerRadius(14)
                    } else {
                        IconGeneratedPreview(colors: [Color.accentColor.opacity(0.4), Color.accentColor], symbol: "app")
                            .frame(width: 84, height: 84)
                    }
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.accentColor, lineWidth: 3)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(icon.displayName))
    }

    private func previewImage() -> UIImage? {
        #if canImport(UIKit)
        if icon == .primary {
            // Try to resolve primary from Info.plist files; fallback to AppIcon asset name
            if let iconsDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
               let primary = iconsDict["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String],
               let last = files.last, let ui = UIImage(named: last) {
                return ui
            }
            return UIImage(named: "AppIcon")
        } else {
            // Resolve alternate by its CFBundleIconFiles last entry (commonly equals rawValue)
            if let iconsDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
               let alts = iconsDict["CFBundleAlternateIcons"] as? [String: Any],
               let alt = alts[icon.rawValue] as? [String: Any],
               let files = alt["CFBundleIconFiles"] as? [String],
               let last = files.last, let ui = UIImage(named: last) {
                return ui
            }
            return UIImage(named: icon.previewImage)
        }
        #else
        return nil
        #endif
    }
}

// Reuse the existing generated preview from IconSettingsView if present; otherwise a simple fallback
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

#Preview { NavigationStack { AppIconSettingsView() } }
