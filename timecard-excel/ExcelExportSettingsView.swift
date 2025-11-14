import SwiftUI

struct ExcelExportSettingsView: View {
    @EnvironmentObject var store: TimecardStore
    @State private var serverURL = ""
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var testMessage = ""
    
    enum ConnectionStatus {
        case unknown, testing, success, failure
        
        var color: Color {
            switch self {
            case .unknown: return .secondary
            case .testing: return .orange
            case .success: return .green
            case .failure: return .red
            }
        }
        
        var systemImage: String {
            switch self {
            case .unknown: return "questionmark.circle"
            case .testing: return "arrow.clockwise"
            case .success: return "checkmark.circle.fill"
            case .failure: return "exclamationmark.triangle.fill"
            }
        }
    }
    
    var body: some View {
        List {
            Section(header: Text("Server Configuration").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Excel Export Server URL")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("https://your-timecard-server.onrender.com", text: $serverURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
#endif
                    
                    Text("This should be the URL of your Go server deployed on Render")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Button(action: testConnection) {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: connectionStatus.systemImage)
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTestingConnection || serverURL.isEmpty)
                    
                    Spacer()
                    
                    if connectionStatus != .unknown {
                        HStack {
                            Image(systemName: connectionStatus.systemImage)
                                .foregroundColor(connectionStatus.color)
                            Text(connectionStatusText)
                                .font(.caption)
                                .foregroundColor(connectionStatus.color)
                        }
                    }
                }
                
                if !testMessage.isEmpty {
                    Text(testMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            
            Section(header: Text("Export Options").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: {
                        Task {
                            await store.exportAndSaveExcel()
                        }
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Export Excel File")
                            Spacer()
                            if store.apiService.isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(store.apiService.isExporting || connectionStatus != .success)
                    
                    Button(action: {
                        Task {
                            await store.exportAndEmailExcel()
                        }
                    }) {
                        HStack {
                            Image(systemName: "envelope")
                            Text("Export & Email Excel File")
                            Spacer()
                            if store.apiService.isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(store.apiService.isExporting || connectionStatus != .success || store.emailRecipients.isEmpty)
                    
                    if store.emailRecipients.isEmpty {
                        Text("Configure email recipients in Email settings to enable email export")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            if let lastError = store.apiService.lastExportError {
                Section(header: Text("Last Export Error").font(.headline)) {
                    Text(lastError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Section(header: Text("Template Information").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Go server should have a `template.xlsx` file that matches your company's timecard format.")
                        .font(.subheadline)
                    
                    Text("The template should include:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Employee name in cell M2")
                        Text("• Date cells in column B (rows 5-11 for regular, 16-22 for OT)")
                        Text("• Hour entries in appropriate columns")
                        Text("• Project/job information columns")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Excel Export")
        .onAppear {
            serverURL = store.serverURL
        }
        .onChange(of: serverURL) { newValue in
            store.serverURL = newValue
            store.apiService.updateServerURL(newValue)
            connectionStatus = .unknown
            testMessage = ""
        }
    }
    
    private var connectionStatusText: String {
        switch connectionStatus {
        case .unknown: return ""
        case .testing: return "Testing..."
        case .success: return "Connected"
        case .failure: return "Failed"
        }
    }
    
    private func testConnection() {
        guard !serverURL.isEmpty else { return }
        
        isTestingConnection = true
        connectionStatus = .testing
        testMessage = "Checking server health..."
        
        Task {
            let isHealthy = await store.apiService.healthCheck()
            
            await MainActor.run {
                isTestingConnection = false
                connectionStatus = isHealthy ? .success : .failure
                testMessage = isHealthy 
                    ? "Server is responding correctly"
                    : "Server is not responding. Check the URL and ensure your server is deployed."
            }
        }
    }
}

#Preview {
    NavigationView {
        ExcelExportSettingsView()
            .environmentObject(TimecardStore.sampleStore)
    }
}