import SwiftUI

/// A debug view that shows Excel formula fix diagnostics
/// Can be used during development to verify the fix is working
struct ExcelDiagnosticsView: View {
    let excelData: Data
    @State private var diagnostics: ExcelDiagnostics?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Excel File Diagnostics")
                .font(.headline)
            
            if let diag = diagnostics {
                Group {
                    infoRow("File Size", ByteCountFormatter.string(fromByteCount: Int64(diag.fileSize), countStyle: .file))
                    infoRow("Entries", "\(diag.entryCount)")
                    infoRow("Worksheets", "\(diag.worksheetCount)")
                    
                    if let calcMode = diag.calcMode {
                        infoRow("Calc Mode", calcMode, calcMode == "auto" ? .green : .orange)
                    }
                    
                    if diag.hasCalcPr {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Has calcPr element")
                            Spacer()
                        }
                    }
                    
                    if diag.hasCalcChain {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Has calcChain")
                            Spacer()
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Image(systemName: diag.needsFormulaFix ? "wrench.fill" : "checkmark.circle.fill")
                            .foregroundColor(diag.needsFormulaFix ? .orange : .green)
                        Text(diag.needsFormulaFix ? "Needs Formula Fix" : "Formulas OK")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                
                if let error = diag.error {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            } else {
                ProgressView("Analyzing...")
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
        .onAppear {
            analyzeDiagnostics()
        }
    }
    
    private func infoRow(_ label: String, _ value: String, _ color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(color)
        }
    }
    
    private func analyzeDiagnostics() {
        DispatchQueue.global(qos: .userInitiated).async {
            let diag = ExcelFormulaFixer.diagnose(excelData)
            DispatchQueue.main.async {
                diagnostics = diag
            }
        }
    }
}

// MARK: - Formula Fix Status Badge

/// A small badge that shows if an Excel file needs formula fixing
/// Use this in your UI to show users that the fix was applied
struct FormulaFixBadge: View {
    let wasFixed: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "function")
                .font(.caption)
            Text(wasFixed ? "Formulas Fixed" : "Original")
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(wasFixed ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
        .foregroundColor(wasFixed ? .green : .secondary)
        .cornerRadius(8)
    }
}

// MARK: - Usage Example View

struct ExcelFormulaFixerDemoView: View {
    @State private var showDiagnostics = false
    @State private var excelData: Data?
    @State private var fixedExcelData: Data?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let data = excelData {
                    ExcelDiagnosticsView(excelData: data)
                    
                    if let fixed = fixedExcelData {
                        ExcelDiagnosticsView(excelData: fixed)
                        
                        HStack(spacing: 16) {
                            shareButton(data: data, label: "Share Original")
                            shareButton(data: fixed, label: "Share Fixed")
                        }
                    }
                    
                    Button(action: fixFormulas) {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Label("Fix Formulas", systemImage: "wrench.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing || fixedExcelData != nil)
                    
                } else {
                    ContentUnavailableView(
                        "No Excel File",
                        systemImage: "doc.text",
                        description: Text("Load an Excel file from your Go API to test the formula fixer")
                    )
                    
                    Button("Load Test File") {
                        loadTestFile()
                    }
                    .buttonStyle(.bordered)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding()
            .navigationTitle("Formula Fixer Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func shareButton(data: Data, label: String) -> some View {
        ShareLink(
            item: data,
            preview: SharePreview(
                label,
                image: Image(systemName: "doc.text")
            )
        ) {
            Label(label, systemImage: "square.and.arrow.up")
                .font(.caption)
        }
        .buttonStyle(.bordered)
    }
    
    private func loadTestFile() {
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                // Download a test file from the API
                guard let url = URL(string: "https://timecard-api.onrender.com/api/generate-timecard") else {
                    throw URLError(.badURL)
                }
                
                let request = GoTimecardRequest(
                    employee_name: "Test User",
                    pay_period_num: 1,
                    year: 2025,
                    week_start_date: "2025-01-06T00:00:00Z",
                    week_number_label: "Week 1",
                    jobs: [GoTimecardRequest.GoJob(job_code: "TEST", job_name: "Test Job")],
                    entries: [
                        GoTimecardRequest.GoEntry(
                            date: "2025-01-06T00:00:00Z",
                            job_code: "TEST",
                            hours: 8.0,
                            overtime: false
                        )
                    ]
                )
                
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = try JSONEncoder().encode(request)
                urlRequest.timeoutInterval = 60
                
                let (data, _) = try await URLSession.shared.data(for: urlRequest)
                
                await MainActor.run {
                    excelData = data
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
    
    private func fixFormulas() {
        guard let data = excelData else { return }
        
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let fixed = try ExcelFormulaFixer.fixFormulas(in: data)
                
                await MainActor.run {
                    fixedExcelData = fixed
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Fix failed: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ExcelFormulaFixerDemoView()
}
