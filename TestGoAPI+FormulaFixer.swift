import Foundation

#if canImport(Compression)
import Compression

// MARK: - Excel Formula Fixer Tests
// This is an extension file that adds ExcelFormulaFixer testing to TestGoAPI
// Only include this file in your target if ExcelFormulaFixer.swift is also included

extension TestGoAPI {
    
    /// Test the ExcelFormulaFixer functionality
    /// This method is only available when this extension file is included in the target
    static func testExcelFormulaFixer() async {
        print("3️⃣ Testing ExcelFormulaFixer...")
        
        // First, generate a timecard from the API
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
                    overtime: false
                ),
                GoTimecardRequest.GoEntry(
                    date: "2025-01-07T00:00:00Z",
                    job_code: "JOB001",
                    hours: 7.5,
                    overtime: false
                )
            ]
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
            
            // Diagnose the original file
            let originalDiag = ExcelFormulaFixer.diagnose(data)
            print("\n   📋 Original File:")
            print(originalDiag.description.split(separator: "\n").map { "   \($0)" }.joined(separator: "\n"))
            
            // Test the formula fixer
            do {
                let fixedData = try ExcelFormulaFixer.fixFormulas(in: data)
                print("\n   ✓ Fixed formulas successfully")
                
                // Diagnose the fixed file
                let fixedDiag = ExcelFormulaFixer.diagnose(fixedData)
                print("\n   📋 Fixed File:")
                print(fixedDiag.description.split(separator: "\n").map { "   \($0)" }.joined(separator: "\n"))
                
                // Save both versions for comparison
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let originalURL = documentsDirectory.appendingPathComponent("formula_test_original.xlsx")
                let fixedURL = documentsDirectory.appendingPathComponent("formula_test_fixed.xlsx")
                
                try data.write(to: originalURL)
                try fixedData.write(to: fixedURL)
                
                print("\n   ✓ Saved test files:")
                print("      Original: \(originalURL.path)")
                print("      Fixed:    \(fixedURL.path)")
                print("   💡 Open both files in Excel and compare formula behavior")
                print("✅ Formula fixer test passed\n")
                
            } catch {
                print("❌ Formula fixer failed: \(error.localizedDescription)\n")
            }
            
        } catch {
            print("❌ Error: \(error.localizedDescription)\n")
        }
    }
}

#endif
