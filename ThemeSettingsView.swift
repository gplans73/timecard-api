import SwiftUI

struct ThemeSettingsView: View {
    @EnvironmentObject var store: TimecardStore
    @AppStorage("appTheme") private var appThemeRaw: String = ThemeType.system.rawValue
    @AppStorage("accentColorHex") private var accentColorHex: String = ""
    @State private var customAccentColor: Color = .accentColor

    private var selectedTheme: ThemeType { ThemeType(rawValue: appThemeRaw) ?? .system }

    // MARK: - Helpers
    private func hexString(from color: Color) -> String {
        #if os(iOS)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(r*255)), Int(round(g*255)), Int(round(b*255)))
        #else
        let ns = NSColor(color)
        let c = ns.usingColorSpace(.deviceRGB) ?? ns
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent*255)), Int(round(c.greenComponent*255)), Int(round(c.blueComponent*255)))
        #endif
    }
    private var effectiveAccentColor: Color {
        accentColorHex.isEmpty ? Color.accentColor : Color(hex: accentColorHex)
    }

    var body: some View {
        List {
            // Theme selection (System / Light / Dark / Automatic)
            Section(header: Text("Theme").font(.headline)) {
                ForEach(ThemeType.allCases) { theme in
                    Button(action: {
                        appThemeRaw = theme.rawValue
                        UbiquitousSettingsSync.shared.pushTheme(appThemeRaw: appThemeRaw)
                    }) {
                        HStack {
                            Image(systemName: theme.icon)
                            Text(theme.label)
                            Spacer()
                            if selectedTheme == theme {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                    .contentShape(Rectangle())
                }
            }

            // Accent color
            Section(header: Text("Accent Color").font(.headline)) {
                let presets: [String] = [
                    "#AF52DE", // purple
                    "#007AFF", // blue
                    "#34C759", // green
                    "#FF3B30", // red
                    "#FF9500", // orange
                    "#30B0C7"  // teal
                ]

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            accentColorHex = ""
                            customAccentColor = .accentColor
                            UbiquitousSettingsSync.shared.pushAccent(hex: accentColorHex)
                        } label: {
                            Text("System")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(store.accentColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .frame(minWidth: 72)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .background(
                                    Capsule().fill({
#if os(iOS)
                                        Color(UIColor.tertiarySystemBackground)
#else
                                        Color.secondary.opacity(0.15)
#endif
                                    }())
                                )
                                .overlay(
                                    Capsule().stroke(store.accentColor, lineWidth: accentColorHex.isEmpty ? 1.6 : 1.0)
                                )
                                .shadow(color: store.accentColor.opacity(accentColorHex.isEmpty ? 0.25 : 0), radius: 1)
                        }
                        .buttonStyle(.plain)

                        ForEach(presets, id: \.self) { hex in
                            Button {
                                accentColorHex = hex
                                customAccentColor = Color(hex: hex)
                                UbiquitousSettingsSync.shared.pushAccent(hex: accentColorHex)
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle().stroke(Color.white, lineWidth: accentColorHex == hex ? 3 : 0)
                                    )
                                    .shadow(radius: 0.5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(
                    {
#if os(iOS)
                        Color(UIColor.secondarySystemBackground)
#else
                        Color.secondary.opacity(0.12)
#endif
                    }(), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                )

                ColorPicker("Custom", selection: $customAccentColor, supportsOpacity: false)
                    .onChange(of: customAccentColor) { _, newValue in
                        accentColorHex = hexString(from: newValue)
                        UbiquitousSettingsSync.shared.pushAccent(hex: accentColorHex)
                    }
            }
        }
        .navigationTitle("Theme")
        .onAppear { customAccentColor = effectiveAccentColor }
        .onChange(of: appThemeRaw) { _, newValue in
            UbiquitousSettingsSync.shared.pushTheme(appThemeRaw: newValue)
        }
        .onChange(of: accentColorHex) { _, newValue in
            UbiquitousSettingsSync.shared.pushAccent(hex: newValue)
        }
    }
}

#Preview {
    ThemeSettingsView().environmentObject(TimecardStore.sampleStore)
}
