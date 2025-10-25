import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AppIconViewModel: ObservableObject {
    // Published UI state
    @Published var currentIconName: String? = {
        #if canImport(UIKit)
        return UIApplication.shared.alternateIconName
        #else
        return nil
        #endif
    }()
    @Published var options: [IconOption] = AppIconViewModel.makeOptions()
    @Published var isApplying: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Derived models
    var currentIcon: AppIconDescriptor {
        #if canImport(UIKit)
        let name = UIApplication.shared.alternateIconName
        let display: String
        if let n = name, !n.isEmpty {
            let spaced = n.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            display = spaced.prefix(1).uppercased() + spaced.dropFirst()
        } else {
            display = "Default"
        }
        return AppIconDescriptor(name: name, displayName: display, previewImage: name ?? "AppIcon")
        #else
        return AppIconDescriptor(name: nil, displayName: "Default", previewImage: "AppIcon")
        #endif
    }

    func preview(for option: IconOption) -> AppIconDescriptor {
        let display = option.title
        let imageName = option.iconNameForAPI ?? "AppIcon"
        return AppIconDescriptor(name: option.iconNameForAPI, displayName: display, previewImage: imageName)
    }

    // MARK: - Actions
    func refresh() {
        #if canImport(UIKit)
        currentIconName = UIApplication.shared.alternateIconName
        #else
        currentIconName = nil
        #endif
        options = AppIconViewModel.makeOptions()
    }

    func apply(_ option: IconOption) async {
        #if canImport(UIKit)
            guard UIApplication.shared.supportsAlternateIcons else {
                self.errorMessage = "Alternate icons are not supported on this device."
                return
            }
        #endif
            isApplying = true
            errorMessage = nil
            do {
                try await AppIconViewModel.setAlternateIcon(option.iconNameForAPI)
                #if canImport(UIKit)
                self.currentIconName = UIApplication.shared.alternateIconName
                #else
                self.currentIconName = nil
                #endif
                self.options = AppIconViewModel.makeOptions()
            } catch {
                self.errorMessage = error.localizedDescription
            }
            isApplying = false
    }

    // MARK: - Private helpers
    private static func makeOptions() -> [IconOption] {
        #if canImport(UIKit)
        var result: [IconOption] = []
        // Primary icon option first
        result.append(IconOption(title: "Default", iconNameForAPI: nil))
        if let iconsDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let alternates = iconsDict["CFBundleAlternateIcons"] as? [String: Any] {
            let names = alternates.keys.sorted()
            for raw in names {
                let title = prettifyIconName(raw)
                result.append(IconOption(title: title, iconNameForAPI: raw))
            }
        }
        return result
        #else
        return [IconOption(title: "Default", iconNameForAPI: nil)]
        #endif
    }

    #if canImport(UIKit)
    private static func prettifyIconName(_ raw: String) -> String {
        guard !raw.isEmpty else { return "Default" }
        let spaced = raw.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
    #endif

    private static func setAlternateIcon(_ name: String?) async throws {
        #if canImport(UIKit)
        return try await withCheckedThrowingContinuation { continuation in
            UIApplication.shared.setAlternateIconName(name) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #else
        // No-op on platforms without UIKit
        return
        #endif
    }
}

