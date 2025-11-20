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
    // 1) Header fields (Employee, Pay Period, Year, Week Label)
    // ----------------------------------------------------------------------

    // M2 – Employee Name
    if val, err := file.GetCellValue(sheetName, "M2"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "M2", req.EmployeeName); err != nil {
            return fmt.Errorf("failed setting M2: %w", err)
        }
        log.Printf("✏️ Set M2 (Employee Name) = %s", req.EmployeeName)
    } else {
        log.Printf("⚠️ Skipping M2 (formula or error): %v", err)
    }

    // AJ2 – Pay Period #
    if val, err := file.GetCellValue(sheetName, "AJ2"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "AJ2", req.PayPeriodNum); err != nil {
            return fmt.Errorf("failed setting AJ2: %w", err)
        }
        log.Printf("✏️ Set AJ2 (Pay Period) = %d", req.PayPeriodNum)
    } else {
        log.Printf("⚠️ Skipping AJ2 (formula or error): %v", err)
    }

    // AJ3 – Year
    if val, err := file.GetCellValue(sheetName, "AJ3"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "AJ3", req.Year); err != nil {
            return fmt.Errorf("failed setting AJ3: %w", err)
        }
        log.Printf("✏️ Set AJ3 (Year) = %d", req.Year)
    } else {
        log.Printf("⚠️ Skipping AJ3 (formula or error): %v", err)
    }

    // AJ4 – Week Label (safe to overwrite)
    if err := file.SetCellValue(sheetName, "AJ4", weekLabel); err != nil {
        return fmt.Errorf("failed setting AJ4: %w", err)
    }
    log.Printf("✏️ Set AJ4 (Week Label) = %s", weekLabel)

    // ----------------------------------------------------------------------
    // 2) Week start date → Excel serial in B4
    // ----------------------------------------------------------------------

    var weekStart time.Time

    // Prefer explicit WeekStartDate if present
    if req.WeekStartDate != "" {
        if t, err := time.Parse(time.RFC3339, req.WeekStartDate); err == nil {
            weekStart = t.UTC().Truncate(24 * time.Hour)
        } else {
            log.Printf("⚠️ Failed to parse WeekStartDate=%q: %v", req.WeekStartDate, err)
        }
    }

    // Fallback: earliest entry date in this week
    if weekStart.IsZero() && len(entries) > 0 {
        var earliest time.Time
        for _, e := range entries {
            t, err := time.Parse(time.RFC3339, e.Date)
            if err != nil {
                continue
            }
            t = t.UTC().Truncate(24 * time.Hour)
            if earliest.IsZero() || t.Before(earliest) {
                earliest = t
            }
        }
        if !earliest.IsZero() {
            weekStart = earliest
        }
    }

    // Last resort: today
    if weekStart.IsZero() {
        weekStart = time.Now().UTC().Truncate(24 * time.Hour)
    }

    excelEpoch := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
    daysSinceEpoch := weekStart.Sub(excelEpoch).Hours() / 24.0

    // B4 – Week start date serial
    if val, err := file.GetCellValue(sheetName, "B4"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "B4", daysSinceEpoch); err != nil {
            return fmt.Errorf("failed setting B4: %w", err)
        }
        log.Printf("✏️ Set B4 (Week Start) = %.2f", daysSinceEpoch)
    } else {
        log.Printf("⚠️ Skipping B4 (formula or error): %v", err)
    }

    // ----------------------------------------------------------------------
    // 3) Job headers (Regular row 4, OT row 15)
    //    CODE columns (C,E,G,...) are where HOURS live.
    //    JOB columns  (D,F,H,...) are the job names/numbers.
    // ----------------------------------------------------------------------

    codeCols := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
    nameCols := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}

    jobIndex := make(map[string]int) // JobCode -> index into codeCols/nameCols

    if len(req.Jobs) > len(codeCols) {
        log.Printf("⚠️ Too many jobs (%d); template supports %d", len(req.Jobs), len(codeCols))
    }

    for i, job := range req.Jobs {
        if i >= len(codeCols) {
            break
        }
        codeCol := codeCols[i]
        nameCol := nameCols[i]

        // Regular headers (row 4)
        if err := file.SetCellValue(sheetName, codeCol+"4", job.JobCode); err != nil {
            return fmt.Errorf("failed setting %s4: %w", codeCol, err)
        }
        if err := file.SetCellValue(sheetName, nameCol+"4", job.JobName); err != nil {
            return fmt.Errorf("failed setting %s4: %w", nameCol, err)
        }

        // Overtime headers (row 15) mirror regular
        if err := file.SetCellValue(sheetName, codeCol+"15", job.JobCode); err != nil {
            return fmt.Errorf("failed setting %s15: %w", codeCol, err)
        }
        if err := file.SetCellValue(sheetName, nameCol+"15", job.JobName); err != nil {
            return fmt.Errorf("failed setting %s15: %w", nameCol, err)
        }

        jobIndex[job.JobCode] = i
        log.Printf("📋 Job %d: Code=%s Name=%s (cols %s/%s)", i+1, job.JobCode, job.JobName, codeCol, nameCol)
    }

    // ----------------------------------------------------------------------
    // 4) Aggregate entries by (date, job, overtime)
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
    // 5) Fill date columns (B5–B11 regular, B16–B22 OT)
    // ----------------------------------------------------------------------

    for i := 0; i < 7; i++ {
        dayDate := weekStart.AddDate(0, 0, i)
        daySerial := dayDate.Sub(excelEpoch).Hours() / 24.0

        // Regular date row
        regRow := 5 + i
        regCell := "B" + strconv.Itoa(regRow)
        if val, _ := file.GetCellValue(sheetName, regCell); !strings.HasPrefix(val, "=") {
            if err := file.SetCellValue(sheetName, regCell, daySerial); err != nil {
                return fmt.Errorf("failed setting %s: %w", regCell, err)
            }
        }

        // Overtime date row
        otRow := 16 + i
        otCell := "B" + strconv.Itoa(otRow)
        if val, _ := file.GetCellValue(sheetName, otCell); !strings.HasPrefix(val, "=") {
            if err := file.SetCellValue(sheetName, otCell, daySerial); err != nil {
                return fmt.Errorf("failed setting %s: %w", otCell, err)
            }
        }
    }

    // ----------------------------------------------------------------------
    // 6) Write hours into CODE columns only (C,E,G,...)
    //
    // Regular rows:  5–11  (Sun–Sat)
    // Overtime rows: 16–22 (Sun–Sat)
    // ----------------------------------------------------------------------

    for key, hours := range agg {
        entryDate, err := time.Parse(time.RFC3339, key.Date)
        if err != nil {
            log.Printf("⚠️ Skipping entry with bad date %q: %v", key.Date, err)
            continue
        }
        entryDate = entryDate.UTC().Truncate(24 * time.Hour)

        dayOffset := int(entryDate.Sub(weekStart).Hours() / 24.0)
        if dayOffset < 0 || dayOffset > 6 {
            log.Printf("⚠️ Skipping entry on %s (offset %d outside week from %s)",
                entryDate.Format("2006-01-02"), dayOffset, weekStart.Format("2006-01-02"))
            continue
        }

        idx, ok := jobIndex[key.JobCode]
        if !ok {
            log.Printf("⚠️ Job code %q not in job list; skipping", key.JobCode)
            continue
        }

        col := codeCols[idx]
        baseRow := 5
        if key.Overtime {
            baseRow = 16
        }
        row := baseRow + dayOffset
        cellRef := fmt.Sprintf("%s%d", col, row)

        if err := file.SetCellValue(sheetName, cellRef, hours); err != nil {
            return fmt.Errorf("failed setting %s: %w", cellRef, err)
        }

        log.Printf("✏️ Wrote %.2f hours to %s (Job=%s, OT=%v, Date=%s)",
            hours, cellRef, key.JobCode, key.Overtime, entryDate.Format("2006-01-02"))
    }

    log.Printf("✅ Finished populating sheet %q", sheetName)
    return nil
}
