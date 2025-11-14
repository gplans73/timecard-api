import Foundation

#if canImport(Compression)
import Compression

// MARK: - Excel Download Test
// This extension downloads Excel files from the API for manual testing
// No dependency on ExcelFormulaFixer - just saves files for you to inspect

extension TestGoAPI {
    
    /// Download and save Excel file for manual inspection
    /// This is useful for testing without requiring ExcelFormulaFixer
    static func testExcelDownload() async {
        print("3️⃣ Testing Excel File Download...")
        
        // Generate a timecard from the API
        guard let url = URL(string: "https://timecard-api.onrender.com/api/generate-timecard") else {
            print("❌ Invalid URL")
            return
        }
        
        let request = GoTimecardRequest(
            employee_name: "Test Employee",
            pay_period_num: 1,
            year: 2025,
            week_start_date: "2025-01-06T00:00:00Z",
            week_number_label: "Week 1",
            jobs: [
                GoTimecardRequest.GoJob(job_code: "JOB001", job_name: "Test Job")
            ],
            entries: [
                GoTimecardRequest.GoEntry(
                    date: "2025-01-06T00:00:00Z",
                    job_code: "JOB001",
                    hours: 8.0,
                    overtime: false,
                    night_shift: false
                ),
                GoTimecardRequest.GoEntry(
                    date: "2025-01-07T00:00:00Z",
                    job_code: "JOB001",
                    hours: 7.5,
                    overtime: false,
                    night_shift: false
                )
            ],
            weeks: nil
        )
        
        let encoder = JSONEncoder()
        guard let requestBody = try? encoder.encode(request) else {
            print("❌ Failed to encode request")
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = requestBody
        urlRequest.timeoutInterval = 60
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ Failed to get Excel file from API")
                return
            }
            
            print("   ✓ Downloaded Excel file (\(data.count) bytes)")
            
            // Save for manual inspection
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let testURL = documentsDirectory.appendingPathComponent("api_test_download.xlsx")
            
            try data.write(to: testURL)
            
            print("\n   ✓ Saved Excel file:")
            print("      Location: \(testURL.path)")
            print("   💡 Open this file in Excel to verify formulas and content")
            print("✅ Excel download test passed\n")
            
        } catch {
            print("❌ Error: \(error.localizedDescription)\n")
        }
    }
}

#endif
