import SwiftUI

struct CodesSettingsView: View {
    @EnvironmentObject var store: TimecardStore
    @State private var query: String = ""

    private var filteredCodes: [LabourCode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.labourCodes }
        return store.labourCodes.filter { item in
            item.name.localizedCaseInsensitiveContains(q) ||
            item.code.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List(filteredCodes) { item in
            HStack {
                Text(item.name)
                    .foregroundColor(.primary)
                Spacer()
                Text(item.code)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
        }
        .navigationTitle("Codes")
#if os(iOS)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic))
#endif
    }
}

#Preview {
    NavigationStack { CodesSettingsView().environmentObject(TimecardStore.sampleStore) }
}
