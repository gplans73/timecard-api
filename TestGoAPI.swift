import Foundation

/// Test script for the Go API integration
/// Run this in a Swift Playground or as a standalone script to test the API

struct TestGoAPI {
    
    static func main() async {
        print("🧪 Testing Go API Integration\n")
        
        await testHealthCheck()
        await testGenerateTimecard()
        // await testEmailTimecard() // Uncomment when SMTP is configured
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
                    overtime: false
                ),
                GoTimecardRequest.GoEntry(
                    date: "2025-01-07T00:00:00Z",
                    job_code: "JOB001",
                    hours: 8.5,
                    overtime: false
                ),
                GoTimecardRequest.GoEntry(
                    date: "2025-01-07T00:00:00Z",
                    job_code: "JOB002",
                    hours: 2.0,
                    overtime: true
                )
            ]
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
                // Save to desktop for inspection
                let desktop = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                let fileURL = desktop.appendingPathComponent("test_timecard.xlsx")
                
                try? data.write(to: fileURL)
                print("   Saved to: \(fileURL.path)")
                print("✅ Generate timecard passed\n")
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Generate timecard failed: \(errorMessage)\n")
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
                    overtime: false
                )
            ],
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

// Run tests
Task {
    await TestGoAPI.main()
}

// Keep the process alive long enough to complete async operations
RunLoop.main.run(until: Date().addingTimeInterval(30))
