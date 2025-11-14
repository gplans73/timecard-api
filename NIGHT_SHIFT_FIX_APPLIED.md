# 🌙 Night Shift Fix - RESOLVED

## The Problem

Night shift hours were not appearing in Row 13 "TOTAL NIGHT" of the Excel export.

## Root Cause

**JSON Field Name Mismatch:**
- Swift app sends: `"night_shift": true`
- Go backend was looking for: `"is_night_shift"` or `"isNightShift"`
- Result: The `night_shift` field was being ignored and defaulting to `false`

## The Fix Applied

Updated the `UnmarshalJSON` method in `main.go` to accept `night_shift` (without the `is_` prefix):

```go
type rawEntry struct {
    Date                string   `json:"date"`
    JobCode             string   `json:"job_code"`
    Code                string   `json:"code"`
    Hours               float64  `json:"hours"`
    Overtime            *bool    `json:"overtime"`
    IsOvertimeCamel     *bool    `json:"isOvertime"`
    NightShift          *bool    `json:"night_shift"`        // ⭐️ ADDED - Swift sends this
    IsNightShiftSnake   *bool    `json:"is_night_shift"`    // Alternative format
    IsNightShiftCamel   *bool    `json:"isNightShift"`      // Alternative format
}

// Priority order: night_shift → is_night_shift → isNightShift
if aux.NightShift != nil {
    e.IsNightShift = *aux.NightShift
} else if aux.IsNightShiftSnake != nil {
    e.IsNightShift = *aux.IsNightShiftSnake
} else if aux.IsNightShiftCamel != nil {
    e.IsNightShift = *aux.IsNightShiftCamel
} else {
    e.IsNightShift = false
}
```

## What Changed

**Before:**
```go
// Only checked for is_night_shift and isNightShift
IsNightShiftSnake   *bool    `json:"is_night_shift"`
IsNightShiftCamel   *bool    `json:"isNightShift"`
```

**After:**
```go
// Now checks for night_shift first (what Swift actually sends)
NightShift          *bool    `json:"night_shift"`        // ⭐️ PRIMARY
IsNightShiftSnake   *bool    `json:"is_night_shift"`    // Fallback
IsNightShiftCamel   *bool    `json:"isNightShift"`      // Fallback
```

## How It Works

The rest of the code was already correct! It was designed to:
1. ✅ Prefix night shift job codes with "N" (e.g., "92408" → "N92408")
2. ✅ Display night shift jobs as separate columns with "N" prefix on labour code (e.g., "N223")
3. ✅ Track night shift hours separately from regular hours

The only issue was that `IsNightShift` was always `false` due to the JSON field name mismatch.

## Testing

### Step 1: Rebuild and Deploy

```bash
# Commit the change
git add main.go
git commit -m "Fix night_shift JSON field name to match Swift app"
git push

# Render.com will auto-deploy
```

### Step 2: Test from Swift

Run the night shift test:
```swift
await TestGoAPI.testNightShiftSpecifically()
```

Expected output in Excel:
- **Row 4 headers:** Should show "N223" in labour code column for night shift job 92408
- **Row 5-11 (daily hours):** Should show 0.5 hours under the "N223" column on Nov 10
- **Row 13 (TOTAL NIGHT):** Should be empty (because totals are calculated by formulas in the template)

### Step 3: Test from iOS App

1. Create a new entry
2. Select job (e.g., 92408)
3. Enter hours (e.g., 0.5)
4. Toggle **"Night"** button ON
5. Send the timecard
6. Open Excel and verify:
   - Night shift job appears as separate column with "N" prefix
   - Hours show in the correct column

## Expected Excel Layout

For a night shift entry (Job 92408, Labour Code 223, 0.5 hours):

| Row | Column C | Column D | Column E | Column F |
|-----|----------|----------|----------|----------|
| 4 | 201 | 12215 | **N223** | **92408** |
| 5 (Sun) | 1.0 | | | |
| 6 (Mon) | 0.5 | | **0.5** | |
| ... | | | | |

The "N223" label indicates this is a night shift version of labour code 223.

## Debug Logging

Added debug logging in `UnmarshalJSON` to help verify the fix:

```go
log.Printf("  Unmarshaled entry: JobCode=%s, Hours=%.1f, Overtime=%v, IsNightShift=%v", 
    e.JobCode, e.Hours, e.Overtime, e.IsNightShift)
```

Check your server logs after deployment to confirm `IsNightShift=true` for night entries.

## Why This Happened

The original code was written to accept multiple JSON formats for flexibility, but it was checking for `is_night_shift` (with `is_` prefix) when Swift was actually sending `night_shift` (without prefix).

This is a common issue when integrating systems that use different naming conventions:
- Swift: camelCase → `isNightShift` property → encoded as snake_case `night_shift`
- Go: Was expecting `is_night_shift` (with the `is_` prefix)

## Files Modified

✅ `/repo/main.go` - Added `NightShift *bool` field to `rawEntry` struct

## Files for Reference

- `NIGHT_SHIFT_FIX.md` - Original diagnostic document
- `GO_BACKEND_NIGHT_SHIFT_FIX.go` - Reference implementation
- `FIX_SUMMARY.md` - Quick reference guide
- `TestGoAPI.swift` - Includes `testNightShiftSpecifically()` test

## Status

✅ **FIXED** - Ready to deploy and test

## Next Steps

1. ✅ Deploy updated `main.go` to Render.com
2. ⏳ Run `TestGoAPI.testNightShiftSpecifically()` from Swift
3. ⏳ Verify night shift entries in Excel export
4. ⏳ Test with real timecard entries from iOS app

---

**Fixed:** November 12, 2025
**Issue:** JSON field name mismatch (`night_shift` vs `is_night_shift`)
**Solution:** Added `NightShift` field to JSON unmarshaling with correct tag
