import SwiftUI
import SwiftData

struct BootstrapView: View {
    @StateObject var store: TimecardStore
    @Environment(\.modelContext) private var modelContext

    @State private var jobCode: String = ""
    @FocusState private var isJobCodeFocused: Bool

    init(store: TimecardStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Form {
                    Section("Job") {
                        TextField("Job Code", text: $jobCode)
                            .focused($isJobCodeFocused)
                            .onTapGesture {
                                isJobCodeFocused = true
                            }
                    }
                }

                if isJobCodeFocused {
                    NumericKeypad(
                        insert: { char in
                            jobCode.append(char)
                        },
                        backspace: {
                            if !jobCode.isEmpty { _ = jobCode.removeLast() }
                        },
                        done: {
                            withAnimation(.spring) { isJobCodeFocused = false }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.default, value: isJobCodeFocused)
                }
            }
            .navigationTitle("Enter Job Code")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isJobCodeFocused = false }
                }
            }
        }
        .environmentObject(store)
        .onAppear {
            if #available(iOS 17, macOS 14, *) {
                store.attach(modelContext: modelContext)
            }
        }
    }
}

#Preview {
    BootstrapView(store: TimecardStore.sampleStore)
        .modelContainer(for: [EntryModel.self, LabourCodeModel.self], inMemory: true)
}
