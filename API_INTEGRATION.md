# Timecard API Integration Guide

## Overview

This document explains how the Swift iOS timecard app integrates with the Go backend API for generating and emailing Excel timecards.

## Architecture

```
┌─────────────────┐
│   iOS App       │
│   (Swift)       │
└────────┬────────┘
         │ HTTP/JSON
         ▼
┌─────────────────┐
│  Go Backend     │
│  main.go        │
├─────────────────┤
│ /health         │
│ /api/generate   │
│ /api/email      │
└────────┬────────┘
         │
         ▼
    Excel/SMTP
```

## Go Backend API

### Endpoints

#### 1. Health Check
```
GET /health
Response: "ok" (200)
```

#### 2. Generate Timecard Excel
```
POST /api/generate-timecard
Content-Type: application/json
```

**Request Body:**
```json
{
  "employee_name": "John Doe",
  "pay_period_num": 1,
  "year": 2025,
  "week_start_date": "2025-01-06T00:00:00Z",
  "week_number_label": "Week 1",
  "jobs": [
    {
      "job_code": "JOB001",
      "job_name": "Construction Project A"
    }
  ],
  "entries": [
    {
      "date": "2025-01-06T00:00:00Z",
      "job_code": "JOB001",
      "hours": 8.0,
      "overtime": false
    }
  ]
}
```

**Response:**
- Content-Type: `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`
- Body: Excel file binary data (.xlsx)

#### 3. Email Timecard
```
POST /api/email-timecard
Content-Type: application/json
```

**Request Body:**
Extends the generate request with email fields:
```json
{
  "employee_name": "John Doe",
  "pay_period_num": 1,
  "year": 2025,
  "week_start_date": "2025-01-06T00:00:00Z",
  "week_number_label": "Week 1",
  "jobs": [...],
  "entries": [...],
  "to": "manager@company.com, hr@company.com",
  "cc": "supervisor@company.com",
  "subject": "Timecard - John Doe - Week 1",
  "body": "Please find attached timecard for the week."
}
```

**Response:**
```json
{
  "status": "sent"
}
```

### Environment Variables Required by Go API

The Go backend requires these SMTP settings:

```bash
SMTP_HOST=smtp.gmail.com           # Your SMTP server
SMTP_PORT=587                       # Usually 587 for TLS
SMTP_USERNAME=your-email@gmail.com  # SMTP username
SMTP_PASSWORD=your-app-password     # SMTP password/app password
SMTP_FROM=your-email@gmail.com      # From address (optional, defaults to username)
```

### Deployment

The Go API is deployed at:
```
https://timecard-api.onrender.com
```

To test locally:
```bash
cd /path/to/go-backend
go run main.go
# Server starts on :8080
```

## Swift iOS App Integration

### Files

1. **TimecardAPIService.swift** - API client
2. **SendView.swift** - UI for sending timecards
3. **SwiftDataModels.swift** - Data models

### Key Components

#### TimecardAPIService

Singleton service that communicates with the Go API:

```swift
@MainActor
class TimecardAPIService: ObservableObject {
    static let shared = TimecardAPIService()
    private let baseURL = "https://timecard-api.onrender.com"
    
    // Generate Excel file
    func generateTimecardFiles(...) async throws -> (Data, Data)
    
    // Send email via API
    func emailTimecard(...) async throws
}
```

#### Data Flow

```swift
// 1. User taps "Send" button in SendView
generateAndSendFiles()

// 2. Collect entries from all selected weeks
let allEntries: [EntryModel] = // ...

// 3. Call Go API to generate Excel
let (excelData, _) = try await apiService.generateTimecardFiles(...)

// 4. Either:
//    a) Show iOS Mail composer with Excel attachment
//    b) OR use Go API to send email directly
try await apiService.emailTimecard(...)
```

### Request Mapping

The Swift app converts its internal models to match the Go API structure:

| Swift Property | Go JSON Field | Type |
|---------------|---------------|------|
| `entry.date` | `date` | ISO 8601 string |
| `entry.jobNumber` | `job_code` | String |
| `entry.hours` | `hours` | Double |
| `entry.isOvertime` | `overtime` | Bool |
| `store.employeeName` | `employee_name` | String |
| `store.payPeriodNumber` | `pay_period_num` | Int |

### Date Format

**Critical:** The Go API expects ISO 8601 format with timezone:

```swift
let isoFormatter = ISO8601DateFormatter()
isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
let dateString = isoFormatter.string(from: date)
// Result: "2025-01-06T00:00:00Z"
```

### Jobs Extraction

The Swift app automatically extracts unique jobs from entries:

```swift
private func extractUniqueJobs(from entries: [EntryModel]) -> [GoJob] {
    var jobDict: [String: String] = [:]
    
    for entry in entries {
        if !entry.jobNumber.isEmpty && jobDict[entry.jobNumber] == nil {
            let jobName = entry.code.isEmpty ? entry.jobNumber : entry.code
            jobDict[entry.jobNumber] = jobName
        }
    }
    
    return jobDict.map { code, name in
        GoJob(job_code: code, job_name: name)
    }
}
```

## Usage Examples

### Generate Excel Only

```swift
let (excelData, _) = try await apiService.generateTimecardFiles(
    employeeName: "John Doe",
    emailRecipients: ["manager@company.com"],
    entries: allEntries,
    weekStart: startDate,
    weekEnd: endDate,
    weekNumber: 1,
    totalWeeks: 2,
    ppNumber: 1
)

// Save or attach excelData
let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("timecard.xlsx")
try excelData.write(to: url)
```

### Send Email via Go API

```swift
try await apiService.emailTimecard(
    employeeName: "John Doe",
    emailRecipients: ["manager@company.com"],
    ccRecipients: ["hr@company.com"],
    subject: "Timecard - Week 1",
    body: "Please find attached timecard.",
    entries: allEntries,
    weekStart: startDate,
    weekEnd: endDate,
    weekNumber: 1,
    totalWeeks: 2,
    ppNumber: 1
)
```

## Error Handling

### Swift Side

```swift
do {
    let (excelData, _) = try await apiService.generateTimecardFiles(...)
} catch let error as TimecardAPIService.APIError {
    switch error {
    case .invalidURL:
        // Handle invalid URL
    case .serverError(let message):
        // Show server error to user
    case .networkError(let underlying):
        // Handle network issues
    default:
        // Generic error handling
    }
}
```

### Go Side

The Go API returns appropriate HTTP status codes:

| Status | Meaning |
|--------|---------|
| 200 | Success |
| 400 | Bad Request (invalid JSON) |
| 405 | Method Not Allowed |
| 500 | Internal Server Error |

Error messages are returned as plain text in the response body.

## Testing

### Test the Go API Directly

Using curl:

```bash
# Health check
curl https://timecard-api.onrender.com/health

# Generate Excel
curl -X POST https://timecard-api.onrender.com/api/generate-timecard \
  -H "Content-Type: application/json" \
  -d '{
    "employee_name": "Test User",
    "pay_period_num": 1,
    "year": 2025,
    "week_start_date": "2025-01-06T00:00:00Z",
    "week_number_label": "Week 1",
    "jobs": [{"job_code": "TEST", "job_name": "Test Job"}],
    "entries": [{
      "date": "2025-01-06T00:00:00Z",
      "job_code": "TEST",
      "hours": 8.0,
      "overtime": false
    }]
  }' \
  --output timecard.xlsx
```

### Test from iOS

Enable debug logging in `TimecardAPIService.swift`:

```swift
// Prints the JSON being sent
if let jsonString = String(data: urlRequest.httpBody!, encoding: .utf8) {
    print("📤 Sending to Go API:\n\(jsonString)")
}

// Prints response size
print("✅ Received Excel file: \(data.count) bytes")
```

## Troubleshooting

### Issue: "Invalid JSON"

**Cause:** The request structure doesn't match Go's `TimecardRequest`

**Solution:** Verify field names match exactly (snake_case in JSON):
- ✅ `employee_name`
- ❌ `employeeName`

### Issue: "Date parsing failed"

**Cause:** Date format is not ISO 8601 with timezone

**Solution:** Use `ISO8601DateFormatter`:
```swift
let formatter = ISO8601DateFormatter()
formatter.timeZone = TimeZone(secondsFromGMT: 0)
```

### Issue: "Empty Excel file"

**Cause:** No entries or jobs in request

**Solution:** Verify `jobs` and `entries` arrays are populated:
```swift
print("Jobs: \(request.jobs.count)")
print("Entries: \(request.entries.count)")
```

### Issue: "Email not sent"

**Cause:** SMTP configuration missing or incorrect

**Solution:** 
1. Check environment variables on server
2. Verify SMTP credentials are valid
3. For Gmail, use App Passwords, not regular password

### Issue: "Network timeout"

**Cause:** Server may be sleeping (Render free tier)

**Solution:** First request to a sleeping Render service takes ~30 seconds. Add timeout:
```swift
urlRequest.timeoutInterval = 60 // 60 seconds
```

## Future Enhancements

### Potential Improvements

1. **Caching** - Cache generated Excel files
2. **Batch Operations** - Send multiple timecards in one request
3. **PDF Generation** - Move PDF generation to Go backend
4. **Retry Logic** - Automatic retry with exponential backoff
5. **Offline Support** - Queue requests when offline
6. **Progress Tracking** - Stream progress for large files

### Adding New Fields

To add a new field to timecards:

1. **Go Backend** - Update structs in `main.go`:
```go
type Entry struct {
    // ... existing fields
    NewField string `json:"new_field"`
}
```

2. **Swift App** - Update request model:
```swift
struct GoEntry: Codable {
    // ... existing fields
    let new_field: String
}
```

3. **Map the data** in conversion:
```swift
GoEntry(
    // ... existing mappings
    new_field: entry.newField
)
```

## Security Considerations

### Current Implementation

- ✅ HTTPS for all API communication
- ✅ Environment variables for sensitive SMTP credentials
- ⚠️ No authentication on API endpoints

### Recommended for Production

1. **Add API Authentication:**
```go
// Add API key middleware
func requireAPIKey(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        apiKey := r.Header.Get("X-API-Key")
        if apiKey != os.Getenv("API_KEY") {
            http.Error(w, "unauthorized", http.StatusUnauthorized)
            return
        }
        next(w, r)
    }
}
```

2. **Rate Limiting** - Prevent abuse
3. **Input Validation** - Sanitize all inputs
4. **File Size Limits** - Prevent memory exhaustion
5. **Audit Logging** - Track all email sends

## Support

For issues or questions:
1. Check this documentation
2. Review Go backend logs
3. Enable debug logging in Swift app
4. Test API endpoints directly with curl

---

**Last Updated:** November 8, 2025
