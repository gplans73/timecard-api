import Foundation

// MARK: - Go API Codable Models
// These mirror the Go structs in main.go (snake_case JSON keys)

struct GoEntry: Codable {
    let date: String            // RFC3339 (no fractional seconds)
    let job_code: String        // Labour CODE like "201", "223"
    let hours: Double
    let overtime: Bool
    let is_night_shift: Bool
}

struct GoJob: Codable {
    let job_code: String  // CODE (e.g. "201")
    let job_name: String  // Job NUMBER/Name (e.g. "12215")
}

struct GoWeekData: Codable {
    let week_number: Int
    let week_start_date: String // RFC3339
    let week_label: String
    let entries: [GoEntry]
}

struct GoTimecardRequest: Codable {
    let employee_name: String
    let pay_period_num: Int
    let year: Int
    let week_start_date: String
    let week_number_label: String
    let jobs: [GoJob]
    let entries: [GoEntry]?      // optional; server primarily uses `weeks`
    let weeks: [GoWeekData]
}

struct GoEmailTimecardRequest: Codable {
    // timecard fields
    let employee_name: String
    let pay_period_num: Int
    let year: Int
    let week_start_date: String
    let week_number_label: String
    let jobs: [GoJob]
    let entries: [GoEntry]?
    let weeks: [GoWeekData]
    // email fields
    let to: String
    let cc: String?
    let subject: String
    let body: String
}

// MARK: - API Error

enum TimecardAPIError: Error, LocalizedError {
    case badURL
    case invalidResponse(Int)
    case emptyData

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid API URL"
        case .invalidResponse(let code): return "Server error (status: \(code))"
        case .emptyData: return "Empty response data"
        }
    }
}

// MARK: - Service

/// Service responsible for communicating with the Go backend.
///
/// Usage:
///   let svc = TimecardAPIService.shared
///   svc.setConfiguration(baseURL: "https://timecard-api.onrender.com", apiKey: "<optional>")
///   let data = try await svc.generateExcel(for: store, weeks: [0])
///   try await svc.emailTimecard(from: store, to: ["timecard@logicalgroup.ca"], subject: "...", body: "...", weeks: [0])
@MainActor
final class TimecardAPIService: ObservableObject {
    static let shared = TimecardAPIService()

    /// Base URL of the Go service (e.g. "https://timecard-api.onrender.com")
    @Published var baseURL: String = "http://localhost:8080"
    /// Optional API key if the server enforces X-API-Key
    @Published var apiKey: String? = nil
    /// Enable verbose logging of requests
    @Published var debugLogging: Bool = false

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        // RFC3339 without fractional seconds; Go uses time.RFC3339 in parsing
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private init() {}

    // MARK: - Configuration

    func setConfiguration(baseURL: String, apiKey: String? = nil) {
        // Normalize to no trailing slash for predictable path joining
        var normalized = baseURL
        while normalized.hasSuffix("/") { normalized.removeLast() }
        self.baseURL = normalized
        self.apiKey = apiKey
    }

    // MARK: - Public API

    /// GET /health convenience check
    func health() async -> Bool {
        guard let url = URL(string: baseURL + "/health") else { return false }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
            if debugLogging, let s = String(data: data, encoding: .utf8) { print("[API] /health -> \(s)") }
            return true
        } catch {
            if debugLogging { print("[API] /health error: \(error)") }
            return false
        }
    }

    /// Generates an Excel timecard via the Go API and returns the XLSX data.
    /// - Parameters:
    ///   - store: Source of entries and metadata
    ///   - weeks: Optional list of week indices to include (0-based). Defaults to all weeks in the pay period.
    func generateExcel(for store: TimecardStore, weeks: [Int]? = nil) async throws -> Data {
        let payload = buildTimecardRequest(from: store, weeks: weeks)
        let url = try endpoint("/api/generate-timecard")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty { req.setValue(key, forHTTPHeaderField: "X-API-Key") }
        req.httpBody = try JSONEncoder().encode(payload)
        req.timeoutInterval = 60

        if debugLogging, let body = req.httpBody, let s = String(data: body, encoding: .utf8) {
            print("[API] POST /api/generate-timecard\n\(s)")
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else { throw TimecardAPIError.invalidResponse(code) }
        guard !data.isEmpty else { throw TimecardAPIError.emptyData }
        if debugLogging { print("[API] Received XLSX (\(data.count) bytes)") }
        return data
    }

    /// Sends a timecard email via the Go API (SMTP on server). Returns when the server responds 2xx.
    func emailTimecard(from store: TimecardStore,
                       to: [String],
                       cc: [String]? = nil,
                       subject: String,
                       body: String,
                       weeks: [Int]? = nil) async throws {
        let base = buildTimecardRequest(from: store, weeks: weeks)
        let payload = GoEmailTimecardRequest(
            employee_name: base.employee_name,
            pay_period_num: base.pay_period_num,
            year: base.year,
            week_start_date: base.week_start_date,
            week_number_label: base.week_number_label,
            jobs: base.jobs,
            entries: base.entries,
            weeks: base.weeks,
            to: to.joined(separator: ","),
            cc: cc?.joined(separator: ","),
            subject: subject,
            body: body
        )

        let url = try endpoint("/api/email-timecard")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty { req.setValue(key, forHTTPHeaderField: "X-API-Key") }
        req.httpBody = try JSONEncoder().encode(payload)
        req.timeoutInterval = 60

        if debugLogging, let body = req.httpBody, let s = String(data: body, encoding: .utf8) {
            print("[API] POST /api/email-timecard\n\(s)")
        }

        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { throw TimecardAPIError.invalidResponse(code) }
        if debugLogging { print("[API] Email send accepted (status \(code))") }
    }

    // MARK: - Builders

    private func buildTimecardRequest(from store: TimecardStore, weeks: [Int]? = nil) -> GoTimecardRequest {
        let cal = Calendar.current
        let year = cal.component(.year, from: store.weekStart)
        let ppNum = store.payPeriodNumber

        // Determine which week indices to include
        let count = max(1, store.payPeriodWeeks)
        let selectedWeeks = (weeks?.isEmpty == false) ? weeks! : Array(0..<count)

        // Build week blocks and collect job mapping (code -> job number/name)
        var weekBlocks: [GoWeekData] = []
        var jobByCode: [String: String] = [:] // code -> job number/name

        for w in selectedWeeks {
            let range = store.weekRange(offset: w)
            let start = range.lowerBound
            let entries = store.entries(in: range)

            let goEntries: [GoEntry] = entries.map { e in
                // Track job number/name for this code if available
                let trimmedJob = e.jobNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedJob.isEmpty {
                    jobByCode[e.code] = trimmedJob
                } else if jobByCode[e.code] == nil {
                    // Fallback: if we never saw a jobNumber, use the code itself as a placeholder name
                    jobByCode[e.code] = e.code
                }
                return GoEntry(
                    date: iso.string(from: e.date),
                    job_code: e.code,
                    hours: e.hours,
                    overtime: e.isOvertime,
                    is_night_shift: e.isNightShift
                )
            }

            let label = "Week \(w + 1) (\(start.weekRangeLabel()))"
            weekBlocks.append(
                GoWeekData(
                    week_number: w + 1,
                    week_start_date: iso.string(from: start),
                    week_label: label,
                    entries: goEntries
                )
            )
        }

        // Convert job map to array
        let jobs: [GoJob] = jobByCode.map { (code, name) in GoJob(job_code: code, job_name: name) }
            .sorted { $0.job_code < $1.job_code }

        let topLabel = "Week \(store.selectedWeekIndex + 1) of \(count)"
        return GoTimecardRequest(
            employee_name: store.employeeName.isEmpty ? "Employee" : store.employeeName,
            pay_period_num: ppNum,
            year: year,
            week_start_date: iso.string(from: store.weekStart),
            week_number_label: topLabel,
            jobs: jobs,
            entries: nil, // server uses `weeks`
            weeks: weekBlocks
        )
    }

    // MARK: - Helpers

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else { throw TimecardAPIError.badURL }
        return url
    }
}
