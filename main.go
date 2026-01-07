
// main.go
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

/* =========================
   Request / Models
   ========================= */

type TimecardRequest struct {
    EmployeeName     string     `json:"employee_name"`
    PayPeriodNum     int        `json:"pay_period_num"`
    Year             int        `json:"year"`
    WeekStartDate    string     `json:"week_start_date"`
    WeekNumberLabel  string     `json:"week_number_label"`
    Jobs             []Job      `json:"jobs"`
    Entries          []Entry    `json:"entries"`
    Weeks            []WeekData `json:"weeks,omitempty"`
}

type Job struct {
    // JobCode: job number (e.g., "29699")
    JobCode string `json:"job_code"`
    // JobName: labour code (e.g., "201", "H")
    JobName string `json:"job_name"`
}

type Entry struct {
    Date         string  `json:"date"`          // RFC3339
    JobCode      string  `json:"job_code"`      // may be a job number OR a labour code
    Hours        float64 `json:"hours"`
    Overtime     bool    `json:"overtime"`
    IsNightShift bool    `json:"is_night_shift"`
}

type WeekData struct {
    WeekNumber    int     `json:"week_number"`
    WeekStartDate string  `json:"week_start_date"` // RFC3339 start of week (Sunday)
    WeekLabel     string  `json:"week_label"`
    Entries       []Entry `json:"entries"`
}

type EmailTimecardRequest struct {
    TimecardRequest
    To      string  `json:"to"`
    CC      *string `json:"cc"`
    Subject string  `json:"subject"`
    Body    string  `json:"body"`
}

/* ===============
   Server bootstrap
   =============== */

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    http.HandleFunc("/health", healthHandler)
    http.HandleFunc("/api/generate-timecard", corsMiddleware(generateTimecardHandler))
    http.HandleFunc("/api/email-timecard", corsMiddleware(emailTimecardHandler))

    log.Printf("Server starting on :%s ...", port)
    log.Fatal(http.ListenAndServe(":"+port, nil))
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    _, _ = w.Write([]byte("OK"))
}

func corsMiddleware(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        next(w, r)
    }
}

/* ===================
   API: Generate / Mail
   =================== */

func generateTimecardHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    var req TimecardRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        log.Printf("decode error: %v", err)
        http.Error(w, fmt.Sprintf("invalid request: %v", err), http.StatusBadRequest)
        return
    }

    log.Printf("Generating timecard for %s", req.EmployeeName)
    excelData, err := generateExcelFile(req)
    if err != nil {
        log.Printf("excel error: %v", err)
        http.Error(w, fmt.Sprintf("error generating timecard: %v", err), http.StatusInternalServerError)
        return
    }

    w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"timecard_%s.xlsx\"", safeFile(req.EmployeeName)))
    w.WriteHeader(http.StatusOK)
    _, _ = w.Write(excelData)

    log.Printf("OK: timecard bytes=%d", len(excelData))
}

func emailTimecardHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    var req EmailTimecardRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        log.Printf("decode error: %v", err)
        http.Error(w, fmt.Sprintf("invalid request: %v", err), http.StatusBadRequest)
        return
    }

    log.Printf("Emailing timecard for %s → %s", req.EmployeeName, req.To)

    excelData, err := generateExcelFile(req.TimecardRequest)
    if err != nil {
        log.Printf("excel error: %v", err)
        http.Error(w, fmt.Sprintf("error generating timecard: %v", err), http.StatusInternalServerError)
        return
    }

    if err := sendEmail(req.To, req.CC, req.Subject, req.Body, excelData, req.EmployeeName); err != nil {
        log.Printf("send email error: %v", err)
        http.Error(w, fmt.Sprintf("error sending email: %v", err), http.StatusInternalServerError)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(map[string]string{
        "status":  "success",
        "message": fmt.Sprintf("Email sent to %s", req.To),
    })
}

/* ===========================
   Excel generation (Excelize)
   =========================== */

// styles holds Style IDs created once per workbook
type styles struct {
    DateStyle       int // "yyyy-mm-dd", centered
    HeaderStyle     int // bold, centered, light gray fill, thin border
    HoursStyle      int // numeric hours with 2 decimals
    ThinBorderStyle int // thin black border on all sides
}

func generateExcelFile(req TimecardRequest) ([]byte, error) {
    // Try to open template.xlsx; if missing, build a basic sheet
    f, err := excelize.OpenFile("template.xlsx")
    if err != nil {
        log.Printf("Template not found, creating basic file: %v", err)
        return generateBasicExcelFile(req)
    }
    defer func() { _ = f.Close() }()

    // Build all styles once; use SetCellStyle to persist formatting into the file
    st, err := buildStyles(f)
    if err != nil {
        return nil, fmt.Errorf("create styles: %w", err)
    }

    // If Weeks[] is empty but we got top-level Entries, partition them into two weeks
    if len(req.Weeks) == 0 && len(req.Entries) > 0 {
        week1Start := inferWeekStart(req.WeekStartDate, req.Entries)
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
        if len(w1.Entries) > 0 {
            req.Weeks = append(req.Weeks, w1)
        }
        if len(w2.Entries) > 0 {
            req.Weeks = append(req.Weeks, w2)
        }
    }

    // Get sheets from template (expecting "Week 1", "Week 2")
    sheets := f.GetSheetList()
    if len(sheets) == 0 {
        return nil, fmt.Errorf("no sheets found in template")
    }

    if len(req.Weeks) > 0 {
        if err := fillWeekSheet(f, sheets[0], req, req.Weeks[0], 1, st); err != nil {
            log.Printf("Week 1 fill error: %v", err)
        }
    }
    if len(sheets) > 1 && len(req.Weeks) > 1 {
        if err := fillWeekSheet(f, sheets[1], req, req.Weeks[1], 2, st); err != nil {
            log.Printf("Week 2 fill error: %v", err)
        }
    }

    // Optional: ask Excel to refresh cached values when opened
    if err := f.UpdateLinkedValue(); err != nil {
        log.Printf("UpdateLinkedValue warning: %v", err)
    }

    buf, err := f.WriteToBuffer()
    if err != nil {
        return nil, err
    }
    return buf.Bytes(), nil
}

func inferWeekStart(weekStartStr string, entries []Entry) time.Time {
    if weekStartStr != "" {
        if t, err := time.Parse(time.RFC3339, weekStartStr); err == nil {
            return t
        }
    }
    earliest := time.Now().UTC()
    for _, e := range entries {
        if t, err := time.Parse(time.RFC3339, e.Date); err == nil {
            if t.Before(earliest) {
                earliest = t
            }
        }
    }
    // normalize to Sunday (Excel template assumes Sun-Sat)
    wd := int(earliest.Weekday()) // 0=Sun
    return time.Date(earliest.Year(), earliest.Month(), earliest.Day()-wd, 0, 0, 0, 0, time.UTC)
}

// buildStyles: create style IDs for borders, headers, dates, hours
func buildStyles(f *excelize.File) (styles, error) {
    var s styles

    // Date style: "yyyy-mm-dd" centered (use NumFmt:14 for locale short date)
    dateFmt := "yyyy-mm-dd"
    ds, err := f.NewStyle(&excelize.Style{
        Alignment:    &excelize.Alignment{Horizontal: "center", Vertical: "center"},
        CustomNumFmt: &dateFmt,
    })
    if err != nil {
        return s, err
    }
    s.DateStyle = ds

    // Header style: bold, centered, light gray fill, thin border
    hs, err := f.NewStyle(&excelize.Style{
        Font:      &excelize.Font{Bold: true},
        Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center", WrapText: true},
        Fill:      excelize.Fill{Type: "pattern", Pattern: 1, Color: []string{"D9D9D9"}},
        Border: []excelize.Border{
            {Type: "left", Color: "000000", Style: 1},
            {Type: "top", Color: "000000", Style: 1},
            {Type: "bottom", Color: "000000", Style: 1},
            {Type: "right", Color: "000000", Style: 1},
        },
    })
    if err != nil {
        return s, err
    }
    s.HeaderStyle = hs

    // Hours style: centered, 2 decimal places (#,##0.00)
    hs2, err := f.NewStyle(&excelize.Style{
        Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
        NumFmt:    4, // built-in "#,##0.00"
    })
    if err != nil {
        return s, err
    }
    s.HoursStyle = hs2

    // Thin border style for tables
    bs, err := f.NewStyle(&excelize.Style{
        Border: []excelize.Border{
            {Type: "left", Color: "000000", Style: 1},
            {Type: "top", Color: "000000", Style: 1},
            {Type: "bottom", Color: "000000", Style: 1},
            {Type: "right", Color: "000000", Style: 1},
        },
    })
    if err != nil {
        return s, err
    }
    s.ThinBorderStyle = bs

    return s, nil
}

// applyBordersToRange: force borders on a rectangular region using a style
func applyBordersToRange(f *excelize.File, sheet, startCell, endCell string, borderStyle int) error {
    return f.SetCellStyle(sheet, startCell, endCell, borderStyle)
}

// fillWeekSheet: write headers, dates, and hours; apply styles & borders
func fillWeekSheet(f *excelize.File, sheetName string, req TimecardRequest, week WeekData, weekNum int, st styles) error {
    weekStart, err := time.Parse(time.RFC3339, week.WeekStartDate)
    if err != nil {
        return fmt.Errorf("parse week start: %w", err)
    }
    log.Printf("=== Filling %s (week %d) start=%s entries=%d ===",
        sheetName, weekNum, weekStart.Format("2006-01-02"), len(week.Entries))

    // Header info (simple values)
    _ = f.SetCellValue(sheetName, "M2", req.EmployeeName)
    _ = f.SetCellValue(sheetName, "AJ2", req.PayPeriodNum)
    _ = f.SetCellValue(sheetName, "AJ3", req.Year)
    _ = f.SetCellValue(sheetName, "B4", timeToExcelDate(weekStart))
    _ = f.SetCellValue(sheetName, "AJ4", week.WeekLabel)

    // Column widths for readability
    _ = f.SetColWidth(sheetName, "A", "A", 3.5)   // (if used)
    _ = f.SetColWidth(sheetName, "B", "B", 12.0)  // dates
    _ = f.SetColWidth(sheetName, "C", "AH", 8.5)  // codes/numbers/hours

    // Header rows styling
    _ = f.SetCellStyle(sheetName, "C4", "AH4", st.HeaderStyle)
    _ = f.SetCellStyle(sheetName, "C15", "AH15", st.HeaderStyle)

    // Date cells styling (week start box + daily rows)
    _ = f.SetCellStyle(sheetName, "B4", "B4", st.DateStyle)
    _ = f.SetCellStyle(sheetName, "B5", "B11", st.DateStyle)
    _ = f.SetCellStyle(sheetName, "B16", "B22", st.DateStyle)

    // Hours cells styling
    _ = f.SetCellStyle(sheetName, "C5", "AG11", st.HoursStyle)
    _ = f.SetCellStyle(sheetName, "C16", "AG22", st.HoursStyle)

    // Code & job columns lists
    codeCols := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
    jobCols := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}

    // Build job lookups
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
    }

    // Unique keys for regular/overtime
    regularKeys := getUniqueJobCodesForType(week.Entries, false)
    overtimeKeys := getUniqueJobCodesForType(week.Entries, true)

    // REGULAR headers in row 4
    if len(regularKeys) > 0 {
        for i := 0; i < len(regularKeys) && i < len(codeCols); i++ {
            _ = f.SetCellValue(sheetName, codeCols[i]+"4", "")
            _ = f.SetCellValue(sheetName, jobCols[i]+"4", "")
        }
        for i, key := range regularKeys {
            if i >= len(codeCols) {
                break
            }
            isNight := strings.HasPrefix(key, "N-")
            actual := strings.TrimPrefix(key, "N-")

            var job *Job
            if j, ok := jobByNumber[actual]; ok {
                job = j
            } else if j, ok := jobByCode[actual]; ok {
                job = j
                actual = j.JobCode
            }
            if job != nil {
                code := job.JobName
                if isNight {
                    code = "N" + code
                }
                _ = f.SetCellValue(sheetName, codeCols[i]+"4", code) // labour code
                _ = f.SetCellValue(sheetName, jobCols[i]+"4", job.JobCode)
            } else {
                // Fallback: write actual key (with N- if present) into code column
                write := actual
                if isNight {
                    write = "N" + actual
                }
                _ = f.SetCellValue(sheetName, codeCols[i]+"4", write)
            }
        }
    }

    // OVERTIME headers in row 15
    if len(overtimeKeys) > 0 {
        for i := 0; i < len(overtimeKeys) && i < len(codeCols); i++ {
            _ = f.SetCellValue(sheetName, codeCols[i]+"15", "")
            _ = f.SetCellValue(sheetName, jobCols[i]+"15", "")
        }
        for i, key := range overtimeKeys {
            if i >= len(codeCols) {
                break
            }
            isNight := strings.HasPrefix(key, "N-")
            actual := strings.TrimPrefix(key, "N-")

            var job *Job
            if j, ok := jobByNumber[actual]; ok {
                job = j
            } else if j, ok := jobByCode[actual]; ok {
                job = j
                actual = j.JobCode
            }
            if job != nil {
                code := job.JobName
                if isNight {
                    code = "N" + code
                }
                _ = f.SetCellValue(sheetName, codeCols[i]+"15", code)
                _ = f.SetCellValue(sheetName, jobCols[i]+"15", job.JobCode)
            } else {
                write := actual
                if isNight {
                    write = "N" + actual
                }
                _ = f.SetCellValue(sheetName, codeCols[i]+"15", write)
            }
        }
    }

    // Aggregate hours by date → {jobKey → hours}
    regMap := make(map[string]map[string]float64)
    otMap := make(map[string]map[string]float64)

    for _, e := range week.Entries {
        t, err := time.Parse(time.RFC3339, e.Date)
        if err != nil {
            log.Printf("bad entry date %q: %v", e.Date, err)
            continue
        }
        dateKey := t.Format("2006-01-02")

        normalized := e.JobCode
        if _, ok := jobByNumber[normalized]; !ok {
            if j, ok2 := jobByCode[normalized]; ok2 {
                normalized = j.JobCode
            }
        }
        jobKey := normalized
        if e.IsNightShift {
            jobKey = "N-" + normalized
        }

        if e.Overtime {
            if otMap[dateKey] == nil {
                otMap[dateKey] = map[string]float64{}
            }
            otMap[dateKey][jobKey] += e.Hours
        } else {
            if regMap[dateKey] == nil {
                regMap[dateKey] = map[string]float64{}
            }
            regMap[dateKey][jobKey] += e.Hours
        }
    }

    // Write dates + hours
    for d := 0; d < 7; d++ {
        day := weekStart.AddDate(0, 0, d)
        dateKey := day.Format("2006-01-02")
        serial := timeToExcelDate(day)

        rowReg := 5 + d
        rowOT := 16 + d

        _ = f.SetCellValue(sheetName, fmt.Sprintf("B%d", rowReg), serial)
        _ = f.SetCellValue(sheetName, fmt.Sprintf("B%d", rowOT), serial)

        if hours := regMap[dateKey]; hours != nil {
            for i, key := range regularKeys {
                if i >= len(codeCols) {
                    break
                }
                if v, ok := hours[key]; ok && v != 0 {
                    cell := fmt.Sprintf("%s%d", codeCols[i], rowReg)
                    _ = f.SetCellValue(sheetName, cell, v)
                }
            }
        }
        if hours := otMap[dateKey]; hours != nil {
            for i, key := range overtimeKeys {
                if i >= len(codeCols) {
                    break
                }
                if v, ok := hours[key]; ok && v != 0 {
                    cell := fmt.Sprintf("%s%d", codeCols[i], rowOT)
                    _ = f.SetCellValue(sheetName, cell, v)
                }
            }
        }
    }

    // Force borders over the full regular/overtime table regions
    // (Use your template’s intended ranges)
    if err := applyBordersToRange(f, sheetName, "A4", "AJ12", st.ThinBorderStyle); err != nil {
        log.Printf("borders regular: %v", err)
    }
    if err := applyBordersToRange(f, sheetName, "A15", "AJ24", st.ThinBorderStyle); err != nil {
        log.Printf("borders overtime: %v", err)
    }

    log.Printf("=== %s week %d done ===", sheetName, weekNum)
    return nil
}

// getUniqueJobCodesForType: collect keys per overtime flag (prefix night with "N-")
func getUniqueJobCodesForType(entries []Entry, isOvertime bool) []string {
    seen := make(map[string]bool)
    var out []string
    for _, e := range entries {
        if e.Overtime != isOvertime {
            continue
        }
        key := e.JobCode
        if e.IsNightShift {
            key = "N-" + key
        }
        if !seen[key] {
            seen[key] = true
            out = append(out, key)
        }
    }
    return out
}

// timeToExcelDate: convert Go time to Excel serial (1900 date system)
func timeToExcelDate(t time.Time) float64 {
    excelEpoch := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
    return t.Sub(excelEpoch).Hours() / 24.0
}

/* ==========
   Basic file (when template.xlsx missing)
   ========== */

func generateBasicExcelFile(req TimecardRequest) ([]byte, error) {
    f := excelize.NewFile()
    defer func() { _ = f.Close() }()

    const sheet = "Sheet1"

    // Build simple styles so the basic file is readable and shows borders
    st, err := buildStyles(f)
    if err != nil {
        return nil, err
    }

    _ = f.SetCellValue(sheet, "A1", "Employee Name:")
    _ = f.SetCellValue(sheet, "B1", req.EmployeeName)
    _ = f.SetCellValue(sheet, "A2", "Pay Period:")
    _ = f.SetCellValue(sheet, "B2", req.PayPeriodNum)
    _ = f.SetCellValue(sheet, "A3", "Year:")
    _ = f.SetCellValue(sheet, "B3", req.Year)
    _ = f.SetCellValue(sheet, "A4", "Week:")
    _ = f.SetCellValue(sheet, "B4", req.WeekNumberLabel)

    // Headers
    _ = f.SetCellValue(sheet, "A6", "Date")
    _ = f.SetCellValue(sheet, "B6", "Job Code")
    _ = f.SetCellValue(sheet, "C6", "Job Name")
    _ = f.SetCellValue(sheet, "D6", "Hours")
    _ = f.SetCellValue(sheet, "E6", "Overtime")
    _ = f.SetCellStyle(sheet, "A6", "E6", st.HeaderStyle)

    // Column widths
    _ = f.SetColWidth(sheet, "A", "A", 12.0)
    _ = f.SetColWidth(sheet, "B", "E", 14.0)

    // Job lookup
    jobMap := make(map[string]string)
    for _, j := range req.Jobs {
        jobMap[j.JobCode] = j.JobName
    }

    row := 7
    total := 0.0
    totalOT := 0.0

    for _, e := range req.Entries {
        t, err := time.Parse(time.RFC3339, e.Date)
        if err != nil {
            continue
        }
        _ = f.SetCellValue(sheet, fmt.Sprintf("A%d", row), timeToExcelDate(t))
        _ = f.SetCellStyle(sheet, fmt.Sprintf("A%d", row), fmt.Sprintf("A%d", row), st.DateStyle)

        codeOut := e.JobCode
        if e.IsNightShift {
            codeOut = "N" + codeOut
        }
        _ = f.SetCellValue(sheet, fmt.Sprintf("B%d", row), codeOut)
        _ = f.SetCellValue(sheet, fmt.Sprintf("C%d", row), jobMap[e.JobCode])
        _ = f.SetCellValue(sheet, fmt.Sprintf("D%d", row), e.Hours)
        _ = f.SetCellStyle(sheet, fmt.Sprintf("D%d", row), fmt.Sprintf("D%d", row), st.HoursStyle)

        ot := "No"
        if e.Overtime {
            ot = "Yes"
            totalOT += e.Hours
        }
        _ = f.SetCellValue(sheet, fmt.Sprintf("E%d", row), ot)

        total += e.Hours
        row++
    }

    // Totals
    row++
    _ = f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Hours:")
    _ = f.SetCellValue(sheet, fmt.Sprintf("D%d", row), total)
    _ = f.SetCellStyle(sheet, fmt.Sprintf("D%d", row), fmt.Sprintf("D%d", row), st.HoursStyle)
    row++
    _ = f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Overtime:")
    _ = f.SetCellValue(sheet, fmt.Sprintf("D%d", row), totalOT)
    _ = f.SetCellStyle(sheet, fmt.Sprintf("D%d", row), fmt.Sprintf("D%d", row), st.HoursStyle)

    // Apply a border around the data block
    _ = applyBordersToRange(f, sheet, "A6", fmt.Sprintf("E%d", row), st.ThinBorderStyle)

    buf, err := f.WriteToBuffer()
    if err != nil {
        return nil, err
    }
    return buf.Bytes(), nil
}

/* ==========
   Email utils
   ========== */

func sendEmail(to string, cc *string, subject string, body string, attachment []byte, employeeName string) error {
    smtpHost := os.Getenv("SMTP_HOST")
    smtpPort := os.Getenv("SMTP_PORT")
    smtpUser := os.Getenv("SMTP_USER")
    smtpPass := os.Getenv("SMTP_PASS")
    fromEmail := os.Getenv("SMTP_FROM")

    if smtpHost == "" || smtpPort == "" || smtpUser == "" || smtpPass == "" {
        return fmt.Errorf("SMTP not configured")
    }
    if fromEmail == "" {
        fromEmail = smtpUser
    }

    // Recipients
    recipients := splitComma(to)
    ccRecipients := splitComma(ptrVal(cc))
    all := append([]string{}, recipients...)
    all = append(all, ccRecipients...)

    // Attachment file name
    fileName := fmt.Sprintf("timecard_%s_%s.xlsx",
        strings.ReplaceAll(employeeName, " ", "_"),
        time.Now().Format("2006-01-02"))

    msg := buildEmailMessage(fromEmail, recipients, ccRecipients, subject, body, attachment, fileName)
    auth := smtp.PlainAuth("", smtpUser, smtpPass, smtpHost)
    addr := fmt.Sprintf("%s:%s", smtpHost, smtpPort)
    return smtp.SendMail(addr, auth, fromEmail, all, []byte(msg))
}

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
    buf.WriteString(fmt.Sprintf("Content-Type: multipart/mixed; boundary=\"%s\"\r\n\r\n", boundary))

    // Body
    buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
    buf.WriteString("Content-Type: text/plain; charset=\"utf-8\"\r\n\r\n")
    buf.WriteString(body + "\r\n\r\n")

    // Attachment (base64 with 76-char lines)
    if len(attachment) > 0 {
        buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
        buf.WriteString("Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n")
        buf.WriteString(fmt.Sprintf("Content-Disposition: attachment; filename=\"%s\"\r\n", fileName))
        buf.WriteString("Content-Transfer-Encoding: base64\r\n\r\n")
        enc := base64.StdEncoding.EncodeToString(attachment)
        for i := 0; i < len(enc); i += 76 {
            end := i + 76
            if end > len(enc) {
                end = len(enc)
            }
            buf.WriteString(enc[i:end] + "\r\n")
        }
        buf.WriteString("\r\n")
    }

    buf.WriteString(fmt.Sprintf("--%s--\r\n", boundary))
    return buf.String()
}

/* ==========
   Helpers
   ========== */

func splitComma(s string) []string {
    if s == "" {
        return nil
    }
    parts := strings.Split(s, ",")
    for i := range parts {
        parts[i] = strings.TrimSpace(parts[i])
    }
    return parts
}

func ptrVal(s *string) string {
    if s == nil {
        return ""
    }
    return *s
}

func safeFile(name string) string {
    out := strings.TrimSpace(name)
    out = strings.ReplaceAll(out, "/", "-")
    out = strings.ReplaceAll(out, ":", "-")
    return out
}
