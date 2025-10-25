import SwiftUI

// Use the same ToolbarButton type as JobCodeTextField for consistency
struct ToolbarButton: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var code: String
    
    init(title: String, code: String) {
        self.title = title
        self.code = code
    }
}

struct ToolbarButtonsSettingsView: View {
    @AppStorage("toolbarButtons") private var toolbarButtonsData = Data()
    
    @State private var toolbarButtons: [ToolbarButton] = []
    @Environment(\.editMode) private var editMode
    
    private var isEditing: Bool {
        editMode?.wrappedValue == .active
    }
    
    var body: some View {
        List {
            Section(header: Text("Toolbar Buttons")) {
                ForEach(toolbarButtons.indices, id: \.self) { index in
                    if isEditing {
                        HStack(spacing: 12) {
                            TextField("Button Text", text: $toolbarButtons[index].title)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                                .frame(maxWidth: 100)
                                .onChange(of: toolbarButtons[index].title) { _ in
                                    saveButtons()
                                }

                            TextField("Code", text: $toolbarButtons[index].code)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospacedDigit())
                                .onChange(of: toolbarButtons[index].code) { _ in
                                    saveButtons()
                                }
                        }
                    } else {
                        HStack {
                            Text(toolbarButtons[index].title)
                                .font(.body)
                            Spacer()
                            Text(toolbarButtons[index].code)
                                .font(.body.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    deleteButton(offsets: offsets)
                }
                .onMove { source, destination in
                    moveButton(from: source, to: destination)
                }
            }
            
            if isEditing {
                Section {
                    Button(action: addButton) {
                        Label("Add Button", systemImage: "plus")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            Section(footer: Text("These buttons will appear in the job code input toolbar. ")
                                + Text("Maximum of 4 buttons will fit; additional buttons may be hidden or truncated.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                + Text(" Tap a button to quickly insert its code.")) {
                EmptyView()
            }
        }
        .navigationTitle("Toolbar Buttons")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
#if os(iOS)
        .navigationBarItems(trailing: EditButton())
#else
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
#endif
        .onAppear {
            loadButtons()
        }
        .onDisappear {
            saveButtons()
        }
    }
    
    private func loadButtons() {
        if toolbarButtonsData.isEmpty {
            // Set default buttons if no data exists
            toolbarButtons = [
                ToolbarButton(title: "L", code: "L"),
                ToolbarButton(title: "C", code: "C")
            ]
            saveButtons()
        } else if let buttons = try? JSONDecoder().decode([ToolbarButton].self, from: toolbarButtonsData) {
            toolbarButtons = buttons
        } else {
            // Fallback to default buttons if decoding fails
            toolbarButtons = [
                ToolbarButton(title: "L", code: "L"),
                ToolbarButton(title: "C", code: "C")
            ]
            saveButtons()
        }
    }
    
    private func saveButtons() {
        if let data = try? JSONEncoder().encode(toolbarButtons) {
            toolbarButtonsData = data
        }
    }
    
    private func addButton() {
        let newButton = ToolbarButton(title: "", code: "")
        toolbarButtons.append(newButton)
        saveButtons()
    }
    
    private func deleteButton(offsets: IndexSet) {
        toolbarButtons.remove(atOffsets: offsets)
        saveButtons()
    }
    
    private func moveButton(from source: IndexSet, to destination: Int) {
        toolbarButtons.move(fromOffsets: source, toOffset: destination)
        saveButtons()
    }
}

#Preview {
    NavigationStack {
        ToolbarButtonsSettingsView()
    }
}

