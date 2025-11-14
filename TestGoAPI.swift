import Foundation

#if canImport(Compression)
import Compression
#endif

/// Test script for the Go API integration
/// Call TestGoAPI.runTests() from your app or tests to execute
///
/// 📦 **Required Files:**
/// - TimecardAPIService.swift (for API models)
///
/// 📦 **Optional Files:**
/// - TestGoAPI+FormulaFixer.swift (for Excel download testing)

struct TestGoAPI {
    
    static func runTests() async {
        print("🧪 Testing Go API Integration\n")
        
        await testHealthCheck()
        await testGenerateTimecard()
        await testNightShiftSpecifically()
        
        // Note: testExcelDownload() is available if TestGoAPI+FormulaFixer.swift is in your target
        // Uncomment the line below to test Excel file downloads:
        // await testExcelDownload()
        
        // Uncomment to test email functionality (requires SMTP configuration):
        // await testEmailTimecard()
    }
    
    // MARK: - Health Check
    
    static func testHealthCheck() async {
        print("1️⃣ Testing /health endpoint...")
        
        guard let url = URL(string: "https://timecard-api.onrender.com/health") else {
            print("❌ Invalid URL")
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response")
                return
            }
            
            print("   Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("   Response: \(body)")
                print("✅ Health check passed\n")
            } else {
                print("❌ Health check failed\n")
            }
        } catch {
            print("❌ Error: \(error.localizedDescription)\n")
        }
    }
    
    // MARK: - Generate Timecard
    
    static func testGenerateTimecard() async {
        print("2️⃣ Testing /api/generate-timecard endpoint...")
        
        guard let url = URL(string: "https://timecard-api.onrender.com/api/generate-timecard") else {
            print("❌ Invalid URL")
            return
        }
        
        // Create test request
        let request = GoTimecardRequest(
            employee_name: "Test Employee",
            pay_period_num: 1,
            year: 2025,
            week_start_date: "2025-01-06T00:00:00Z",
            week_number_label: "Week 1",
            jobs: [
                GoTimecardRequest.GoJob(job_code: "JOB001", job_name: "Construction Project A"),
                GoTimecardRequest.GoJob(job_code: "JOB002", job_name: "Maintenance Work")
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
                    hours: 8.5,
                    overtime: false,
                    night_shift: false
                ),
                GoTimecardRequest.GoEntry(
                    date: "2025-01-07T00:00:00Z",
                    job_code: "JOB002",
                    hours: 2.0,
                    overtime: true,
                    night_shift: false
                ),
                // TEST: Add a night shift entry to verify it shows in TOTAL NIGHT row
                GoTimecardRequest.GoEntry(
                    date: "2025-01-08T00:00:00Z",
                    job_code: "JOB001",
                    hours: 0.5,
                    overtime: false,
                    night_shift: true
                )
            ],
            weeks: nil // Optional: nil for single-week timecards
        )
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let requestBody = try? encoder.encode(request) else {
            print("❌ Failed to encode request")
            return
        }
        
        // Print the JSON being sent
        if let jsonString = String(data: requestBody, encoding: .utf8) {
            print("   Request JSON:")
            print("   \(jsonString)")
        }
        
        // Create URLRequest
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = requestBody
        urlRequest.timeoutInterval = 60 // 60 seconds for cold start
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response")
                return
            }
            
            print("   Status: \(httpResponse.statusCode)")
            print("   Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            print("   File Size: \(data.count) bytes")
            
            if httpResponse.statusCode == 200 {
                // Save original to documents directory for inspection
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let originalURL = documentsDirectory.appendingPathComponent("test_timecard_original.xlsx")
                
                try? data.write(to: originalURL)
                print("   Saved original to: \(originalURL.path)")
                print("   ℹ️ Formula fix skipped in this test (use testExcelFormulaFixer() for full formula testing)")
                
                
                print("✅ Generate timecard passed\n")
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Generate timecard failed: \(errorMessage)\n")
            }
        } catch {
            print("❌ Error: \(error.localizedDescription)\n")
        }
    }
    
    // MARK: - Night Shift Test
    
    static func testNightShiftSpecifically() async {
        print("🌙 Testing Night Shift Detection...")
        
        guard let url = URL(string: "https://timecard-api.onrender.com/api/generate-timecard") else {
            print("❌ Invalid URL")
            return
        }
        
        // Create a focused test with mixed regular, night, and overtime hours
        let request = GoTimecardRequest(
            employee_name: "Night Shift Test",
            pay_period_num: 1,
            year: 2025,
            week_start_date: "2025-11-10T00:00:00Z",
            week_number_label: "Week 1",
            jobs: [
                GoTimecardRequest.GoJob(job_code: "12215", job_name: "Job 201"),
                GoTimecardRequest.GoJob(job_code: "92408", job_name: "Job 223")
            ],
            entries: [
                // Regular hours on job 12215
                GoTimecardRequest.GoEntry(
                    date: "2025-11-09T00:00:00Z",
                    job_code: "12215",
                    hours: 1.0,
                    overtime: false,
                    night_shift: false
                ),
                // Regular hours on job 201
                GoTimecardRequest.GoEntry(
                    date: "2025-11-10T00:00:00Z",
                    job_code: "12215",
                    hours: 0.5,
                    overtime: false,
                    night_shift: false
                ),
                // NIGHT SHIFT hours on job 92408 - THIS SHOULD APPEAR IN "TOTAL NIGHT" ROW
                GoTimecardRequest.GoEntry(
                    date: "2025-11-10T00:00:00Z",
                    job_code: "92408",
                    hours: 0.5,
                    overtime: false,
                    night_shift: true
                )
            ],
            weeks: nil
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let requestBody = try? encoder.encode(request) else {
            print("❌ Failed to encode request")
            return
        }
        
        print("   🔍 Request JSON:")
        if let jsonString = String(data: requestBody, encoding: .utf8) {
            print(jsonString)
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = requestBody
        urlRequest.timeoutInterval = 60
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response")
                return
            }
            
            print("   Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let testURL = documentsDirectory.appendingPathComponent("test_night_shift.xlsx")
                
                try? data.write(to: testURL)
                print("   ✅ Saved test file to: \(testURL.path)")
                print("   📊 Expected results in Excel:")
                print("      Row 12 (TOTAL REGULAR):")
                print("         - Job 12215: 1.5 hours")
                print("         - Job 92408: 0.0 hours")
                print("      Row 13 (TOTAL NIGHT):")
                print("         - Job 12215: 0.0 hours")
                print("         - Job 92408: 0.5 hours ⭐️ CHECK THIS!")
                print("      Row 14 (Overtime & Double-Time):")
                print("         - All jobs: 0.0 hours")
                print()
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Night shift test failed: \(errorMessage)\n")
            }
        } catch {
            print("❌ Error: \(error.localizedDescription)\n")
        }
    }
    
    // MARK: - Email Timecard (requires SMTP configuration)
    
    static func testEmailTimecard() async {
        print("3️⃣ Testing /api/email-timecard endpoint...")
        
        guard let url = URL(string: "https://timecard-api.onrender.com/api/email-timecard") else {
            print("❌ Invalid URL")
            return
        }
        
        let request = GoEmailTimecardRequest(
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
                )
            ],
            weeks: nil, // Optional: nil for single-week timecards
            to: "test@example.com",
            cc: nil,
            subject: "Test Timecard - Week 1",
            body: "This is a test timecard email."
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
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response")
                return
            }
            
            print("   Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                print("   Response: \(responseBody)")
                print("✅ Email sent successfully\n")
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Email failed: \(errorMessage)\n")
            }
        } catch {
            print("❌ Error: \(error.localizedDescription)\n")
        }
    }
}
