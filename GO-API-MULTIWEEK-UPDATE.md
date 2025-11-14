# Go API Update Required: Multi-Week Timecard Support

## Problem
Currently, when the iOS app sends multiple weeks of timecard data, the Go API creates a **single Excel sheet** with all entries combined and labels it "Weeks 1-2". 

**Expected behavior**: Create **separate Excel sheet tabs** - one for "Week 1" with Week 1 data, and one for "Week 2" with Week 2 data.

## Solution Overview
The iOS app has been updated to send a new optional field called `weeks` that contains pre-organized data for each week. The Go API needs to be updated to recognize this field and create separate sheets accordingly.

## Updated Request Structure

### TimecardRequest (Go struct)
```go
type TimecardRequest struct {
    EmployeeName     string     `json:"employee_name"`
    PayPeriodNum     int        `json:"pay_period_num"`
    Year             int        `json:"year"`
    WeekStartDate    string     `json:"week_start_date"`
    WeekNumberLabel  string     `json:"week_number_label"`
    Jobs             []Job      `json:"jobs"`
    Entries          []Entry    `json:"entries"`
    Weeks            []WeekData `json:"weeks,omitempty"` // NEW: Optional multi-week data
}

type WeekData struct {
    WeekNumber     int     `json:"week_number"`
    WeekStartDate  string  `json:"week_start_date"`
    WeekLabel      string  `json:"week_label"`
    Entries        []Entry `json:"entries"`
}

type Job struct {
    JobCode string `json:"job_code"`
    JobName string `json:"job_name"`
}

type Entry struct {
    Date     string  `json:"date"`
    JobCode  string  `json:"job_code"`
    Hours    float64 `json:"hours"`
    Overtime bool    `json:"overtime"`
}
```

### EmailTimecardRequest (Go struct)
```go
type EmailTimecardRequest struct {
    EmployeeName    string     `json:"employee_name"`
    PayPeriodNum    int        `json:"pay_period_num"`
    Year            int        `json:"year"`
    WeekStartDate   string     `json:"week_start_date"`
    WeekNumberLabel string     `json:"week_number_label"`
    Jobs            []Job      `json:"jobs"`
    Entries         []Entry    `json:"entries"`
    Weeks           []WeekData `json:"weeks,omitempty"` // NEW: Optional multi-week data
    To              string     `json:"to"`
    CC              string     `json:"cc,omitempty"`
    Subject         string     `json:"subject"`
    Body            string     `json:"body"`
}
```

## Implementation Logic

### In `/api/generate-timecard` handler:

```go
func generateTimecardHandler(w http.ResponseWriter, r *http.Request) {
    var req TimecardRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    
    // Create Excel file
    f := excelize.NewFile()
    
    // Check if multi-week data is provided
    if req.Weeks != nil && len(req.Weeks) > 0 {
        // Create separate sheet for each week
        for i, weekData := range req.Weeks {
            sheetName := weekData.WeekLabel // e.g., "Week 1", "Week 2"
            
            if i == 0 {
                // Rename the default sheet
                f.SetSheetName("Sheet1", sheetName)
            } else {
                // Create new sheet
                f.NewSheet(sheetName)
            }
            
            // Populate the sheet with weekData.Entries
            populateTimecardSheet(f, sheetName, req, weekData.Entries, weekData.WeekLabel)
        }
        
        // Delete any extra default sheets if needed
        // Set the first week as active
        f.SetActiveSheet(0)
        
    } else {
        // Legacy behavior: single sheet with all entries
        sheetName := req.WeekNumberLabel
        f.SetSheetName("Sheet1", sheetName)
        populateTimecardSheet(f, sheetName, req, req.Entries, req.WeekNumberLabel)
    }
    
    // Write to buffer and send response
    buffer := &bytes.Buffer{}
    if err := f.Write(buffer); err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    
    w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"timecard_%s.xlsx\"", req.EmployeeName))
    w.Write(buffer.Bytes())
}

func populateTimecardSheet(f *excelize.File, sheetName string, req TimecardRequest, entries []Entry, weekLabel string) {
    // Your existing logic to:
    // 1. Set up the timecard template
    // 2. Add employee info
    // 3. Add the week label in the appropriate cell
    // 4. Fill in entries
    // 5. Add job codes
    // 6. Calculate totals
    
    // Example:
    // Set employee name
    f.SetCellValue(sheetName, "E2", req.EmployeeName)
    
    // Set week label (this should be "Week 1", "Week 2", etc., NOT "Weeks 1-2")
    f.SetCellValue(sheetName, "AK4", weekLabel)
    
    // Set PP# and Year
    f.SetCellValue(sheetName, "AL2", req.PayPeriodNum)
    f.SetCellValue(sheetName, "AL3", req.Year)
    
    // Fill in entries...
    // (Your existing entry population logic here)
}
```

### In `/api/email-timecard` handler:

Apply the same logic - check for `req.Weeks` and create multiple sheets if present, otherwise fall back to single sheet behavior.

## Key Points

1. **Backward Compatibility**: The `weeks` field is optional (`omitempty`), so old requests without this field will continue to work as before.

2. **Sheet Naming**: Each sheet should be named using `weekData.WeekLabel` (e.g., "Week 1", "Week 2"), NOT "Weeks 1-2".

3. **Entry Filtering**: When `weeks` is present, use `weekData.Entries` for each respective sheet instead of `req.Entries`.

4. **Active Sheet**: Set the first week (Week 1) as the active sheet when opening the file.

## Example JSON Sent by iOS App

### Single Week (Legacy - still works)
```json
{
  "employee_name": "Geoff",
  "pay_period_num": 47,
  "year": 2025,
  "week_start_date": "2025-11-09T00:00:00Z",
  "week_number_label": "Week 1",
  "jobs": [
    {"job_code": "201", "job_name": "Cable Pull"},
    {"job_code": "223", "job_name": "Testing/Verification"}
  ],
  "entries": [
    {"date": "2025-11-10T00:00:00Z", "job_code": "201", "hours": 0.5, "overtime": false},
    {"date": "2025-11-11T00:00:00Z", "job_code": "223", "hours": 8.0, "overtime": false},
    {"date": "2025-11-12T00:00:00Z", "job_code": "201", "hours": 0.5, "overtime": false}
  ]
}
```

### Multi-Week (New format)
```json
{
  "employee_name": "Geoff",
  "pay_period_num": 47,
  "year": 2025,
  "week_start_date": "2025-11-09T00:00:00Z",
  "week_number_label": "Week 1",
  "jobs": [
    {"job_code": "201", "job_name": "Cable Pull"},
    {"job_code": "223", "job_name": "Testing/Verification"}
  ],
  "entries": [
    {"date": "2025-11-10T00:00:00Z", "job_code": "201", "hours": 0.5, "overtime": false},
    {"date": "2025-11-11T00:00:00Z", "job_code": "223", "hours": 8.0, "overtime": false},
    {"date": "2025-11-12T00:00:00Z", "job_code": "201", "hours": 0.5, "overtime": false},
    {"date": "2025-11-17T00:00:00Z", "job_code": "201", "hours": 1.0, "overtime": false},
    {"date": "2025-11-18T00:00:00Z", "job_code": "223", "hours": 8.0, "overtime": false}
  ],
  "weeks": [
    {
      "week_number": 1,
      "week_start_date": "2025-11-09T00:00:00Z",
      "week_label": "Week 1",
      "entries": [
        {"date": "2025-11-10T00:00:00Z", "job_code": "201", "hours": 0.5, "overtime": false},
        {"date": "2025-11-11T00:00:00Z", "job_code": "223", "hours": 8.0, "overtime": false},
        {"date": "2025-11-12T00:00:00Z", "job_code": "201", "hours": 0.5, "overtime": false}
      ]
    },
    {
      "week_number": 2,
      "week_start_date": "2025-11-16T00:00:00Z",
      "week_label": "Week 2",
      "entries": [
        {"date": "2025-11-17T00:00:00Z", "job_code": "201", "hours": 1.0, "overtime": false},
        {"date": "2025-11-18T00:00:00Z", "job_code": "223", "hours": 8.0, "overtime": false}
      ]
    }
  ]
}
```

## Testing

After implementing the changes:

1. Test with single week - should work as before
2. Test with multiple weeks - should create separate tabs
3. Verify sheet names are "Week 1", "Week 2", etc., not "Weeks 1-2"
4. Verify each tab contains only the entries for that week
5. Test email endpoint with both single and multi-week scenarios

## Notes

- The iOS app now properly groups entries by week before sending to the API
- The `entries` field still contains ALL entries for backward compatibility, but when `weeks` is present, you should use the entries from each `WeekData` object instead
- Each week's entries are already filtered by date range on the iOS side
