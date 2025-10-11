import SwiftUI

struct CodesAndNotesView: View {
    @EnvironmentObject var store: TimecardStore
    @SwiftUI.State private var isEditing: Bool = false
    
    var body: some View {
        List {
            Section(header: Text("Job Labour Codes")) {
                if isEditing {
                    ForEach($store.labourCodes) { $item in
                        HStack(spacing: 12) {
                            TextField("Title", text: $item.name)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                            Spacer(minLength: 8)
                            TextField("Code", text: $item.code)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospacedDigit())
                                .frame(width: 80)
                        }
                    }
                    .onDelete(perform: deleteLabourCodes)
                } else {
                    ForEach(store.labourCodes) { item in
                        HStack {
                            Text(item.name)
                                .font(.body)
                            Spacer()
                            Text(item.code)
                                .font(.body.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Section(header: Text("General Notes")) {
                TextEditor(text: Binding(
                    get: { store.codeGeneralNotes },
                    set: { store.codeGeneralNotes = $0 }
                ))
                .frame(minHeight: 100, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .navigationTitle("Codes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                }
            }
            
            if isEditing {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Add Code") {
                        addNewLabourCode()
                    }
                }
            }
        }
    }
    
    private func addNewLabourCode() {
        let newCode = LabourCode(name: "New Code", code: "")
        store.labourCodes.append(newCode)
    }
    
    private func deleteLabourCodes(offsets: IndexSet) {
        store.labourCodes.remove(atOffsets: offsets)
    }
}

#Preview {
    NavigationStack {
        CodesAndNotesView()
            .environmentObject(TimecardStore.sampleStore)
    }
}

