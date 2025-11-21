package main

import (
    "bytes"
    "encoding/base64"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "net/smtp"
    "os"
    "strings"
    "time"

    "github.com/xuri/excelize/v2"
)

// TimecardRequest matches the Swift GoTimecardRequest structure
type TimecardRequest struct {
    EmployeeName     string      `json:"employee_name"`
    PayPeriodNum     int         `json:"pay_period_num"`
    Year             int         `json:"year"`
    WeekStartDate    string      `json:"week_start_date"`
    WeekNumberLabel  string      `json:"week_number_label"`
    Jobs             []Job       `json:"jobs"`
    Entries          []Entry     `json:"entries"`
    Weeks            []WeekData  `json:"weeks,omitempty"`
}

type Job struct {
    JobCode string `json:"job_code"`
    JobName string `json:"job_name"`
}

type Entry struct {
    Date        string  `json:"date"`
    JobCode     string  `json:"job_code"`
    Hours       float64 `json:"hours"`
    Overtime    bool    `json:"overtime"`
    IsNightShift bool   `json:"is_night_shift"`
}

type WeekData struct {
    WeekNumber    int     `json:"week_number"`
    WeekStartDate string  `json:"week_start_date"`
    WeekLabel     string  `json:"week_label"`
    Entries       []Entry `json:"entries"`
}

// EmailTimecardRequest for email endpoint
type EmailTimecardRequest struct {
    TimecardRequest
    To      string  `json:"to"`
    CC      *string `json:"cc"`
    Subject string  `json:"subject"`
    Body    string  `json:"body"`
}

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    // Health check endpoint
    http.HandleFunc("/health", healthHandler)

    // API endpoints
    http.HandleFunc("/api/generate-timecard", corsMiddleware(generateTimecardHandler))
    http.HandleFunc("/api/email-timecard", corsMiddleware(emailTimecardHandler))

    log.Printf("Server starting on port %s", port)
    if err := http.ListenAndServe(":"+port, nil); err != nil {
        log.Fatal(err)
    }
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte("OK"))
}

func corsMiddleware(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

        if r.Method == "OPTIONS" {
            w.WriteHeader(http.StatusOK)
            return
        }

        next(w, r)
    }
}

func generateTimecardHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    var req TimecardRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        log.Printf("Error decoding request: %v", err)
        http.Error(w, fmt.Sprintf("Invalid request: %v", err), http.StatusBadRequest)
        return
    }

    log.Printf("Generating timecard for %s", req.EmployeeName)

    // Generate Excel file
    excelData, err := generateExcelFile(req)
    if err != nil {
        log.Printf("Error generating Excel: %v", err)
        http.Error(w, fmt.Sprintf("Error generating timecard: %v", err), http.StatusInternalServerError)
        return
    }

    // Send Excel file
    w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"timecard_%s.xlsx\"", req.EmployeeName))
    w.WriteHeader(http.StatusOK)
    w.Write(excelData)

    log.Printf("Successfully generated timecard (%d bytes)", len(excelData))
}

func emailTimecardHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    var req EmailTimecardRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        log.Printf("Error decoding request: %v", err)
        http.Error(w, fmt.Sprintf("Invalid request: %v", err), http.StatusBadRequest)
        return
    }

    log.Printf("Emailing timecard for %s to %s", req.EmployeeName, req.To)

    // Generate Excel file
    excelData, err := generateExcelFile(req.TimecardRequest)
    if err != nil {
        log.Printf("Error generating Excel: %v", err)
        http.Error(w, fmt.Sprintf("Error generating timecard: %v", err), http.StatusInternalServerError)
        return
    }

    log.Printf("Generated Excel file (%d bytes) for email attachment", len(excelData))

    // Send email via SMTP
    err = sendEmail(req.To, req.CC, req.Subject, req.Body, excelData, req.EmployeeName)
    if err != nil {
        log.Printf("Error sending email: %v", err)
        http.Error(w, fmt.Sprintf("Error sending email: %v", err), http.StatusInternalServerError)
        return
    }

    response := map[string]string{
        "status":  "success",
        "message": fmt.Sprintf("Email sent to %s", req.To),
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)

    log.Printf("Email sent successfully to %s", req.To)
}

func generateExcelFile(req TimecardRequest) ([]byte, error) {
    // Open template file
    templatePath := "template.xlsx"
    f, err := excelize.OpenFile(templatePath)
    if err != nil {
        log.Printf("Warning: Template not found, creating basic file: %v", err)
        // If template doesn't exist, create a basic file
        return generateBasicExcelFile(req)
    }
    defer f.Close()

    // Normalize: if Weeks is empty but top-level Entries provided, partition them into Week 1 and Week 2
    if len(req.Weeks) == 0 && len(req.Entries) > 0 {
        // Parse overall week start; if missing or invalid, infer from earliest entry date (start of its week)
        var week1Start time.Time
        var parseErr error
        if req.WeekStartDate != "" {
            week1Start, parseErr = time.Parse(time.RFC3339, req.WeekStartDate)
        }
        if parseErr != nil || req.WeekStartDate == "" {
            // find earliest entry date
            earliest := time.Now().UTC()
            for _, e := range req.Entries {
                if t, err := time.Parse(time.RFC3339, e.Date); err == nil {
                    if t.Before(earliest) {
                        earliest = t
                    }
                }
            }
            // normalize to Sunday start of that week (Excel template assumes Sun-Sat)
            wd := int(earliest.Weekday()) // 0=Sun
            week1Start = time.Date(earliest.Year(), earliest.Month(), earliest.Day()-wd, 0, 0, 0, 0, time.UTC)
        }
        week2Start := week1Start.AddDate(0, 0, 7)

        w1 := WeekData{WeekNumber: 1, WeekStartDate: week1Start.Format(time.RFC3339), WeekLabel: "Week 1"}
        w2 := WeekData{WeekNumber: 2, WeekStartDate: week2Start.Format(time.RFC3339), WeekLabel: "Week 2"}

        for _, e := range req.Entries {
            t, err := time.Parse(time.RFC3339, e.Date)
            if err != nil {
                continue
            }
            if !t.Before(week2Start) {
                w2.Entries = append(w2.Entries, e)
            } else {
                w1.Entries = append(w1.Entries, e)
            }
        }
        // Only include weeks that actually have entries
        if len(w1.Entries) > 0 {
            req.Weeks = append(req.Weeks, w1)
        }
        if len(w2.Entries) > 0 {
            req.Weeks = append(req.Weeks, w2)
        }
    }

    // Get the first sheet (Week 1)
    sheets := f.GetSheetList()
    if len(sheets) == 0 {
        return nil, fmt.Errorf("no sheets found in template")
    }

    // Process Week 1 data
    if len(req.Weeks) > 0 {
        weekData := req.Weeks[0]
        err = fillWeekSheet(f, sheets[0], req, weekData, 1)
        if err != nil {
            log.Printf("Error filling Week 1: %v", err)
        }
    }

    // Process Week 2 data if available
    if len(sheets) > 1 && len(req.Weeks) > 1 {
        weekData := req.Weeks[1]
        err = fillWeekSheet(f, sheets[1], req, weekData, 2)
        if err != nil {
            log.Printf("Error filling Week 2: %v", err)
        }
    }

    // Force Excel to recalculate all formulas when the file is opened
    // Note: The formulas in the template will recalculate automatically when Excel opens the file
    // We just need to make sure we're not overwriting them with static values

    // Write to buffer
    buffer, err := f.WriteToBuffer()
    if err != nil {
        return nil, err
    }

    return buffer.Bytes(), nil
}

// fillWeekSheet fills a single week sheet with data
func fillWeekSheet(f *excelize.File, sheetName string, req TimecardRequest, weekData WeekData, weekNum int) error {
    // Parse week start date
    weekStart, err := time.Parse(time.RFC3339, weekData.WeekStartDate)
    if err != nil {
        return fmt.Errorf("error parsing week start date: %v", err)
    }

    log.Printf("=== Filling %s ===", sheetName)
    log.Printf("Week start: %s, Entries: %d", weekStart.Format("2006-01-02"), len(weekData.Entries))

    // Fill header information
    f.SetCellValue(sheetName, "M2", req.EmployeeName)
    f.SetCellValue(sheetName, "AJ2", req.PayPeriodNum)
    f.SetCellValue(sheetName, "AJ3", req.Year)

    // Set week start date as Excel date serial
    excelDate := timeToExcelDate(weekStart)
    f.SetCellValue(sheetName, "B4", excelDate)

    // Set week number label
    f.SetCellValue(sheetName, "AJ4", weekData.WeekLabel)

    // CRITICAL: CODE columns (C,E,G,I,K...) for job CODES and HOURS
    //           JOB columns (D,F,H,J,L...) for job NAMES/NUMBERS
    codeColumns := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
    jobColumns := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}

    // Build maps for job lookup by NUMBER (JobCode) and by CODE (JobName)
    jobByNumber := make(map[string]*Job)
    jobByCode := make(map[string]*Job)
    for i := range req.Jobs {
        j := &req.Jobs[i]
        if j.JobCode != "" {
            jobByNumber[j.JobCode] = j
        }
        if j.JobName != "" {
            jobByCode[j.JobName] = j
        }
        log.Printf("Adding job: number='%s', code='%s'", j.JobCode, j.JobName)
    }

    // Get separate job code lists for regular time and overtime
    regularJobCodes := getUniqueJobCodesForType(weekData.Entries, false) // regular time only
    overtimeJobCodes := getUniqueJobCodesForType(weekData.Entries, true) // overtime only

    log.Printf("Regular job codes: %v", regularJobCodes)
    log.Printf("Overtime job codes: %v", overtimeJobCodes)

    // Fill REGULAR TIME headers (Row 4) - only if there are regular jobs
    if len(regularJobCodes) > 0 {
        // Clear placeholder text from regular job columns that will be used
        for i := 0; i < len(regularJobCodes) && i < len(codeColumns); i++ {
            f.SetCellValue(sheetName, codeColumns[i]+"4", "")
            f.SetCellValue(sheetName, jobColumns[i]+"4", "")
        }

        // Fill regular job headers (Row 4)
        for i, jobNumberKey := range regularJobCodes {
            if i >= len(codeColumns) {
                log.Printf("Warning: More than %d regular jobs, truncating", len(codeColumns))
                break
            }

            // Remove "N-" prefix from night shift entries to look up the job
            actualJobNumber := jobNumberKey
            isNightShift := strings.HasPrefix(jobNumberKey, "N-")
            if isNightShift {
                actualJobNumber = strings.TrimPrefix(jobNumberKey, "N-")
            }

            var job *Job
            // First assume actualJobNumber is a NUMBER
            if j, ok := jobByNumber[actualJobNumber]; ok {
                job = j
            } else if j, ok := jobByCode[actualJobNumber]; ok {
                // If it's actually a CODE, use that and normalize the number from the job
                job = j
                actualJobNumber = j.JobCode
            }

            if job != nil {
                // Write the CODE (from JobName) to CODE column
                // Add "N" prefix to the CODE if it was a night shift
                codeCellRef := codeColumns[i] + "4"
                codeToWrite := job.JobName // e.g., "201"
                if isNightShift {
                    codeToWrite = "N" + job.JobName // e.g., "N201"
                }
                f.SetCellValue(sheetName, codeCellRef, codeToWrite)
                writtenValue, _ := f.GetCellValue(sheetName, codeCellRef)
                log.Printf("  Wrote code to %s: '%s', verified: '%s'", codeCellRef, codeToWrite, writtenValue)

                // Write the NUMBER (from JobCode) to JOB column (no "N" prefix on number)
                jobCellRef := jobColumns[i] + "4"
                f.SetCellValue(sheetName, jobCellRef, job.JobCode)
                writtenJobValue, _ := f.GetCellValue(sheetName, jobCellRef)
                log.Printf("  Wrote job# to %s: '%s', verified: '%s'", jobCellRef, job.JobCode, writtenJobValue)
            } else {
                log.Printf("  WARNING: Could not resolve job '%s' (by number or code)", actualJobNumber)
                // Can't find the job - write the job number to CODE column with "N" prefix if night shift
                codeToWrite := actualJobNumber
                if isNightShift {
                    codeToWrite = "N" + actualJobNumber
                }
                f.SetCellValue(sheetName, codeColumns[i]+"4", codeToWrite)
            }
        }
    }

    // Fill OVERTIME headers (Row 15) - only if there are overtime jobs
    if len(overtimeJobCodes) > 0 {
        // Clear placeholder text from overtime job columns that will be used
        for i := 0; i < len(overtimeJobCodes) && i < len(codeColumns); i++ {
            f.SetCellValue(sheetName, codeColumns[i]+"15", "")
            f.SetCellValue(sheetName, jobColumns[i]+"15", "")
        }

        // Fill overtime job headers (Row 15)
        for i, jobNumberKey := range overtimeJobCodes {
            if i >= len(codeColumns) {
                log.Printf("Warning: More than %d overtime jobs, truncating", len(codeColumns))
                break
            }

            // Remove "N-" prefix from night shift entries to look up the job
            actualJobNumber := jobNumberKey
            isNightShift := strings.HasPrefix(jobNumberKey, "N-")
            if isNightShift {
                actualJobNumber = strings.TrimPrefix(jobNumberKey, "N-")
            }

            var job *Job
            // First assume actualJobNumber is a NUMBER
            if j, ok := jobByNumber[actualJobNumber]; ok {
                job = j
            } else if j, ok := jobByCode[actualJobNumber]; ok {
                // If it's actually a CODE, use that and normalize the number from the job
                job = j
                actualJobNumber = j.JobCode
            }

            if job != nil {
                // Write the CODE (from JobName) to CODE column
                // Add "N" prefix to the CODE if it was a night shift
                codeToWrite := job.JobName // e.g., "201"
                if isNightShift {
                    codeToWrite = "N" + job.JobName // e.g., "N201"
                }
                f.SetCellValue(sheetName, codeColumns[i]+"15", codeToWrite)
                log.Printf("  Writing OT code to %s15: '%s'", codeColumns[i], codeToWrite)

                // Write the NUMBER (from JobCode) to JOB column (no "N" prefix on number)
                f.SetCellValue(sheetName, jobColumns[i]+"15", job.JobCode)
                log.Printf("  Writing OT job# to %s15: '%s' (looked up by number '%s')", jobColumns[i], job.JobCode, actualJobNumber)
            } else {
                log.Printf("  WARNING: Could not resolve job '%s' (by number or code)", actualJobNumber)
                // Can't find the job - write the job number to CODE column with "N" prefix if night shift
                codeToWrite := actualJobNumber
                if isNightShift {
                    codeToWrite = "N" + actualJobNumber
                }
                f.SetCellValue(sheetName, codeColumns[i]+"15", codeToWrite)
            }
        }
    }

    // Create a map to organize entries by date and job
    // Key format: "JobNumber" or "N-JobNumber" for night shifts
    regularTimeEntries := make(map[string]map[string]float64) // date -> jobNumberKey -> hours
    overtimeEntries := make(map[string]map[string]float64)    // date -> jobNumberKey -> hours

    for _, entry := range weekData.Entries {
        entryDate, err := time.Parse(time.RFC3339, entry.Date)
        if err != nil {
            log.Printf("Error parsing entry date: %v", err)
            continue
        }

        dateKey := entryDate.Format("2006-01-02")

        // Normalize: entry.JobCode may be a NUMBER or a CODE; translate to job NUMBER for keys
        normalizedNumber := entry.JobCode
        if _, ok := jobByNumber[normalizedNumber]; !ok {
            if j, ok2 := jobByCode[normalizedNumber]; ok2 {
                normalizedNumber = j.JobCode
            }
        }
        jobNumberKey := normalizedNumber
        if entry.IsNightShift {
            jobNumberKey = "N-" + normalizedNumber
        }

        if entry.Overtime {
            if overtimeEntries[dateKey] == nil {
                overtimeEntries[dateKey] = make(map[string]float64)
            }
            overtimeEntries[dateKey][jobNumberKey] += entry.Hours
            log.Printf("  OT entry: %s, Job %s, Hours %.1f", dateKey, jobNumberKey, entry.Hours)
        } else {
            if regularTimeEntries[dateKey] == nil {
                regularTimeEntries[dateKey] = make(map[string]float64)
            }
            regularTimeEntries[dateKey][jobNumberKey] += entry.Hours
            log.Printf("  REG entry: %s, Job %s, Hours %.1f", dateKey, jobNumberKey, entry.Hours)
        }
    }

    // Fill date column and hours data
    // Days: Sunday (row 5) through Saturday (row 11)
    for dayOffset := 0; dayOffset < 7; dayOffset++ {
        currentDate := weekStart.AddDate(0, 0, dayOffset)
        dateKey := currentDate.Format("2006-01-02")
        excelDateSerial := timeToExcelDate(currentDate)

        regularRow := 5 + dayOffset
        overtimeRow := 16 + dayOffset

        // Set date in column B for both regular and overtime sections
        f.SetCellValue(sheetName, fmt.Sprintf("B%d", regularRow), excelDateSerial)
        f.SetCellValue(sheetName, fmt.Sprintf("B%d", overtimeRow), excelDateSerial)

        // Fill regular time hours - WRITE TO CODE COLUMNS (C, E, G, I, K...)
        if regularHours, exists := regularTimeEntries[dateKey]; exists {
            for i, jobCode := range regularJobCodes {
                if i >= len(codeColumns) {
                    break
                }
                if hours, hasHours := regularHours[jobCode]; hasHours && hours > 0 {
                    cellRef := fmt.Sprintf("%s%d", codeColumns[i], regularRow)
                    f.SetCellValue(sheetName, cellRef, hours)
                    log.Printf("    Writing REG: %s = %.1f (job %s)", cellRef, hours, jobCode)
                }
            }
        }

        // Fill overtime hours - WRITE TO CODE COLUMNS (C, E, G, I, K...)
        if otHours, exists := overtimeEntries[dateKey]; exists {
            for i, jobCode := range overtimeJobCodes {
                if i >= len(codeColumns) {
                    break
                }
                if hours, hasHours := otHours[jobCode]; hasHours && hours > 0 {
                    cellRef := fmt.Sprintf("%s%d", codeColumns[i], overtimeRow)
                    f.SetCellValue(sheetName, cellRef, hours)
                    log.Printf("    Writing OT: %s = %.1f (job %s)", cellRef, hours, jobCode)
                }
            }
        }
    }

    log.Printf("=== Week %d completed ===", weekNum)
    return nil
}

// getUniqueJobCodesForType returns unique job NUMBERS from entries filtered by overtime type
// Night shift entries get "N-" prefixed to their job NUMBER
// isOvertime = true: returns only overtime job numbers
// isOvertime = false: returns only regular time job numbers
func getUniqueJobCodesForType(entries []Entry, isOvertime bool) []string {
    seen := make(map[string]bool)
    var result []string

    for _, entry := range entries {
        // Skip if not matching the type we want
        if entry.Overtime != isOvertime {
            continue
        }

        // Use the job NUMBER (from entry.JobCode)
        jobNumberKey := entry.JobCode
        // Prefix with "N-" if it's a night shift
        if entry.IsNightShift {
            jobNumberKey = "N-" + entry.JobCode
        }

        if !seen[jobNumberKey] {
            seen[jobNumberKey] = true
            result = append(result, jobNumberKey)
        }
    }

    return result
}

// getMapKeys returns the keys of a Job map for debugging
func getMapKeys(m map[string]*Job) []string {
    keys := make([]string, 0, len(m))
    for k := range m {
        keys = append(keys, k)
    }
    return keys
}

// timeToExcelDate converts a Go time.Time to Excel date serial number
// Excel's epoch is December 30, 1899
func timeToExcelDate(t time.Time) float64 {
    // Excel epoch: December 30, 1899
    excelEpoch := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
    duration := t.Sub(excelEpoch)
    days := duration.Hours() / 24.0
    return days
}

// generateBasicExcelFile creates a basic Excel file when template is not available
func generateBasicExcelFile(req TimecardRequest) ([]byte, error) {
    f := excelize.NewFile()
    defer f.Close()

    sheet := "Sheet1"
    f.SetCellValue(sheet, "A1", "Employee Name:")
    f.SetCellValue(sheet, "B1", req.EmployeeName)
    f.SetCellValue(sheet, "A2", "Pay Period:")
    f.SetCellValue(sheet, "B2", req.PayPeriodNum)
    f.SetCellValue(sheet, "A3", "Year:")
    f.SetCellValue(sheet, "B3", req.Year)
    f.SetCellValue(sheet, "A4", "Week:")
    f.SetCellValue(sheet, "B4", req.WeekNumberLabel)

    // Headers
    f.SetCellValue(sheet, "A6", "Date")
    f.SetCellValue(sheet, "B6", "Job Code")
    f.SetCellValue(sheet, "C6", "Job Name")
    f.SetCellValue(sheet, "D6", "Hours")
    f.SetCellValue(sheet, "E6", "Overtime")

    // Create job lookup
    jobMap := make(map[string]string)
    for _, job := range req.Jobs {
        jobMap[job.JobCode] = job.JobName
    }

    // Add entries
    row := 7
    totalHours := 0.0
    totalOvertimeHours := 0.0

    for _, entry := range req.Entries {
        // Parse date
        t, err := time.Parse(time.RFC3339, entry.Date)
        if err != nil {
            log.Printf("Error parsing date: %v", err)
            continue
        }

        f.SetCellValue(sheet, fmt.Sprintf("A%d", row), t.Format("2006-01-02"))

        // Prefix job code with "N" if night shift for output consistency
        jobCodeToWrite := entry.JobCode
        if entry.IsNightShift {
            jobCodeToWrite = "N" + jobCodeToWrite
        }
        f.SetCellValue(sheet, fmt.Sprintf("B%d", row), jobCodeToWrite)

        f.SetCellValue(sheet, fmt.Sprintf("C%d", row), jobMap[entry.JobCode])
        f.SetCellValue(sheet, fmt.Sprintf("D%d", row), entry.Hours)

        overtimeStr := "No"
        if entry.Overtime {
            overtimeStr = "Yes"
            totalOvertimeHours += entry.Hours
        }
        f.SetCellValue(sheet, fmt.Sprintf("E%d", row), overtimeStr)

        totalHours += entry.Hours
        row++
    }

    // Add totals
    row++
    f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Hours:")
    f.SetCellValue(sheet, fmt.Sprintf("D%d", row), totalHours)
    row++
    f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Overtime:")
    f.SetCellValue(sheet, fmt.Sprintf("D%d", row), totalOvertimeHours)

    // Write to buffer
    buffer, err := f.WriteToBuffer()
    if err != nil {
        return nil, err
    }

    return buffer.Bytes(), nil
}

// sendEmail sends an email with Excel attachment via SMTP
func sendEmail(to string, cc *string, subject string, body string, attachment []byte, employeeName string) error {
    // Get SMTP configuration from environment variables
    smtpHost := os.Getenv("SMTP_HOST")
    smtpPort := os.Getenv("SMTP_PORT")
    smtpUser := os.Getenv("SMTP_USER")
    smtpPass := os.Getenv("SMTP_PASS")
    fromEmail := os.Getenv("SMTP_FROM")

    // Check if SMTP is configured
    if smtpHost == "" || smtpPort == "" || smtpUser == "" || smtpPass == "" {
        return fmt.Errorf("SMTP not configured - please set SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS environment variables")
    }

    if fromEmail == "" {
        fromEmail = smtpUser // Use SMTP user as sender if FROM not specified
    }

    // Parse recipients
    recipients := strings.Split(to, ",")
    for i := range recipients {
        recipients[i] = strings.TrimSpace(recipients[i])
    }

    var ccRecipients []string
    if cc != nil && *cc != "" {
        ccRecipients = strings.Split(*cc, ",")
        for i := range ccRecipients {
            ccRecipients[i] = strings.TrimSpace(ccRecipients[i])
        }
    }

    // Combine all recipients for SMTP
    allRecipients := append([]string{}, recipients...)
    allRecipients = append(allRecipients, ccRecipients...)

    // Create email message with attachment
    fileName := fmt.Sprintf("timecard_%s_%s.xlsx",
        strings.ReplaceAll(employeeName, " ", "_"),
        time.Now().Format("2006-01-02"))

    message := buildEmailMessage(fromEmail, recipients, ccRecipients, subject, body, attachment, fileName)

    // Connect to SMTP server
    auth := smtp.PlainAuth("", smtpUser, smtpPass, smtpHost)
    addr := fmt.Sprintf("%s:%s", smtpHost, smtpPort)

    // Send email
    err := smtp.SendMail(addr, auth, fromEmail, allRecipients, []byte(message))
    if err != nil {
        return fmt.Errorf("failed to send email: %v", err)
    }

    log.Printf("Email sent successfully to %s", to)
    return nil
}

// buildEmailMessage constructs a MIME email message with attachment
func buildEmailMessage(from string, to []string, cc []string, subject string, body string, attachment []byte, fileName string) string {
    boundary := "==BOUNDARY=="

    var buf bytes.Buffer

    // Headers
    buf.WriteString(fmt.Sprintf("From: %s\r\n", from))
    buf.WriteString(fmt.Sprintf("To: %s\r\n", strings.Join(to, ", ")))
    if len(cc) > 0 {
        buf.WriteString(fmt.Sprintf("Cc: %s\r\n", strings.Join(cc, ", ")))
    }
    buf.WriteString(fmt.Sprintf("Subject: %s\r\n", subject))
    buf.WriteString("MIME-Version: 1.0\r\n")
    buf.WriteString(fmt.Sprintf("Content-Type: multipart/mixed; boundary=\"%s\"\r\n", boundary))
    buf.WriteString("\r\n")

    // Body
    buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
    buf.WriteString("Content-Type: text/plain; charset=\"utf-8\"\r\n")
    buf.WriteString("Content-Transfer-Encoding: quoted-printable\r\n")
    buf.WriteString("\r\n")
    buf.WriteString(body)
    buf.WriteString("\r\n\r\n")

    // Attachment
    if len(attachment) > 0 {
        buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
        buf.WriteString("Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n")
        buf.WriteString(fmt.Sprintf("Content-Disposition: attachment; filename=\"%s\"\r\n", fileName))
        buf.WriteString("Content-Transfer-Encoding: base64\r\n")
        buf.WriteString("\r\n")

        // Encode attachment in base64
        encoded := base64.StdEncoding.EncodeToString(attachment)
        // Split into 76-character lines as per RFC 2045
        for i := 0; i < len(encoded); i += 76 {
            end := i + 76
            if end > len(encoded) {
                end = len(encoded)
            }
            buf.WriteString(encoded[i:end])
            buf.WriteString("\r\n")
        }
        buf.WriteString("\r\n")
    }

    // End boundary
    buf.WriteString(fmt.Sprintf("--%s--\r\n", boundary))

    return buf.String()
}

