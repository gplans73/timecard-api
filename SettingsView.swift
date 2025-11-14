import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: TimecardStore
    
    @AppStorage("icloudSyncEnabled") private var icloudSyncEnabled: Bool = false
    @AppStorage("appTheme") private var appThemeRaw: String = ThemeType.system.rawValue
    @AppStorage("accentColorHex") private var accentColorHex: String = ""
    @SwiftUI.State private var customAccentColor: Color = .accentColor
    @FocusState private var nameFieldFocused: Bool
    
    private var selectedTheme: ThemeType { ThemeType(rawValue: appThemeRaw) ?? .system }
    
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
        accentColorHex.isEmpty ? Color.accentColor : Color(accentColorHex)
    }
    
    private func policySummary(_ p: OvertimePolicy) -> String {
        if let wk = p.weeklyRegularCap, p.dailyRegularCap == nil, p.dailyOTCap == nil {
            return "Weekly OT after \(Int(wk))h"
        }
        let reg = p.dailyRegularCap ?? 0
        let otCap = p.dailyOTCap ?? reg
        if p.dailyRegularCap != nil && p.dailyOTCap != nil {
            return "Daily: OT after \(Int(reg))h, DT after \(Int(otCap))h"
        }
        if p.dailyRegularCap != nil {
            return "Daily OT after \(Int(reg))h"
        }
        return "Custom"
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Default User").font(.headline)) {
                    TextField("Name", text: Binding(
                        get: { store.employeeName },
                        set: { store.employeeName = $0 }
                    ))
                    .focused($nameFieldFocused)
#if os(iOS)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
#endif
                    .onSubmit { nameFieldFocused = false }
                }

                Section("Export") {
                    NavigationLink(destination: EmailSettingsView().environmentObject(store)) {
                        HStack {
                            Image(systemName: "envelope")
                            Text("Email")
                        }
                    }

                    // Files subsection
                    Text("Files that can be attached")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    Toggle(isOn: Binding(
                        get: { store.attachCSV },
                        set: { store.attachCSV = $0 }
                    )) {
                        Label("Attach Entries (Excel)", systemImage: "tablecells")
                    }
#if os(macOS)
                    .toggleStyle(.checkbox)
#else
                    .toggleStyle(.switch)
#endif

                    Toggle(isOn: Binding(
                        get: { store.attachPDF },
                        set: { store.attachPDF = $0 }
                    )) {
                        Label("Attach Timecard (PDF)", systemImage: "doc.text")
                    }
#if os(macOS)
                    .toggleStyle(.checkbox)
#else
                    .toggleStyle(.switch)
#endif

                    Text("Selected files will be attached to the email when you send your timecard.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section("Jobs") {
                    NavigationLink(destination: JobsSettingsView().environmentObject(store)) {
                        HStack {
                            Image(systemName: "person.3")
                            Text("Jobs")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Codes") {
                    NavigationLink(destination: CodesAndNotesView()) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                            Text("Codes")
                        }
                    }
                    
                    NavigationLink(destination: ToolbarButtonsSettingsView()) {
                        HStack {
                            Image(systemName: "button.programmable")
                            Text("Toolbar Buttons")
                        }
                    }
                }
                
                Section("Pay Period") {
                    NavigationLink(destination: PayPeriodSettingsView().environmentObject(store)) {
                        HStack {
                            Image(systemName: "calendar")
                            Text("Pay Period")
                        }
                    }
                }
                
                Section("Appearance") {
                    NavigationLink(destination: ThemeSettingsView()) {
                        HStack {
                            Image(systemName: "paintbrush")
                            Text("Theme")
                            Spacer()
                            Circle().fill(store.accentColor).frame(width: 12, height: 12)
                        }
                    }
                    NavigationLink(destination: AppIconSettingsView()) {
                        HStack {
                            Image(systemName: "app")
                            Text("App Icon")
                        }
                    }
                    NavigationLink(destination: LogoSettingsView()) {
                        HStack {
                            Image(systemName: "photo")
                            Text("Company Logo")
                            Spacer()
                            if let _ = store.companyLogoImage {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                        Toggle("Auto Stat Holidays", isOn: Binding(
                            get: { store.autoHolidaysEnabled },
                            set: { store.autoHolidaysEnabled = $0 }
                        ))
                    }
                }
                
                Section("On Call") {
                    NavigationLink(destination: OnCallSettingsView().environmentObject(store)) {
                        HStack {
                            Image(systemName: "phone")
                            Text("On Call")
                        }
                    }
                }
                
                Section("Overtime Policy") {
                    NavigationLink(destination: OvertimePolicySelectorView()
                        .environmentObject(store)
                        .environmentObject(store.holidayManager)
                    ) {
                        HStack {
                            Image(systemName: "clock.badge.exclamationmark")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Overtime Policy")
                                Text(policySummary(store.overtimePolicy))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("Region") {
                    Toggle("Auto-detect Region", isOn: Binding(
                        get: { store.holidayManager.autoDetectRegion },
                        set: { store.holidayManager.autoDetectRegion = $0 }
                    ))
                    Button("Detect Now") {
                        Task {
                            await store.holidayManager.autoDetectAndApplyRegion()
                        }
                    }
                    Button("Preload Holidays for Current Period") {
                        Task {
                            await store.preloadHolidaysForCurrentPeriod()
                        }
                    }
                    
                    // Country and Province/State Selection
                    Picker("Country", selection: Binding(
                        get: { store.holidayManager.selectedCountry },
                        set: { store.holidayManager.selectedCountry = $0 }
                    )) {
                        ForEach(TimecardCountry.allCases, id: \.self) { country in
                            Text(country.displayName).tag(country)
                        }
                    }
                    
                    if store.holidayManager.selectedCountry == .canada {
                        Picker("Province", selection: Binding(
                            get: { store.holidayManager.selectedProvince },
                            set: { store.holidayManager.selectedProvince = $0 }
                        )) {
                            ForEach(Province.allCases, id: \.self) { province in
                                Text(province.displayName).tag(province)
                            }
                        }
                    } else {
                        Picker("State", selection: Binding(
                            get: { store.holidayManager.selectedState },
                            set: { store.holidayManager.selectedState = $0 }
                        )) {
                            ForEach(TimecardUSState.allCases, id: \.self) { state in
                                Text(state.displayName).tag(state)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.holidayManager.regionStatusLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(store.holidayManager.cachedYearsStatusLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Uses your region (auto-detected if enabled) to fetch and cache holidays. Falls back to built-in rules if the network is unavailable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section("iCloud") {
                    NavigationLink(destination: ICloudSettingsView()) {
                        HStack {
                            Image(systemName: "icloud")
                            Text("iCloud")
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { nameFieldFocused = false }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { customAccentColor = effectiveAccentColor }
        }
    }
}

// MARK: - Email Preview Sheet
private struct EmailPreviewSheet: View {
    let store: TimecardStore
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Preview Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email Preview")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("This is how your email will appear with current settings.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    // Email Content
                    VStack(alignment: .leading, spacing: 16) {
                        // Recipients
                        VStack(alignment: .leading, spacing: 4) {
                            Text("To:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(store.emailRecipients.joined(separator: "; "))
                                .font(.body)
                        }
                        
                        Divider()
                        
                        // Subject
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Subject:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(store.emailSubject(for: store.selectedWeekStart))
                                .font(.body)
                        }
                        
                        Divider()
                        
                        // Body
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Body:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(store.emailBody(for: store.selectedWeekStart))
                                .font(.body)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                }
                .padding()
            }
            .navigationTitle("Email Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(TimecardStore.sampleStore)
    }
}

