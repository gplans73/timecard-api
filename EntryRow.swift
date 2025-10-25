import SwiftUI

struct EntryRow: View {
    @EnvironmentObject var store: TimecardStore

    @Binding var jobNumber: String
    @Binding var hours: Double
    @Binding var code: String
    @Binding var notes: String
    @Binding var isOvertime: Bool
    @Binding var isNightShift: Bool

    // Optional delete action for this row
    var onDelete: (() -> Void)? = nil

    // New enum to represent hour types
    enum HourType: String, CaseIterable, Identifiable {
        case regular = "Regular"
        case nightShift = "Night"
        case overtime = "Overtime"

        var id: String { rawValue }
    }

    // State to track the selected hour type
    @State private var selectedHourType: HourType = .regular
    
    // Track whether the user has manually selected a type (vs auto-detected)
    @State private var isManualSelection: Bool = false

    @State private var showLabourCodes = false
    @State private var hoursText: String = ""   // 👈 changed from "0" to ""
    @FocusState private var hoursFocused: Bool

    @State private var showJobPicker: Bool = false
    @State private var isOtherJobSelected: Bool = false
    @State private var showSuggestions: Bool = false
    @FocusState private var jobNumberFocused: Bool

    @State private var showJobsSettings: Bool = false

    @State private var showJobMenuPopover: Bool = false
    
    @State private var popoverContentWidth: CGFloat = 0

    @State private var showEnterCodeSheet: Bool = false
    @State private var tempJobCode: String = ""

    private let step: Double = 0.5

    // Formatter that drops trailing zeros and shows up to 2 decimals
    private static let displayFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 2
        return nf
    }()
    private func formatted(_ value: Double) -> String {
        Self.displayFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func syncTextFromHours() {
        hoursText = (hours == 0) ? "" : formatted(hours)              // 0 -> "", 2.5 -> "2.5"
    }

    private func syncHoursFromText() {
        // sanitize: allow digits, one dot, optional leading minus (we clamp to >= 0 anyway)
        var t = hoursText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            hours = 0
            hoursText = ""
            return
        }
        if t.first == "." { t = "0" + t }         // ".5" -> "0.5"
        if t == "-" || t == "-." { t = "0" }

        let allowed = "0123456789.-"
        t = String(t.filter { allowed.contains($0) })

        if let v = Double(t) {
            // clamp to reasonable bounds, keep up to 2 decimals visually
            let clamped = max(0, min(24, v))
            hours = clamped
            hoursText = formatted(clamped)        // removes trailing zeros
        } else {
            // fall back to last model value
            hoursText = formatted(hours)
        }
    }

    private var matchedJob: Job? {
        store.jobs.first(where: { $0.code == jobNumber })
    }

    private func filteredJobs(_ query: String) -> [Job] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return store.jobs
            .filter { store.onCallEnabled || !($0.name == "On Call" || $0.code.uppercased() == "OC") }
            .filter { $0.name.localizedCaseInsensitiveContains(q) || $0.code.localizedCaseInsensitiveContains(q) }
            .prefix(20)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header row as two equal-width centered cells
            HStack(spacing: 0) {
                // Job number cell with combined Picker + TextField
                ZStack {
                    Color.clear

                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            // Left: manual job number entry with custom keyboard
                            JobCodeTextField(title: "Job", text: $jobNumber)
                                .focused($jobNumberFocused)
                                .onChange(of: jobNumberFocused) { _, nowFocused in
                                    if !nowFocused {
                                        jobNumber = jobNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                    // Disable suggestions entirely
                                    showSuggestions = false
                                }
                                .onChange(of: jobNumber) { _, _ in
                                    // Disable suggestions entirely when typing
                                    showSuggestions = false
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Right: chevron dropdown for predefined jobs
                            Menu {
                                // Top: Manage Jobs only (no Enter Code)
                                Button { showJobsSettings = true } label: { Label("Manage Jobs…", systemImage: "gearshape") }

                                Divider()

                                // Two-line job rows: code on first line, name on second
                                ForEach(store.jobs.filter { store.onCallEnabled || !($0.name == "On Call" || $0.code.uppercased() == "OC") }) { job in
                                    Button {
                                        Task { @MainActor in
                                            try? await Task.sleep(for: .milliseconds(75))
                                            jobNumber = job.code
                                            isOtherJobSelected = false
                                            showSuggestions = false
                                        }
                                    } label: {
                                        (
                                            Text(job.code)
                                                .font(.system(size: 17, weight: .semibold))
                                                .monospacedDigit()
                                                .foregroundStyle(.primary)
                                            + Text("\n")
                                            + Text(job.name)
                                                .font(.system(size: 13))
                                                .foregroundStyle(.secondary)
                                        )
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 2)
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .accessibilityLabel("Choose Job")
                            .accessibilityValue(jobNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "None" : jobNumber)
                            .transaction { tx in tx.animation = nil }
                        }
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    
                    // Removed suggestion list UI to disable suggestions entirely
                    
                }
                .frame(maxWidth: .infinity, minHeight: 44)

                // Vertical divider
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 44)

                // Code picker cell as Menu
                ZStack {
                    Color.clear
                    Menu {
                        ForEach(store.labourCodes.filter { store.onCallEnabled || !($0.name == "On Call" || $0.code.uppercased() == "OC") }) { item in
                            Button {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(75))
                                    code = item.code
                                }
                            } label: {
                                Text(item.code.isEmpty ? "None" : item.code)
                                    .font(.system(size: 18, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                Text(item.name)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(code.isEmpty ? "Code" : code)
                                .font(.system(size: 18, weight: .semibold))
                                .monospacedDigit()
                                .multilineTextAlignment(.center)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(store.accentColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .accessibilityLabel("Choose Labour Code")
                    .accessibilityValue(code.isEmpty ? "None" : code)
                    .transaction { tx in tx.animation = nil }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }

            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)

            // Hour type segmented control spans full width, centered inherently
            Picker("Hour Type", selection: $selectedHourType) {
                Text("Regular").tag(HourType.regular)
                Text("Night").tag(HourType.nightShift)
                Text("Overtime").tag(HourType.overtime)
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedHourType) { _, newValue in
                // Update bindings based on selection
                isOvertime = (newValue == .overtime)
                isNightShift = (newValue == .nightShift)

                // Mark this as a manual selection
                isManualSelection = true

                // Do not auto-change the labour code when toggling Night/Regular/Overtime.
                // The user will choose the appropriate code manually if they wish.
            }

            // Hours row as three cells: label, field, +/- controls; all centered
            HStack(spacing: 0) {
                ZStack { // label cell
                    Color.clear
                    Text("Hours:")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, minHeight: 40)

                Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 40)

                ZStack { // text field cell
                    Color.clear
                    ZStack {
                        TextField("0", text: $hoursText)
#if os(iOS)
                            .keyboardType(.decimalPad)
                            .submitLabel(.done)
#endif
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .id("hoursField")
                            .focused($hoursFocused)
                            .onChange(of: hoursText) { _, _ in
                                var t = hoursText
                                if t.first == "." { t = "0" + t }
                                t.removeAll(where: { $0 == "-" })
                                var seenDot = false
                                t = String(t.compactMap { c in
                                    if c.isNumber { return c }
                                    if c == "." && !seenDot { seenDot = true; return c }
                                    return nil
                                })
                                hoursText = t
                            }
                            .onChange(of: hoursFocused) { _, nowFocused in
                                if !nowFocused { syncHoursFromText() }
                            }
                            .onSubmit { syncHoursFromText() }
                            .onAppear { syncTextFromHours() }
                            .onChange(of: hours, initial: false) { _, _ in syncTextFromHours() }

                        // Trailing clear button overlay
                        HStack {
                            Spacer()
                            if !hoursText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (Double(hoursText) ?? hours) > 0 {
                                Button {
                                    hours = 0
                                    syncTextFromHours()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear hours")
                                .padding(.trailing, 8)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40)

                Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 40)

                ZStack { // +/- controls cell
                    Color.clear
                    HStack(spacing: 18) {
                        Button {
                            hours = max(0, ((hours - step) * 100).rounded() / 100)
                            syncTextFromHours()
                        } label: {
                            Image(systemName: "minus").font(.body.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)

                        Button {
                            hours = min(24, ((hours + step) * 100).rounded() / 100)
                            syncTextFromHours()
                            // Let user keep their selected code when adding hours
                        } label: {
                            Image(systemName: "plus").font(.body.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
#if os(iOS)
                    .background(Color(UIColor.systemGray5), in: Capsule())
#else
                    .background(Color.secondary.opacity(0.2), in: Capsule())
#endif
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.leading, 10)
            }

            HStack {
                Spacer()
                Text("Swipe left to delete")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(
                {
#if os(iOS)
                    Color(UIColor.systemBackground)
#else
                    Color(nsColor: NSColor.windowBackgroundColor)
#endif
                }()
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(
                {
#if os(iOS)
                    Color(UIColor.quaternaryLabel)
#else
                    Color.secondary.opacity(0.3)
#endif
                }(),
                lineWidth: 0.5)
        )
        //.sheet(isPresented: $showLabourCodes) {
        //    EntryRowLabourCodePicker(code: $code).environmentObject(store)
        //}
        .onAppear {
            syncTextFromHours()
            
            // Initialize selectedHourType based on current state
            if isOvertime {
                selectedHourType = .overtime
                isNightShift = false
            } else {
                let category = store.category(for: code)
                if category == .night || isNightShift {
                    selectedHourType = .nightShift
                    isNightShift = true
                } else {
                    selectedHourType = .regular
                    isNightShift = false
                }
            }
            
            // Reset manual selection flag on appear
            isManualSelection = false
            
            // Default to text-entry when job is empty; otherwise keep menu
            if jobNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isOtherJobSelected = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { jobNumberFocused = true }
            } else {
                isOtherJobSelected = false
            }
            showSuggestions = false
        }
        .onChange(of: code) { _, newCode in
            // Only auto-update selectedHourType if it wasn't manually selected
            // and the entry isn't marked as overtime
            if !isManualSelection && !isOvertime {
                let category = store.category(for: newCode)
                if category == .night {
                    selectedHourType = .nightShift
                    isNightShift = true
                } else {
                    selectedHourType = .regular
                    isNightShift = false
                }
            }
        }
        .onDisappear { syncHoursFromText() }
        .sheet(isPresented: $showJobsSettings) {
            NavigationStack {
                JobsSettingsView()
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showEnterCodeSheet) {
            NavigationStack {
                Form {
                    Section(header: Text("Job Code")) {
                        TextField("e.g. 12216", text: $tempJobCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.asciiCapable)
                    }
                }
                .navigationTitle("Enter Job Code")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showEnterCodeSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use") {
                            let code = tempJobCode.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !code.isEmpty {
                                jobNumber = code
                                isOtherJobSelected = false
                                showSuggestions = false
                            }
                            showEnterCodeSheet = false
                        }
                        .disabled(tempJobCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}

// Labour code picker renamed to avoid duplicate type error
private struct EntryRowLabourCodePicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: TimecardStore
    @Binding var code: String

    var body: some View {
        NavigationStack {
            List(store.labourCodes) { item in
                Button {
                    code = item.code
                    dismiss()
                } label: {
                    HStack {
                        Text(item.name).foregroundColor(.primary)
                        Spacer()
                        Text(item.code).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Labour Codes")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
#else
                ToolbarItem { Button("Done") { dismiss() } }
#endif
            }
        }
    }
}

private struct MenuItemWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
