import SwiftUI
import UniformTypeIdentifiers

struct JobsSettingsView: View {
    @Environment(\.editMode) private var editMode
    @EnvironmentObject var store: TimecardStore
    @SwiftUI.State private var isEditing: Bool = false
    @SwiftUI.State private var showImportSheet: Bool = false
    @SwiftUI.State private var importText: String = ""

    @SwiftUI.State private var showFileImporter: Bool = false
    @SwiftUI.State private var importedJobs: [Job] = []
    @SwiftUI.State private var showImportChoice: Bool = false

    var body: some View {
        List {
            Section(header: Text("Jobs")) {
                if isEditing {
                    ForEach($store.jobs) { $job in
                        HStack(spacing: 12) {
                            TextField("Job Name", text: $job.name)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                            Spacer(minLength: 8)
                            TextField("Code", text: $job.code)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospacedDigit())
                                .frame(width: 80)
                        }
                    }
                    .onDelete { offsets in
                        store.jobs.remove(atOffsets: offsets)
                    }
                    .onMove { indices, newOffset in
                        store.jobs.move(fromOffsets: indices, toOffset: newOffset)
                    }
                } else {
                    ForEach(store.jobs) { job in
                        HStack {
                            Text(job.name)
                                .font(.body)
                            Spacer()
                            Text(job.code)
                                .font(.body.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        store.jobs.remove(atOffsets: offsets)
                    }
                    .onMove { indices, newOffset in
                        store.jobs.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
            }
        }
        .navigationTitle("Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Removed the original leading reorder toggle button here

            // Leading: Add Job only while editing
            if isEditing {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Add Job") { store.jobs.append(Job(name: "New Job", code: "")) }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    withAnimation { editMode?.wrappedValue = (editMode?.wrappedValue == .active ? .inactive : .active) }
                }) {
                    if editMode?.wrappedValue == .active {
                        Label("Done", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Reorder", systemImage: "arrow.up.arrow.down.circle")
                    }
                }
            }

            // Trailing: One compact overflow menu
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Edit toggle
                    Button(isEditing ? "Done Editing" : "Edit") { isEditing.toggle() }

                    Divider()

                    // Import options
                    Button("Import…") { showImportSheet = true }
                    Button("Import File…") { showFileImporter = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            NavigationStack {
                JobsImportView(importText: $importText, onReplaceAll: { items in
                    // Replace entire list with imported items
                    store.jobs = items
                    showImportSheet = false
                }, onAppend: { items in
                    // Append, de-duplicating by code
                    var existingByCode = Dictionary(uniqueKeysWithValues: store.jobs.map { ($0.code.uppercased(), $0) })
                    for it in items {
                        let key = it.code.uppercased()
                        if existingByCode[key] == nil {
                            existingByCode[key] = it
                        }
                    }
                    store.jobs = Array(existingByCode.values).sorted { $0.name < $1.name }
                    showImportSheet = false
                })
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let data = try Data(contentsOf: url)
                    // Try UTF-8, then fall back to MacRoman if needed
                    let text = String(data: data, encoding: .utf8) ?? (String(data: data, encoding: .macOSRoman) ?? "")
                    let parsed = TimecardStore.parseJobsCSV(text)
                    if !parsed.isEmpty {
                        importedJobs = parsed
                        showImportChoice = true
                    }
                } catch {
                    // Ignore parse errors silently for now; could surface an alert if desired
                }
            case .failure:
                break
            }
        }
        .confirmationDialog("Import Jobs", isPresented: $showImportChoice, titleVisibility: .visible) {
            Button("Replace All", role: .destructive) {
                store.jobs = importedJobs
            }
            Button("Append (Skip Duplicates)") {
                var existingByCode = Dictionary(uniqueKeysWithValues: store.jobs.map { ($0.code.uppercased(), $0) })
                for it in importedJobs {
                    let key = it.code.uppercased()
                    if existingByCode[key] == nil {
                        existingByCode[key] = it
                    }
                }
                store.jobs = Array(existingByCode.values).sorted { $0.name < $1.name }
            }
            Button("Cancel", role: .cancel) {}
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#else
        .listStyle(.inset)
#endif
        .environment(\.editMode, editMode)
    }
}

private struct JobsImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var importText: String
    let onReplaceAll: ([Job]) -> Void
    let onAppend: ([Job]) -> Void

    @State private var parsed: [Job] = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(footer: Text("Paste lines like: L2439, Seven Nations NC or 2439\tSeven Nations NC").font(.footnote).foregroundStyle(.secondary)) {
                    TextEditor(text: $importText)
                        .frame(minHeight: 220)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: importText) { _ in parsed = parse(importText) }
                        .onAppear { parsed = parse(importText) }
                }
                Section("Preview (\(parsed.count))") {
                    if parsed.isEmpty {
                        Text("No jobs parsed yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(parsed) { j in
                            HStack {
                                Text(j.code).font(.body.monospacedDigit())
                                Text("—").foregroundStyle(.secondary)
                                Text(j.name)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Import Jobs")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Menu("Add") {
                    Button("Replace All") { onReplaceAll(parsed) }
                    Button("Append (Skip Duplicates)") { onAppend(parsed) }
                }
                .disabled(parsed.isEmpty)
            }
        }
    }

    private func parse(_ text: String) -> [Job] {
        let separators = CharacterSet(charactersIn: ",\t|")
        var results: [Job] = []
        let lines = text.split(whereSeparator: { $0.isNewline })
        for lineSub in lines {
            let line = String(lineSub).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            // Try CSV/TSV split first
            var parts = line.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if parts.count < 2 {
                // Fallback: split on first space: CODE NAME...
                if let space = line.firstIndex(of: " ") {
                    let code = String(line[..<space]).trimmingCharacters(in: .whitespaces)
                    let name = String(line[space...]).trimmingCharacters(in: .whitespaces)
                    if !code.isEmpty && !name.isEmpty { parts = [code, name] }
                }
            }
            guard parts.count >= 2 else { continue }
            let code = parts[0]
            let name = parts.dropFirst().joined(separator: " ")
            results.append(Job(name: name, code: code))
        }
        // Deduplicate by code (keep first occurrence), stable order
        var seen: Set<String> = []
        var dedup: [Job] = []
        for j in results {
            let key = j.code.uppercased()
            if !seen.contains(key) { seen.insert(key); dedup.append(j) }
        }
        return dedup
    }
}

#Preview {
    NavigationStack {
        JobsSettingsView().environmentObject(TimecardStore.sampleStore)
    }
}
