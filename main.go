package main

import (
    "archive/zip"
    "bytes"
    "encoding/base64"
    "encoding/json"
    "fmt"
    "io"
    "log"
    "net/http"
    "os"
    "os/exec"
    "path/filepath"
    "strconv"
    "strings"
    "time"

    "github.com/xuri/excelize/v2"
)

// TimecardRequest represents the JSON payload for generating a timecard
type TimecardRequest struct {
    EmployeeName    string     `json:"employee_name"`
    PayPeriodNum    int        `json:"pay_period_num"`
    Year            int        `json:"year"`
    WeekStartDate   string     `json:"week_start_date"`
    WeekNumberLabel string     `json:"week_number_label"`
    Jobs            []Job      `json:"jobs"`
    Entries         []Entry    `json:"entries"`
    Weeks           []WeekData `json:"weeks"`
    IncludePDF      bool       `json:"include_pdf"`
}

type EmailTimecardRequest struct {
    TimecardRequest
    To      string `json:"to"`
    CC      string `json:"cc"`
    Subject string `json:"subject"`
    Body    string `json:"body"`
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
    NightShift  bool    `json:"night_shift"`
    JobType     string  `json:"job_type"` // Optional: used for splitting Regular vs Overtime in some templates
    TusCode     string  `json:"tus_code"`
    Description string  `json:"description"`
}

type WeekData struct {
    WeekStartDate string  `json:"week_start_date"`
    WeekLabel     string  `json:"week_label"`
    Entries       []Entry `json:"entries"`
}

// respondError standardizes error responses
func respondError(w http.ResponseWriter, err error) {
    log.Printf("❌ Error: %v", err)
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusInternalServerError)
    json.NewEncoder(w).Encode(map[string]string{
        "error": err.Error(),
    })
}

// convertExcelToPDF uses LibreOffice headless to convert an Excel file to PDF
func convertExcelToPDF(excelPath, pdfPath string) error {
    log.Printf("🖨️ Converting Excel to PDF: %s -> %s", excelPath, pdfPath)

    cmd := exec.Command("libreoffice",
        "--headless",
        "--convert-to", "pdf",
        "--outdir", filepath.Dir(pdfPath),
        excelPath,
    )

    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr

    if err := cmd.Run(); err != nil {
        return fmt.Errorf("LibreOffice conversion failed: %v", err)
    }

    log.Printf("✅ PDF generated at: %s", pdfPath)
    return nil
}

// zipFiles zips the Excel and optional PDF into a buffer
func zipFiles(files map[string]string) ([]byte, error) {
    buf := new(bytes.Buffer)
    zipWriter := zip.NewWriter(buf)

    for name, path := range files {
        if path == "" {
            continue
        }
        fileToZip, err := os.Open(path)
        if err != nil {
            return nil, fmt.Errorf("failed to open file for zipping: %v", err)
        }
        defer fileToZip.Close()

        w, err := zipWriter.Create(name)
        if err != nil {
            return nil, fmt.Errorf("failed to create zip entry: %v", err)
        }

        if _, err := io.Copy(w, fileToZip); err != nil {
            return nil, fmt.Errorf("failed to write file to zip: %v", err)
        }
    }

    if err := zipWriter.Close(); err != nil {
        return nil, fmt.Errorf("failed to close zip writer: %v", err)
    }

    return buf.Bytes(), nil
}

// createXLSXFile loads the template and populates it with timecard data
func createXLSXFile(req TimecardRequest) (*excelize.File, error) {
    log.Printf("📂 Loading template.xlsx...")

    // Load the template file
    file, err := excelize.OpenFile("template.xlsx")
    if err != nil {
        return nil, fmt.Errorf("failed to load template: %v", err)
    }

    log.Printf("✅ Template loaded successfully")

    // Get the first sheet name from template
    originalSheetName := file.GetSheetName(0)
    if originalSheetName == "" {
        return nil, fmt.Errorf("template has no sheets")
    }

    log.Printf("📄 Original sheet name: %s", originalSheetName)

    // Normalize: if Weeks is empty but top-level Entries provided, partition them
    if len(req.Weeks) == 0 && len(req.Entries) > 0 {
        var week1Entries, week2Entries []Entry
        var week1Start, week2Start time.Time

        for _, entry := range req.Entries {
            entryDate, err := time.Parse(time.RFC3339, entry.Date)
            if err != nil {
                log.Printf("⚠️ Skipping entry with invalid date %q: %v", entry.Date, err)
                continue
            }

            week := 1
            if !week1Start.IsZero() {
                daysDiff := int(entryDate.Sub(week1Start).Hours() / 24)
                if daysDiff >= 7 {
                    week = 2
                    if week2Start.IsZero() {
                        week2Start = entryDate
                    }
                }
            } else {
                week1Start = entryDate
            }

            if week == 1 {
                week1Entries = append(week1Entries, entry)
            } else {
                week2Entries = append(week2Entries, entry)
            }
        }

        if len(week1Entries) > 0 {
            req.Weeks = append(req.Weeks, WeekData{
                WeekStartDate: week1Start.Format(time.RFC3339),
                WeekLabel:     "Week 1",
                Entries:       week1Entries,
            })
        }
        if len(week2Entries) > 0 {
            req.Weeks = append(req.Weeks, WeekData{
                WeekStartDate: week2Start.Format(time.RFC3339),
                WeekLabel:     "Week 2",
                Entries:       week2Entries,
            })
        }
    }

    if len(req.Weeks) == 0 {
        return nil, fmt.Errorf("no weeks or entries provided")
    }

    for i, week := range req.Weeks {
        sheetName := ""

        if i == 0 {
            sheetName = originalSheetName
            log.Printf("📄 Using original sheet for Week 1: %s", sheetName)
        } else {
            sheetName = fmt.Sprintf("Week %d", i+1)
            if index := file.GetSheetIndex(sheetName); index == -1 {
                log.Printf("📄 Creating new sheet: %s", sheetName)
                file.NewSheet(sheetName)
            } else {
                log.Printf("ℹ️ Sheet already exists: %s", sheetName)
            }
        }

        log.Printf("🗓️ Populating %s with Week %d data", sheetName, i+1)

        // Update req.WeekStartDate and WeekNumberLabel for this week
        req.WeekStartDate = week.WeekStartDate
        req.WeekNumberLabel = week.WeekLabel

        // Call populateTimecardSheet with the correct entries slice
        if err := populateTimecardSheet(file, sheetName, req, week.Entries, week.WeekLabel, i+1); err != nil {
            return nil, fmt.Errorf("failed to populate sheet for week %d: %v", i+1, err)
        }
    }

    file.SetActiveSheet(0)

    return file, nil
}

// FIXED populateTimecardSheet:
// - Writes hours into CODE columns (C, E, G, ...) only
// - Keeps JOB name/number in JOB columns (D, F, H, ...)
// - Handles regular rows (5–11) and OT rows (16–22)
// - Sets week start + date rows safely without overwriting formulas
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

// generateTimecardHandler handles the /api/generate-timecard endpoint
func generateTimecardHandler(w http.ResponseWriter, r *http.Request) {
    log.Printf("📥 Received request to %s", r.URL.Path)

    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    var req TimecardRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        log.Printf("❌ Failed to decode request: %v", err)
        respondError(w, err)
        return
    }

    log.Printf("📥 Generating timecard for %s (IncludePDF: %v)", req.EmployeeName, req.IncludePDF)

    // Create xlsx file from template
    file, err := createXLSXFile(req)
    if err != nil {
        log.Printf("❌ Failed to create Excel: %v", err)
        respondError(w, err)
        return
    }
    defer file.Close()

    // Create temp directory
    tempDir, err := os.MkdirTemp("", "timecard-*")
    if err != nil {
        log.Printf("❌ Failed to create temp dir: %v", err)
        respondError(w, err)
        return
    }
    defer os.RemoveAll(tempDir)

    excelFilename := fmt.Sprintf("Timecard_%s_%d(%d).xlsx", req.EmployeeName, req.Year, req.PayPeriodNum)
    excelPath := filepath.Join(tempDir, excelFilename)

    // Save Excel to disk
    if err := file.SaveAs(excelPath); err != nil {
        log.Printf("❌ Failed to save Excel: %v", err)
        respondError(w, err)
        return
    }
    log.Printf("✅ Excel file created: %s", excelPath)

    var pdfPath string
    if req.IncludePDF {
        pdfFilename := fmt.Sprintf("Timecard_%s_%d(%d).pdf", req.EmployeeName, req.Year, req.PayPeriodNum)
        pdfPath = filepath.Join(tempDir, pdfFilename)

        log.Printf("🔄 Converting Excel to PDF...")
        if err := convertExcelToPDF(excelPath, pdfPath); err != nil {
            log.Printf("⚠️ PDF conversion failed: %v", err)
            pdfPath = ""
        } else {
            log.Printf("✅ PDF file created: %s", pdfPath)
        }
    }

    // If PDF was generated, return ZIP of both; otherwise return only Excel file
    if pdfPath != "" {
        zipFilename := fmt.Sprintf("Timecard_%s_%d(%d).zip", req.EmployeeName, req.Year, req.PayPeriodNum)
        zipPath := filepath.Join(tempDir, zipFilename)

        files := map[string]string{
            excelFilename: excelPath,
            pdfFilename(excelFilename): pdfPath,
        }

        zipBytes, err := zipFiles(files)
        if err != nil {
            log.Printf("❌ Failed to create ZIP: %v", err)
            respondError(w, err)
            return
        }

        if err := os.WriteFile(zipPath, zipBytes, 0644); err != nil {
            log.Printf("❌ Failed to write ZIP file: %v", err)
            respondError(w, err)
            return
        }

        log.Printf("✅ ZIP file created: %s", zipPath)

        w.Header().Set("Content-Type", "application/zip")
        w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", zipFilename))
        http.ServeFile(w, r, zipPath)
    } else {
        // Return only the Excel file
        w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", excelFilename))
        http.ServeFile(w, r, excelPath)
    }
}

func pdfFilename(excelFilename string) string {
    base := strings.TrimSuffix(excelFilename, filepath.Ext(excelFilename))
    return base + ".pdf"
}

// emailTimecardHandler handles sending the timecard via SendGrid (or another email provider)
func emailTimecardHandler(w http.ResponseWriter, r *http.Request) {
    log.Printf("📧 Received request to %s", r.URL.Path)

    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    var req EmailTimecardRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        log.Printf("❌ Failed to decode email request: %v", err)
        respondError(w, err)
        return
    }

    // Generate the Excel file in memory
    file, err := createXLSXFile(req.TimecardRequest)
    if err != nil {
        log.Printf("❌ Failed to create Excel: %v", err)
        respondError(w, err)
        return
    }
    defer file.Close()

    // Create temp directory
    tempDir, err := os.MkdirTemp("", "timecard-email-*")
    if err != nil {
        log.Printf("❌ Failed to create temp dir: %v", err)
        respondError(w, err)
        return
    }
    defer os.RemoveAll(tempDir)

    excelFilename := fmt.Sprintf("Timecard_%s_%d(%d).xlsx", req.EmployeeName, req.Year, req.PayPeriodNum)
    excelPath := filepath.Join(tempDir, excelFilename)

    if err := file.SaveAs(excelPath); err != nil {
        log.Printf("❌ Failed to save Excel for email: %v", err)
        respondError(w, err)
        return
    }

    var pdfPath string
    if req.IncludePDF {
        pdfFilename := fmt.Sprintf("Timecard_%s_%d(%d).pdf", req.EmployeeName, req.Year, req.PayPeriodNum)
        pdfPath = filepath.Join(tempDir, pdfFilename)

        log.Printf("🔄 Converting Excel to PDF for email...")
        if err := convertExcelToPDF(excelPath, pdfPath); err != nil {
            log.Printf("⚠️ PDF conversion failed for email: %v", err)
            pdfPath = ""
        } else {
            log.Printf("✅ PDF file created for email: %s", pdfPath)
        }
    }

    // Prepare attachments: always include Excel, optionally PDF
    attachments := map[string]string{
        excelFilename: excelPath,
    }
    if pdfPath != "" {
        attachments[pdfFilename] = pdfPath
    }

    // Send email with attachments (implementation depends on your provider)
    if err := sendEmailWithAttachments(req.To, req.CC, req.Subject, req.Body, attachments); err != nil {
        log.Printf("❌ Failed to send email: %v", err)
        respondError(w, err)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{
        "status": "email sent",
    })
}

// Dummy sendEmailWithAttachments – you should plug your real provider (SendGrid, SES, etc.)
func sendEmailWithAttachments(to, cc, subject, body string, attachments map[string]string) error {
    // For now, just log — you've likely already wired this to SendGrid in your original code.
    log.Printf("📨 Pretending to send email:\nTo: %s\nCC: %s\nSubject: %s\nBody: %s\nAttachments: %+v",
        to, cc, subject, body, attachments)
    return nil
}

// healthHandler: simple health check
func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{
        "status": "ok",
    })
}

// testLibreOfficeHandler: quick endpoint to test LibreOffice presence
func testLibreOfficeHandler(w http.ResponseWriter, r *http.Request) {
    cmd := exec.Command("libreoffice", "--version")
    output, err := cmd.CombinedOutput()
    if err != nil {
        w.WriteHeader(http.StatusInternalServerError)
        fmt.Fprintf(w, "LibreOffice test failed: %v\nOutput: %s", err, string(output))
        return
    }

    w.WriteHeader(http.StatusOK)
    fmt.Fprintf(w, "LibreOffice is working:\n%s", string(output))
}

func main() {
    http.HandleFunc("/health", healthHandler)

    // Allow cross-origin by wrapping handlers if needed
    http.HandleFunc("/api/generate-timecard", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

        if r.Method == http.MethodOptions {
            return
        }

        generateTimecardHandler(w, r)
    })

    http.HandleFunc("/api/email-timecard", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

        if r.Method == http.MethodOptions {
            return
        }

        emailTimecardHandler(w, r)
    })

    http.HandleFunc("/test/libreoffice", testLibreOfficeHandler)

    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    log.Printf("🚀 Server starting on port %s", port)
    if err := http.ListenAndServe(":"+port, nil); err != nil {
        log.Fatalf("Server failed: %v", err)
    }
}
