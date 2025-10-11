import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var store: TimecardStore
    @State private var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            TimeEntryView_FULL_SunSatFriday_ALIGNED()
                .tabItem { Label("Time", systemImage: "clock") }
                .tag(0)

            SendView()
                .tabItem { Label("Send", systemImage: "paperplane.fill") }
                .tag(1)

            Group {
                SummaryTabSimple() // <- use this
            }
            .tabItem { Label("Summary", systemImage: "chart.bar.fill") }
            .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
        .onChange(of: selection) { _, _ in
            finishEditingOnTabChange()
        }
        .tint(store.accentColor)
    }

    private func finishEditingOnTabChange() {
        // TODO: Move the logic that the former "Done" button performed into this method.
        // Example: commit/save pending edits and dismiss the keyboard if needed.
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

