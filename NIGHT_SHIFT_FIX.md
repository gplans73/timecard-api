# Night Shift Hours Not Showing in Excel Export - Diagnostic & Fix

## Problem Statement

Night shift hours marked in the iOS app are not appearing in the "TOTAL NIGHT" row of the exported Excel timecard. They are incorrectly being counted as regular hours.

## Root Cause Analysis

### ✅ Swift iOS App (WORKING CORRECTLY)

The Swift side is correctly:

1. **Storing night shift data**
   ```swift
   @Model
   final class EntryModel {
       var isNightShift: Bool = false  // ✅ Property exists
   }
   ```

2. **Sending to API**
   ```swift
   GoTimecardRequest.GoEntry(
       date: isoFormatter.string(from: entry.date),
       job_code: entry.jobNumber,
       hours: entry.hours,
       overtime: entry.isOvertime,
       night_shift: entry.isNightShift  // ✅ Correctly mapped
   )
   ```

3. **JSON Output Example**
   ```json
   {
     "entries": [
       {
         "date": "2025-11-10T00:00:00Z",
         "job_code": "92408",
         "hours": 0.5,
         "overtime": false,
         "night_shift": true  // ✅ Field is present in JSON
       }
     ]
   }
   ```

### ❌ Go Backend (NEEDS FIX)

The Go backend at `https://timecard-api.onrender.com` is likely:

1. **Not reading the `night_shift` field** from the JSON request
2. **Treating all non-overtime hours as regular hours**
3. **Not writing to the "TOTAL NIGHT" row** (row 13) in the Excel template

## Required Fix in `main.go`

You need to update your Go backend code. Here's what needs to be fixed:

### 1. Verify Entry Struct Has NightShift Field

```go
type Entry struct {
    Date       string  `json:"date"`
    JobCode    string  `json:"job_code"`
    Hours      float64 `json:"hours"`
    Overtime   bool    `json:"overtime"`
    NightShift bool    `json:"night_shift"`  // ⚠️ MUST BE PRESENT
}
```

### 2. Update Excel Generation Logic

The logic needs to separate hours into three categories:

```go
// When processing entries for each job/date combination
for _, entry := range request.Entries {
    jobCode := entry.JobCode
    date := entry.Date
    hours := entry.Hours
    
    // Determine which row to write to
    if entry.Overtime {
        // Write to "Overtime & Double-Time" row (row 14)
        writeToOvertimeRow(f, jobCode, date, hours)
    } else if entry.NightShift {
        // Write to "TOTAL NIGHT" row (row 13)
        writeToNightRow(f, jobCode, date, hours)
    } else {
        // Write to "TOTAL REGULAR" row (row 12)
        writeToRegularRow(f, jobCode, date, hours)
    }
}
```

### 3. Example Implementation

Here's a more complete example of how to handle the three types of hours:

```go
func fillTimecardData(f *excelize.File, request TimecardRequest) error {
    // Maps to track totals by job and type
    regularHours := make(map[string]map[string]float64)  // job -> date -> hours
    nightHours := make(map[string]map[string]float64)    // job -> date -> hours
    overtimeHours := make(map[string]map[string]float64) // job -> date -> hours
    
    // Initialize maps
    for _, job := range request.Jobs {
        regularHours[job.JobCode] = make(map[string]float64)
        nightHours[job.JobCode] = make(map[string]float64)
        overtimeHours[job.JobCode] = make(map[string]float64)
    }
    
    // Categorize entries
    for _, entry := range request.Entries {
        dateStr := formatDateForExcel(entry.Date)
        
        if entry.Overtime {
            overtimeHours[entry.JobCode][dateStr] += entry.Hours
        } else if entry.NightShift {
            nightHours[entry.JobCode][dateStr] += entry.Hours
        } else {
            regularHours[entry.JobCode][dateStr] += entry.Hours
        }
    }
    
    // Write to Excel template
    // Row 12: TOTAL REGULAR
    for job, dates := range regularHours {
        for date, hours := range dates {
            cell := getCellForJobAndDate(job, date)
            f.SetCellValue("Sheet1", cell+"12", hours)
        }
    }
    
    // Row 13: TOTAL NIGHT
    for job, dates := range nightHours {
        for date, hours := range dates {
            cell := getCellForJobAndDate(job, date)
            f.SetCellValue("Sheet1", cell+"13", hours)
        }
    }
    
    // Row 14: Overtime & Double-Time
    for job, dates := range overtimeHours {
        for date, hours := range dates {
            cell := getCellForJobAndDate(job, date)
            f.SetCellValue("Sheet1", cell+"14", hours)
        }
    }
    
    return nil
}
```

## Testing the Fix

### Step 1: Update Test Case

Run the updated test in `TestGoAPI.swift`:

```swift
await TestGoAPI.testGenerateTimecard()
```

This will send a request with:
- 8.0 hours regular (JOB001, Jan 6)
- 8.5 hours regular (JOB001, Jan 7)
- 2.0 hours overtime (JOB002, Jan 7)
- **0.5 hours night shift (JOB001, Jan 8)** ← NEW TEST CASE

### Step 2: Verify Excel Output

Open the downloaded Excel file and verify:

1. **Row 12 (TOTAL REGULAR)** should show:
   - JOB001: 8.0 + 8.5 = 16.5 hours
   - JOB002: 0 hours

2. **Row 13 (TOTAL NIGHT)** should show:
   - JOB001: 0.5 hours ← **THIS SHOULD NOW APPEAR**
   - JOB002: 0 hours

3. **Row 14 (Overtime & Double-Time)** should show:
   - JOB001: 0 hours
   - JOB002: 2.0 hours

### Step 3: Test with Real Data

Create a timecard entry in your iOS app:
1. Add a job (e.g., "92408")
2. Enter hours
3. Toggle **"Night"** button
4. Send the timecard
5. Verify the hours appear in "TOTAL NIGHT" row

## Excel Template Row Structure

Make sure your Excel template has these rows:

| Row | Label | Purpose |
|-----|-------|---------|
| 12 | TOTAL REGULAR | Sum of all regular (non-overtime, non-night) hours |
| 13 | TOTAL NIGHT | Sum of all night shift hours |
| 14 | Overtime & Double-Time | Sum of all overtime hours |

## Debugging Tips

### 1. Enable Go Backend Logging

Add logging in your Go code to verify data is being received:

```go
func handleGenerateTimecard(w http.ResponseWriter, r *http.Request) {
    var request TimecardRequest
    err := json.NewDecoder(r.Body).Decode(&request)
    
    // Add logging
    log.Printf("Received %d entries", len(request.Entries))
    for i, entry := range request.Entries {
        log.Printf("Entry %d: JobCode=%s, Hours=%.1f, Overtime=%v, NightShift=%v",
            i, entry.JobCode, entry.Hours, entry.Overtime, entry.NightShift)
    }
    
    // ... rest of handler
}
```

### 2. Print JSON from Swift

In `TimecardAPIService.swift`, the JSON being sent is already logged:

```swift
if let jsonString = String(data: urlRequest.httpBody!, encoding: .utf8) {
    print("📤 Sending to Go API:\n\(jsonString)")
}
```

Check your Xcode console for this output to verify `night_shift: true` is being sent.

### 3. Verify Excel Cell References

Make sure your Go code is writing to the correct cells. The template structure should match:

```
Column B: Job Code Column Header
Columns C-I: Days of the week (Sun-Sat)
Row 12: TOTAL REGULAR
Row 13: TOTAL NIGHT
Row 14: Overtime & Double-Time
```

## Checklist

- [ ] `Entry` struct in Go has `NightShift bool` field with correct JSON tag
- [ ] Go code separates entries into regular/night/overtime categories
- [ ] Go code writes night shift hours to row 13 (TOTAL NIGHT)
- [ ] Test case with `night_shift: true` generates Excel with hours in row 13
- [ ] Real iOS app entries with Night toggle enabled show in row 13

## Next Steps

1. **Access your Go backend code** (main.go)
2. **Apply the fixes** described above
3. **Redeploy** to Render.com
4. **Test** with the updated TestGoAPI.swift
5. **Verify** with real timecard entries from the iOS app

## Additional Resources

- `TimecardAPIService.swift` - Swift API client (correctly implemented)
- `API_INTEGRATION.md` - API integration guide
- `TestGoAPI.swift` - Test script with night shift test case
- Your Go backend repo on GitHub/local machine

---

**Status:** Issue diagnosed - Swift is working correctly, Go backend needs update
**Priority:** High - Affects timecard accuracy
**Estimated Fix Time:** 15-30 minutes (Go code changes only)
