import SwiftUI
import UIKit

@available(iOSApplicationExtension, unavailable)
struct AlternateIconSwitcherView: View {
    @State private var currentIcon: String? = UIApplication.shared.alternateIconName
    @State private var preview: UIImage? = nil
    @State private var resultMessage: String?
    @State private var showResultBanner = false
    
    private var icons: [(name: String?, display: String)] {
        let names = AppIconManager.alternateIconNamesFromPlist()
        var result: [(String?, String)] = [(nil, "Default")]
        for n in names.sorted() {
            result.append((n, n))
        }
        return result
    }
    
    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(radius: 4)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 72, height: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Icon").font(.headline)
                    Text(currentIcon ?? "Default")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top)
            
            ForEach(icons, id: \.name) { icon in
                Button {
                    switchIcon(to: icon.name)
                } label: {
                    Text(icon.display)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Spacer()
        }
        .padding()
        .overlay(
            Group {
                if showResultBanner, let message = resultMessage {
                    ResultBanner(message: message)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }, alignment: .top
        )
        .animation(.easeInOut(duration: 0.3), value: showResultBanner)
        .onAppear {
            currentIcon = UIApplication.shared.alternateIconName
            preview = previewImage(forAlternateName: currentIcon)
            print("Available alternates:", AppIconManager.alternateIconNamesFromPlist())
        }
    }
    
    private func switchIcon(to name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else {
            logResult("Alternate icons not supported on this device.")
            return
        }
        UIApplication.shared.setAlternateIconName(name) { error in
            DispatchQueue.main.async {
                if let error = error {
                    logResult("Failed to set icon: \(error.localizedDescription)")
                } else {
                    // Small delay helps avoid UI races in debug and lets SpringBoard settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        currentIcon = UIApplication.shared.alternateIconName
                        preview = previewImage(forAlternateName: currentIcon)
                        logResult("Successfully set icon to \(currentIcon ?? "Default")")
                    }
                }
            }
        }
    }
    
    private func iconAssetBaseName(forAlternateName name: String?) -> String? {
        guard
            let info = Bundle.main.infoDictionary,
            let icons = info["CFBundleIcons"] as? [String: Any]
        else { return nil }

        if let name = name,
           let alternates = icons["CFBundleAlternateIcons"] as? [String: Any],
           let alt = alternates[name] as? [String: Any],
           let files = alt["CFBundleIconFiles"] as? [String],
           let first = files.first {
            return first
        }

        if let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let first = files.first {
            return first
        }

        return nil
    }

    private func previewImage(forAlternateName name: String?) -> UIImage? {
        guard let base = iconAssetBaseName(forAlternateName: name) else { return nil }
        return UIImage(named: base)
    }
    
    private func logResult(_ message: String) {
        print(message)
        resultMessage = message
        withAnimation {
            showResultBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showResultBanner = false
            }
        }
    }
}

private struct ResultBanner: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75))
            .foregroundColor(.white)
            .cornerRadius(12)
            .padding(.horizontal)
            .shadow(radius: 5)
    }
}

struct AlternateIconSwitcherView_Previews: PreviewProvider {
    static var previews: some View {
        AlternateIconSwitcherView()
            .previewLayout(.sizeThatFits)
    }
}


// MARK: - Simple Icon Sanity Check (merged from IconSanityCheck 2.swift)
struct IconSanityCheck: View {
    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var message: String = ""
    @State private var busy = false

    private let names: [String?] = [nil, "AppIcon Green", "AppIcon Red", "AppIcon MC"]

    var body: some View {
        VStack(spacing: 16) {
            Text("Icon Sanity Check").font(.title3).bold()
            Group {
                Text("Current: \(current ?? "<Primary>")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !message.isEmpty {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Capsule().fill(Color.accentColor))
                }
            }

            HStack(spacing: 10) {
                ForEach(names.indices, id: \.self) { i in
                    let name = names[i]
                    Button {
                        tap(name)
                    } label: {
                        Text(title(for: name))
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(name == nil ? .gray : .accentColor)
                    .disabled(busy)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .onAppear { current = UIApplication.shared.alternateIconName }
    }

    private func title(for name: String?) -> String {
        switch name {
        case nil: return "Default"
        case let .some(n): return n
        }
    }

    private func tap(_ name: String?) {
        Task { await set(name) }
    }

    @MainActor
    private func set(_ name: String?) async {
        guard UIApplication.shared.supportsAlternateIcons else {
            message = "Alternate icons not supported"
            return
        }
        busy = true
        message = ""
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            UIApplication.shared.setAlternateIconName(name) { error in
                if let error = error {
                    print("[IconSanityCheck] Error: \(error)")
                    message = "Error: \(error.localizedDescription)"
                } else {
                    let actual = UIApplication.shared.alternateIconName
                    current = actual
                    let ok = (actual == name)
                    print("[IconSanityCheck] Set → \(name ?? "<primary>") | actual=\(actual ?? "<primary>") | ok=\(ok)")
                    message = ok ? "OK → \(title(for: name))" : "Mismatch"
                }
                cont.resume()
            }
        }
        busy = false
    }
}

#Preview {
    NavigationView { IconSanityCheck() }
}
