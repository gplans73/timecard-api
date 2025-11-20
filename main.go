func populateTimecardSheet(
    file *excelize.File,
    sheetName string,
    req TimecardRequest,
    entries []Entry,
    weekLabel string,
    weekNumber int,
) error {
    log.Printf("✍️ Populating sheet %q (week %d, %d entries)", sheetName, weekNumber, len(entries))

    // ----------------------------------------------------------------------
    // 1) Header fields (employee, PP#, year, week label)
    // ----------------------------------------------------------------------

    // Employee name (M2)
    if val, err := file.GetCellValue(sheetName, "M2"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "M2", req.EmployeeName); err != nil {
            return fmt.Errorf("failed setting M2: %w", err)
        }
    }

    // Pay-period number (AJ2)
    if val, err := file.GetCellValue(sheetName, "AJ2"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "AJ2", req.PayPeriodNum); err != nil {
            return fmt.Errorf("failed setting AJ2: %w", err)
        }
    }

    // Year (AJ3)
    if val, err := file.GetCellValue(sheetName, "AJ3"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "AJ3", req.Year); err != nil {
            return fmt.Errorf("failed setting AJ3: %w", err)
        }
    }

    // Week label (AJ4) – always safe to overwrite
    if err := file.SetCellValue(sheetName, "AJ4", weekLabel); err != nil {
        return fmt.Errorf("failed setting AJ4: %w", err)
    }

    // ----------------------------------------------------------------------
    // 2) Week start date → Excel serial in B4 ("Sun Date Start")
    // ----------------------------------------------------------------------

    var weekStart time.Time
    var err error

    // Prefer explicit WeekStartDate from request
    if req.WeekStartDate != "" {
        weekStart, err = time.Parse(time.RFC3339, req.WeekStartDate)
        if err != nil {
            log.Printf("⚠️ Failed to parse req.WeekStartDate=%q: %v", req.WeekStartDate, err)
        }
    }

    // If not set or parse failed, fall back to earliest entry date
    if weekStart.IsZero() {
        var earliest time.Time
        for _, e := range entries {
            t, parseErr := time.Parse(time.RFC3339, e.Date)
            if parseErr != nil {
                continue
            }
            if earliest.IsZero() || t.Before(earliest) {
                earliest = t
            }
        }

        if earliest.IsZero() {
            // Last-resort fallback
            weekStart = time.Now().UTC().Truncate(24 * time.Hour)
        } else {
            weekStart = earliest.UTC().Truncate(24 * time.Hour)
        }
    }

    // Convert to Excel serial (template uses 1899-12-30 base)
    excelEpoch := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
    daysSinceEpoch := weekStart.Sub(excelEpoch).Hours() / 24.0

    // Only write B4 if it's not a formula
    if val, err := file.GetCellValue(sheetName, "B4"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "B4", daysSinceEpoch); err != nil {
            return fmt.Errorf("failed setting B4: %w", err)
        }
    }

    // ----------------------------------------------------------------------
    // 3) Job headers (Regular @ row 4, OT @ row 15)
    //    CODE columns (C,E,G,...) are where HOURS live.
    //    JOB columns (D,F,H,...) are the names.
    // ----------------------------------------------------------------------

    jobCodeColumns := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
    jobNameColumns := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}

    // Map JobCode → index in the slices above
    jobIndex := make(map[string]int)

    for i, job := range req.Jobs {
        if i >= len(jobCodeColumns) {
            log.Printf("⚠️ Too many jobs (%d); template supports %d", len(req.Jobs), len(jobCodeColumns))
            break
        }

        codeCol := jobCodeColumns[i]
        nameCol := jobNameColumns[i]

        // Row 4: regular-time headers
        if err := file.SetCellValue(sheetName, codeCol+"4", job.JobCode); err != nil {
            return fmt.Errorf("failed setting %s4: %w", codeCol, err)
        }
        if err := file.SetCellValue(sheetName, nameCol+"4", job.JobName); err != nil {
            return fmt.Errorf("failed setting %s4: %w", nameCol, err)
        }

        // Row 15: overtime headers (so TOTAL OVERTIME formulas look at real job codes)
        if err := file.SetCellValue(sheetName, codeCol+"15", job.JobCode); err != nil {
            return fmt.Errorf("failed setting %s15: %w", codeCol, err)
        }
        if err := file.SetCellValue(sheetName, nameCol+"15", job.JobName); err != nil {
            return fmt.Errorf("failed setting %s15: %w", nameCol, err)
        }

        jobIndex[job.JobCode] = i
    }

    // ----------------------------------------------------------------------
    // 4) Aggregate entries by (date, job, overtime)
    //    so multiple punches for same day/job roll up.
    // ----------------------------------------------------------------------

    type entryKey struct {
        Date     string
        JobCode  string
        Overtime bool
    }

    agg := make(map[entryKey]float64)

    for _, e := range entries {
        key := entryKey{
            Date:     e.Date,
            JobCode:  e.JobCode,
            Overtime: e.Overtime,
        }
        agg[key] += e.Hours
    }

    // ----------------------------------------------------------------------
    // 5) Write hours into template
    //
    //    Regular rows:  5–11  (Sun–Sat)
    //    OT rows:      16–22  (Sun–Sat)
    //
    //    We only write into CODE columns (C,E,G,...), which matches the
    //    template’s SUM/SUMIFS formulas.
    // ----------------------------------------------------------------------

    for key, totalHours := range agg {
        entryDate, err := time.Parse(time.RFC3339, key.Date)
        if err != nil {
            log.Printf("⚠️ Skipping entry with bad date %q: %v", key.Date, err)
            continue
        }

        dayOffset := int(entryDate.Sub(weekStart).Hours() / 24.0)
        if dayOffset < 0 || dayOffset > 6 {
            log.Printf("⚠️ Skipping entry on %s (outside 7-day window from %s)",
                entryDate.Format("2006-01-02"), weekStart.Format("2006-01-02"))
            continue
        }

        idx, ok := jobIndex[key.JobCode]
        if !ok {
            log.Printf("⚠️ Job code %q not in job list; skipping", key.JobCode)
            continue
        }

        codeCol := jobCodeColumns[idx]

        // Decide which block (regular vs OT) to write into
        baseRow := 5 // regular
        if key.Overtime {
            baseRow = 16 // overtime block
        }
        row := baseRow + dayOffset

        cellRef := fmt.Sprintf("%s%d", codeCol, row)
        if err := file.SetCellValue(sheetName, cellRef, totalHours); err != nil {
            return fmt.Errorf("failed setting %s: %w", cellRef, err)
        }

        log.Printf("✏️ Wrote %.2f hours to %s (Job=%s, OT=%v, Date=%s)",
            totalHours, cellRef, key.JobCode, key.Overtime, entryDate.Format("2006-01-02"))
    }

    log.Printf("✅ Finished populating sheet %q", sheetName)
    return nil
}
