# 🌙 Night Shift Issue - Quick Fix Summary

## The Problem

Night shift hours marked in the iOS app are showing in the "TOTAL REGULAR" row instead of the "TOTAL NIGHT" row in the exported Excel file.

**From your screenshots:**
- iOS app shows entry with "Night" toggle ON for job 92408 (0.5 hours)
- Excel export shows this in regular hours instead of night hours row

## Root Cause

✅ **Swift iOS App:** Working correctly - sending `night_shift: true` in JSON
❌ **Go Backend:** Not properly reading/handling the `night_shift` field

## The Fix (3 Steps)

### Step 1: Verify Go Backend Has NightShift Field

In your `main.go`, ensure the Entry struct has this field:

```go
type Entry struct {
    Date       string  `json:"date"`
    JobCode    string  `json:"job_code"`
    Hours      float64 `json:"hours"`
    Overtime   bool    `json:"overtime"`
    NightShift bool    `json:"night_shift"`  // ← ADD THIS IF MISSING
}
```

### Step 2: Separate Hours by Type

Update your Excel generation logic to categorize hours:

```go
// Categorize each entry
for _, entry := range request.Entries {
    if entry.Overtime {
        // Goes to Overtime & Double-Time row
    } else if entry.NightShift {  // ← ADD THIS CHECK
        // Goes to TOTAL NIGHT row
    } else {
        // Goes to TOTAL REGULAR row
    }
}
```

### Step 3: Write to Correct Excel Rows

Write night shift hours to row 13 (TOTAL NIGHT):

```go
// Write night hours
if nightHours > 0 {
    cell := fmt.Sprintf("%s13", columnForDay)
    f.SetCellValue("Sheet1", cell, nightHours)
}
```

## Complete Fixed Code

See **`GO_BACKEND_NIGHT_SHIFT_FIX.go`** for the complete corrected implementation.

⚠️ **Important:** You must adjust row numbers based on YOUR template structure.

## Testing

### Test #1: Run Swift Test

```swift
// In your Swift app
await TestGoAPI.testNightShiftSpecifically()
```

This will:
1. Send a request with night shift hours
2. Save Excel to Documents folder
3. Print expected vs actual results

### Test #2: Check Excel Output

Open the generated Excel file and verify:

| Row | Label | Expected Hours |
|-----|-------|---------------|
| 12 | TOTAL REGULAR | Job 12215: 1.5, Job 92408: 0 |
| 13 | TOTAL NIGHT | Job 12215: 0, Job 92408: 0.5 ⭐️ |
| 14 | Overtime | All: 0 |

### Test #3: Real-World Test

1. Create entry in iOS app
2. Select a job (e.g., 92408)
3. Enter hours (e.g., 0.5)
4. Toggle "Night" button ON
5. Send timecard
6. Open Excel → verify hours are in row 13

## Files Changed

### Swift Side (Already Correct)
- ✅ `SwiftDataModels.swift` - Has `isNightShift` property
- ✅ `TimecardAPIService.swift` - Maps to `night_shift` in JSON
- ✅ `SendView.swift` - Passes property through
- ✅ `TestGoAPI.swift` - Updated with night shift test case

### Go Side (Needs Your Update)
- ❌ `main.go` - Apply the fixes from `GO_BACKEND_NIGHT_SHIFT_FIX.go`

## Expected JSON (from Swift)

```json
{
  "entries": [
    {
      "date": "2025-11-10T00:00:00Z",
      "job_code": "92408",
      "hours": 0.5,
      "overtime": false,
      "night_shift": true  ← This is being sent correctly
    }
  ]
}
```

## Deployment

After updating `main.go`:

```bash
# Commit changes
git add main.go
git commit -m "Fix night shift hours routing to correct Excel row"
git push

# Render.com will auto-deploy (if connected to Git)
# Or manually deploy if needed
```

## Verification Checklist

- [ ] Go Entry struct has `NightShift bool` field with `json:"night_shift"` tag
- [ ] Go code checks `entry.NightShift` when processing entries
- [ ] Go code writes night hours to row 13 (or appropriate row for your template)
- [ ] Rebuild and redeploy Go backend
- [ ] Run `TestGoAPI.testNightShiftSpecifically()`
- [ ] Verify Excel has hours in "TOTAL NIGHT" row
- [ ] Test with real iOS app entry with Night toggle enabled

## Next Steps

1. **Update your Go backend** with the fixes
2. **Redeploy** to Render.com
3. **Run tests** to verify
4. **Test in production** with real timecard entries

## Questions?

Check these files for more details:
- `NIGHT_SHIFT_FIX.md` - Detailed diagnostic and explanation
- `GO_BACKEND_NIGHT_SHIFT_FIX.go` - Complete fixed Go code
- `TestGoAPI.swift` - Test cases including night shift

---

**Status:** Ready to fix (Go backend update required)
**Time to Fix:** 15-30 minutes
**Risk:** Low (only affects categorization, doesn't lose data)
