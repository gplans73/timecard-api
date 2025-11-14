import Foundation
import Combine

// MARK: - API Request/Response Models (Matching Go API)

/// Request structure matching Go's TimecardRequest
struct GoTimecardRequest: Codable {
    let employee_name: String
    let pay_period_num: Int
    let year: Int
    let week_start_date: String // ISO 8601 format
    let week_number_label: String
    let jobs: [GoJob]
    let entries: [GoEntry]
    let weeks: [WeekData]? // Optional array for multi-week support
    
    struct GoJob: Codable {
        let job_code: String
        let job_name: String
    }
    
    struct GoEntry: Codable {
        let date: String // ISO 8601 format
        let job_code: String
        let hours: Double
        let overtime: Bool
        let night_shift: Bool
    }
    
    struct WeekData: Codable {
        let week_number: Int
        let week_start_date: String
        let week_label: String
        let entries: [GoEntry]
    }
}

/// Request for emailing timecard via Go API
struct GoEmailTimecardRequest: Codable {
    let employee_name: String
    let pay_period_num: Int
    let year: Int
    let week_start_date: String
    let week_number_label: String
    let jobs: [GoTimecardRequest.GoJob]
    let entries: [GoTimecardRequest.GoEntry]
    let weeks: [GoTimecardRequest.WeekData]? // Optional array for multi-week support
    let to: String      // Comma-separated email addresses
    let cc: String?     // Optional CC addresses
    let subject: String
    let body: String
}

// MARK: - API Service
@MainActor
class TimecardAPIService: ObservableObject {
    static let shared = TimecardAPIService()
    
    // Your deployed Render.com API URL
    private let baseURL = "https://timecard-api.onrender.com"
    
    // Use the deployed URL
    private var apiBaseURL: String {
        return baseURL
    }
    
    private init() {}
    
    enum APIError: Error, LocalizedError {
        case invalidURL
        case noData
        case invalidResponse
        case serverError(String)
        case networkError(Error)
        case apiNotConfigured
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .noData:
                return "No data received from server"
            case .invalidResponse:
                return "Invalid response format"
            case .serverError(let message):
                return "Server error: \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .apiNotConfigured:
                return "API not configured - using local file generation instead"
            }
        }
    }
    
    /// Generate Excel and PDF files via Go API
    func generateTimecardFiles(
        employeeName: String,
        emailRecipients: [String],
        entries: [EntryModel],
        weekStart: Date,
        weekEnd: Date,
        weekNumber: Int,
        totalWeeks: Int,
        ppNumber: Int
    ) async throws -> (excelData: Data, pdfData: Data) {
        
        guard let excelURL = URL(string: "\(apiBaseURL)/api/generate-timecard"),
              let pdfURL = URL(string: "\(apiBaseURL)/api/generate-pdf") else {
            throw APIError.invalidURL
        }
        
        // ISO 8601 date formatter for Go API
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        // Extract unique jobs from entries
        let uniqueJobs = extractUniqueJobs(from: entries)
        
        // Convert entries to Go API format
        let goEntries = entries.map { entry in
            GoTimecardRequest.GoEntry(
                date: isoFormatter.string(from: entry.date),
                job_code: entry.jobNumber,
                hours: entry.hours,
                overtime: entry.isOvertime,
                night_shift: entry.isNightShift
            )
        }
        
        // Build week label - for single week only
        let weekLabel = "Week \(weekNumber)"
        
        let calendar = Calendar.current
        let year = calendar.component(.year, from: weekStart)
        
        // Determine if we need multi-week support
        let weeksData: [GoTimecardRequest.WeekData]?
        if totalWeeks > 1 {
            // Group entries by week and create separate week data
            weeksData = groupEntriesByWeek(entries: entries, startDate: weekStart, totalWeeks: totalWeeks, isoFormatter: isoFormatter)
        } else {
            weeksData = nil
        }
        
        let request = GoTimecardRequest(
            employee_name: employeeName,
            pay_period_num: ppNumber,
            year: year,
            week_start_date: isoFormatter.string(from: weekStart),
            week_number_label: weekLabel,
            jobs: uniqueJobs,
            entries: goEntries,
            weeks: weeksData
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let requestBody: Data
        do {
            requestBody = try encoder.encode(request)
            
            // Debug: Print the JSON being sent
            if let jsonString = String(data: requestBody, encoding: .utf8) {
                print("📤 Sending to Go API:\n\(jsonString)")
            }
        } catch {
            throw APIError.networkError(error)
        }
        
        // Call both APIs in parallel
        async let excelTask: Data = {
            var urlRequest = URLRequest(url: excelURL)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = requestBody
            
            do {
                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                if httpResponse.statusCode != 200 {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw APIError.serverError("Excel HTTP \(httpResponse.statusCode): \(errorMessage)")
                }
                
                print("✅ Received Excel file: \(data.count) bytes")
                return data
                
            } catch let error as APIError {
                throw error
            } catch {
                throw APIError.networkError(error)
            }
        }()
        
        async let pdfTask: Data = {
            var urlRequest = URLRequest(url: pdfURL)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = requestBody
            
            do {
                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                if httpResponse.statusCode != 200 {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("⚠️ PDF generation failed: HTTP \(httpResponse.statusCode): \(errorMessage)")
                    return Data() // Return empty data instead of throwing
                }
                
                print("✅ Received PDF file: \(data.count) bytes")
                return data
                
            } catch {
                print("⚠️ PDF generation failed: \(error.localizedDescription)")
                return Data() // Return empty data instead of throwing
            }
        }()
        
        // Wait for both to complete
        let excelData = try await excelTask
        let pdfData = await pdfTask
        
        return (excelData: excelData, pdfData: pdfData)
    }
    
    /// Group entries by week for multi-week timecard generation
    private func groupEntriesByWeek(entries: [EntryModel], startDate: Date, totalWeeks: Int, isoFormatter: ISO8601DateFormatter) -> [GoTimecardRequest.WeekData] {
        var weekDataArray: [GoTimecardRequest.WeekData] = []
        let calendar = Calendar.current
        
        for weekIndex in 0..<totalWeeks {
            // Calculate week start date
            guard let weekStart = calendar.date(byAdding: .day, value: weekIndex * 7, to: startDate) else {
                continue
            }
            
            // Calculate week end date (6 days later)
            guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                continue
            }
            
            // Filter entries for this week
            let weekEntries = entries.filter { entry in
                entry.date >= weekStart && entry.date <= weekEnd
            }
            
            // Convert to Go format
            let goEntries = weekEntries.map { entry in
                GoTimecardRequest.GoEntry(
                    date: isoFormatter.string(from: entry.date),
                    job_code: entry.jobNumber,
                    hours: entry.hours,
                    overtime: entry.isOvertime,
                    night_shift: entry.isNightShift
                )
            }
            
            // Create week data
            let weekData = GoTimecardRequest.WeekData(
                week_number: weekIndex + 1,
                week_start_date: isoFormatter.string(from: weekStart),
                week_label: "Week \(weekIndex + 1)",
                entries: goEntries
            )
            
            weekDataArray.append(weekData)
        }
        
        return weekDataArray
    }
    
    /// Send timecard via email through Go API
    func emailTimecard(
        employeeName: String,
        emailRecipients: [String],
        ccRecipients: [String] = [],
        subject: String,
        body: String,
        entries: [EntryModel],
        weekStart: Date,
        weekEnd: Date,
        weekNumber: Int,
        totalWeeks: Int,
        ppNumber: Int
    ) async throws {
        
        guard let url = URL(string: "\(apiBaseURL)/api/email-timecard") else {
            throw APIError.invalidURL
        }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let uniqueJobs = extractUniqueJobs(from: entries)
        
        let goEntries = entries.map { entry in
            GoTimecardRequest.GoEntry(
                date: isoFormatter.string(from: entry.date),
                job_code: entry.jobNumber,
                hours: entry.hours,
                overtime: entry.isOvertime,
                night_shift: entry.isNightShift
            )
        }
        
        // Build week label - for single week only
        let weekLabel = "Week \(weekNumber)"
        
        let calendar = Calendar.current
        let year = calendar.component(.year, from: weekStart)
        
        // Determine if we need multi-week support
        let weeksData: [GoTimecardRequest.WeekData]?
        if totalWeeks > 1 {
            // Group entries by week and create separate week data
            weeksData = groupEntriesByWeek(entries: entries, startDate: weekStart, totalWeeks: totalWeeks, isoFormatter: isoFormatter)
        } else {
            weeksData = nil
        }
        
        let request = GoEmailTimecardRequest(
            employee_name: employeeName,
            pay_period_num: ppNumber,
            year: year,
            week_start_date: isoFormatter.string(from: weekStart),
            week_number_label: weekLabel,
            jobs: uniqueJobs,
            entries: goEntries,
            weeks: weeksData,
            to: emailRecipients.joined(separator: ", "),
            cc: ccRecipients.isEmpty ? nil : ccRecipients.joined(separator: ", "),
            subject: subject,
            body: body
        )
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        do {
            urlRequest.httpBody = try encoder.encode(request)
            
            // Debug: Print the JSON being sent
            if let jsonString = String(data: urlRequest.httpBody!, encoding: .utf8) {
                print("📤 Sending email request to Go API:\n\(jsonString)")
            }
        } catch {
            throw APIError.networkError(error)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }
            
            print("✅ Email sent successfully via Go API")
            
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    // MARK: - Helper Functions
    
    /// Extract unique jobs from entries
    private func extractUniqueJobs(from entries: [EntryModel]) -> [GoTimecardRequest.GoJob] {
        var jobDict: [String: String] = [:] // job_code -> job_name
        
        for entry in entries {
            if !entry.jobNumber.isEmpty && jobDict[entry.jobNumber] == nil {
                // Use code as job name if we don't have better info
                // You might want to enhance this by looking up from a jobs database
                let jobName = entry.code.isEmpty ? entry.jobNumber : entry.code
                jobDict[entry.jobNumber] = jobName
            }
        }
        
        return jobDict.map { code, name in
            GoTimecardRequest.GoJob(job_code: code, job_name: name)
        }.sorted { $0.job_code < $1.job_code }
    }
}
