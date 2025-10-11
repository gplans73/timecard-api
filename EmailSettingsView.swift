import SwiftUI

struct EmailSettingsView: View {
    @EnvironmentObject var store: TimecardStore
    @State private var showingEmailPreview = false

    var body: some View {
        List {
            Section(header: Text("Default Recipients").font(.headline)) {
                HStack {
                    TextField("email@company.com; another@company.com", text: Binding(
                        get: { store.defaultEmail },
                        set: { store.defaultEmail = $0 }
                    ))
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
#else
                    .autocorrectionDisabled(true)
#endif

                    Button("Preview") {
                        showingEmailPreview = true
                    }
                    .font(.caption)
                    .foregroundColor(store.accentColor)
                }
                Text("Separate multiple emails with semicolons (;) or commas (,)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if !store.emailRecipients.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parsed Recipients (\(store.emailRecipients.count))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ForEach(Array(store.emailRecipients.enumerated()), id: \.offset) { index, email in
                            Text("• \(email)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Section(header: Text("Subject Template").font(.headline)) {
                TextField("Timecard — {name} — {range}", text: Binding(
                    get: { store.emailSubjectTemplate },
                    set: { store.emailSubjectTemplate = $0 }
                ))
#if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
#else
                .autocorrectionDisabled(true)
#endif

                Text("Available tokens: {name}, {range}, {pp}")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Body Template").font(.headline)) {
                TextEditor(text: Binding(
                    get: { store.emailBodyTemplate },
                    set: { store.emailBodyTemplate = $0 }
                ))
                .frame(minHeight: 120, maxHeight: 180)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

                Text("Available tokens: {name}, {range}, {pp}")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Email")
        .sheet(isPresented: $showingEmailPreview) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
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

                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("To:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(store.emailRecipients.joined(separator: "; "))
                                    .font(.body)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Subject:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(store.emailSubject(for: store.selectedWeekStart))
                                    .font(.body)
                            }
                            Divider()
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
                            showingEmailPreview = false
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    EmailSettingsView().environmentObject(TimecardStore.sampleStore)
}
