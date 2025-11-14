import SwiftUI

struct ExcelExportButton: View {
    @EnvironmentObject var store: TimecardStore
    @State private var showingExportOptions = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        Button(action: {
            showingExportOptions = true
        }) {
            HStack {
                Image(systemName: "doc.badge.arrow.up")
                Text("Export Excel")
            }
        }
        .disabled(store.apiService.isExporting)
        .confirmationDialog("Excel Export Options", isPresented: $showingExportOptions, titleVisibility: .visible) {
            Button("Download Excel File") {
                Task {
                    await exportExcel(sendEmail: false)
                }
            }
            
            Button("Email Excel File") {
                Task {
                    await exportExcel(sendEmail: true)
                }
            }
            .disabled(store.emailRecipients.isEmpty)
            
            Button("Cancel", role: .cancel) { }
        } message: {
            if store.emailRecipients.isEmpty {
                Text("Configure email recipients in settings to enable email export")
            } else {
                Text("Choose how to export your timecard using your template format")
            }
        }
        .alert("Export Result", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func exportExcel(sendEmail: Bool) async {
        do {
            if sendEmail {
                _ = try await store.exportToExcel(sendEmail: true)
                await MainActor.run {
                    alertMessage = "Excel timecard has been generated and emailed successfully!"
                    showingAlert = true
                }
            } else {
                let excelData = try await store.exportToExcel(sendEmail: false)
                await store.saveExcelFile(data: excelData)
                await MainActor.run {
                    alertMessage = "Excel file has been generated and is ready to save!"
                    showingAlert = true
                }
            }
        } catch {
            await MainActor.run {
                alertMessage = "Export failed: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}

// MARK: - Progress Overlay
struct ExcelExportProgressView: View {
    @EnvironmentObject var store: TimecardStore
    
    var body: some View {
        if store.apiService.isExporting {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    
                    Text("Generating Excel Timecard...")
                        .font(.headline)
                    
                    Text("Using your template format")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(24)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 8)
            }
        }
    }
}

#Preview {
    VStack {
        ExcelExportButton()
        ExcelExportProgressView()
    }
    .environmentObject(TimecardStore.sampleStore)
}