import Foundation

// MARK: - API Models
struct TimecardExportRequest: Codable {
    let employeeName: String
    let weekNumber: Int
    let rows: [TimecardRow]
    let totalOC: Double  // Total regular/on-call hours
    let totalOT: Double  // Total overtime hours
    let sendEmail: Bool
    let emailTo: [String]?
    let emailSubject: String?
    let emailBody: String?
}

struct TimecardRow: Codable {
    let date: String        // "2024-11-04"
    let project: String
    let hours: Double
    let type: String        // "Regular", "OT", etc.
    let notes: String
}

struct TimecardExportResponse: Codable {
    let success: Bool
    let message: String?
    let emailSent: Bool?
}

// MARK: - API Service
@MainActor
class TimecardAPIService: ObservableObject {
    // Update this to your actual Render URL
    private let baseURL = "https://your-timecard-server.onrender.com"
    
    @Published var isExporting = false
    @Published var lastExportError: String?
    
    /// Export timecard as Excel file and optionally email it
    func exportTimecard(
        employeeName: String,
        weekStart: Date,
        entries: [EntryModel],
        sendEmail: Bool = false,
        emailRecipients: [String] = [],
        emailSubject: String? = nil,
        emailBody: String? = nil
    ) async throws -> Data {
        
        isExporting = true
        lastExportError = nil
        
        defer { isExporting = false }
        
        // Determine week number (1 or 2)
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: weekStart)
        let weekNumber = (weekOfYear % 2) + 1  // Alternates between 1 and 2
        
        // Convert entries to API format
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let rows = entries.map { entry in
            TimecardRow(
                date: formatter.string(from: entry.date),
                project: entry.jobModel?.name ?? "Unknown",
                hours: entry.hours,
                type: entry.labourCodeModel?.name ?? "Regular",
                notes: entry.notes ?? ""
            )
        }
        
        // Calculate totals
        let regularHours = entries.filter { 
            $0.labourCodeModel?.name?.lowercased().contains("regular") == true ||
            $0.labourCodeModel?.name?.lowercased().contains("oc") == true
        }.reduce(0) { $0 + $1.hours }
        
        let overtimeHours = entries.filter {
            $0.labourCodeModel?.name?.lowercased().contains("ot") == true ||
            $0.labourCodeModel?.name?.lowercased().contains("overtime") == true
        }.reduce(0) { $0 + $1.hours }
        
        // Create request
        let request = TimecardExportRequest(
            employeeName: employeeName,
            weekNumber: weekNumber,
            rows: rows,
            totalOC: regularHours,
            totalOT: overtimeHours,
            sendEmail: sendEmail,
            emailTo: sendEmail ? emailRecipients : nil,
            emailSubject: emailSubject,
            emailBody: emailBody
        )
        
        // Make API call
        guard let url = URL(string: "\(baseURL)/excel") else {
            throw TimecardAPIError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TimecardAPIError.invalidResponse
            }
            
            if httpResponse.statusCode == 200 {
                // Success - return the Excel file data
                return data
            } else {
                // Try to parse error response
                if let errorResponse = try? JSONDecoder().decode(TimecardExportResponse.self, from: data) {
                    throw TimecardAPIError.serverError(errorResponse.message ?? "Unknown server error")
                } else {
                    throw TimecardAPIError.httpError(httpResponse.statusCode)
                }
            }
        } catch let error as TimecardAPIError {
            lastExportError = error.localizedDescription
            throw error
        } catch {
            lastExportError = error.localizedDescription
            throw TimecardAPIError.networkError(error)
        }
    }
    
    /// Check if the API server is healthy
    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// Update the server URL (for settings)
    func updateServerURL(_ newURL: String) {
        // You might want to store this in UserDefaults or similar
        // For now, this would require app restart to take effect
        print("Server URL update requested: \(newURL)")
        print("Note: Restart app for changes to take effect, or implement dynamic URL updating")
    }
}

// MARK: - Error Types
enum TimecardAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case serverError(String)
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}