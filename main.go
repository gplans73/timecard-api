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
    JobCode string `json:"job_code"` // This is the JOB NUMBER (like "29699", "12215", "92408")
    JobName string `json:"job_name"` // This is the LABOUR CODE (like "201", "223", "H")
}

type Entry struct {
    Date        string  `json:"date"`
    JobCode     string  `json:"job_code"` // This is the JOB NUMBER (like "29699", "12215")
    Hours       float64 `json:"hours"`
    Overtime    bool    `json:"overtime"`
    IsNightShift bool   `json:"is_night_shift"`
}

// UnmarshalJSON accepts both snake_case (Go server) and camelCase (Swift) payloads.
// It also maps `code` -> `job_code` and `isOvertime` -> `overtime`.
func (e *Entry) UnmarshalJSON(data []byte) error {
    // Define an auxiliary type to avoid recursion
    type rawEntry struct {
        Date                string   `json:"date"`
        JobCode             string   `json:"job_code"`
        Code                string   `json:"code"`
        Hours               float64  `json:"hours"`
        Overtime            *bool    `json:"overtime"`
        IsOvertimeCamel     *bool    `json:"isOvertime"`
        NightShift          *bool    `json:"night_shift"`        // ⭐️ Swift sends this
        IsNightShiftSnake   *bool    `json:"is_night_shift"`    // Alternative format
        IsNightShiftCamel   *bool    `json:"isNightShift"`      // Alternative format
    }
    var aux rawEntry
    if err := json.Unmarshal(data, &aux); err != nil {
        return err
    }
    // Required fields
    e.Date = aux.Date
    // Prefer job_code, fall back to code
    if aux.JobCode != "" {
        e.JobCode = aux.JobCode
    } else {
        e.JobCode = aux.Code
    }
    e.Hours = aux.Hours
    // Map overtime flag from either key
    if aux.Overtime != nil {
        e.Overtime = *aux.Overtime
    } else if aux.IsOvertimeCamel != nil {
        e.Overtime = *aux.IsOvertimeCamel
    } else {
        e.Overtime = false
    }
    // Map night shift flag from any of the possible keys
    // ⭐️ Check night_shift first (what Swift actually sends)
    if aux.NightShift != nil {
        e.IsNightShift = *aux.NightShift
    } else if aux.IsNightShiftSnake != nil {
        e.IsNightShift = *aux.IsNightShiftSnake
    } else if aux.IsNightShiftCamel != nil {
        e.IsNightShift = *aux.IsNightShiftCamel
    } else {
        e.IsNightShift = false
    }
    
    // DEBUG: Log the night shift value
    log.Printf("  Unmarshaled entry: JobCode=%s, Hours=%.1f, Overtime=%v, IsNightShift=%v", 
        e.JobCode, e.Hours, e.Overtime, e.IsNightShift)
    
    return nil
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

    http.HandleFunc("/health", healthHandler)
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

    excelData, err := generateExcelFile(req)
    if err != nil {
        log.Printf("Error generating Excel: %v", err)
        http.Error(w, fmt.Sprintf("Error generating timecard: %v", err), http.StatusInternalServerError)
        return
    }

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

    excelData, err := generateExcelFile(req.TimecardRequest)
    if err != nil {
        log.Printf("Error generating Excel: %v", err)
        http.Error(w, fmt.Sprintf("Error generating timecard: %v", err), http.StatusInternalServerError)
        return
    }

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
}

func generateExcelFile(req TimecardRequest) ([]byte, error) {
    templatePath := "template.xlsx"
    f, err := excelize.OpenFile(templatePath)
    if err != nil {
        log.Printf("Template not found: %v", err)
        return generateBasicExcelFile(req)
    }
    defer f.Close()
    
    sheets := f.GetSheetList()
    if len(sheets) == 0 {
        return nil, fmt.Errorf("no sheets found in template")
    }
    
    if len(req.Weeks) > 0 {
        err = fillWeekSheet(f, sheets[0], req, req.Weeks[0], 1)
        if err != nil {
            log.Printf("Error filling Week 1: %v", err)
        }
    }
    
    if len(sheets) > 1 && len(req.Weeks) > 1 {
        err = fillWeekSheet(f, sheets[1], req, req.Weeks[1], 2)
        if err != nil {
            log.Printf("Error filling Week 2: %v", err)
        }
    }
    
    buffer, err := f.WriteToBuffer()
    if err != nil {
        return nil, err
    }
    
    return buffer.Bytes(), nil
}

func fillWeekSheet(f *excelize.File, sheetName string, req TimecardRequest, weekData WeekData, weekNum int) error {
    weekStart, err := time.Parse(time.RFC3339, weekData.WeekStartDate)
    if err != nil {
        return fmt.Errorf("error parsing week start date: %v", err)
    }
    
    log.Printf("=== Filling %s ===", sheetName)
    log.Printf("Week start: %s, Entries: %d", weekStart.Format("2006-01-02"), len(weekData.Entries))
    
    // Set header info
    f.SetCellValue(sheetName, "M2", req.EmployeeName)
    f.SetCellValue(sheetName, "AJ2", req.PayPeriodNum)
    f.SetCellValue(sheetName, "AJ3", req.Year)
    f.SetCellValue(sheetName, "B4", timeToExcelDate(weekStart))
    f.SetCellValue(sheetName, "AJ4", weekData.WeekLabel)
    
    // CODE columns: C, E, G, I, K, M, O, Q, S, U, W, Y, AA, AC, AE, AG (for LABOUR CODES)
    // JOB columns:  D, F, H, J, L, N, P, R, T, V, X, Z, AB, AD, AF, AH (for JOB NUMBERS)
    codeColumns := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
    jobColumns := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}
    
    // Create job lookup map - key by JobCode (which is the JOB NUMBER)
    jobMap := make(map[string]*Job)
    for i := range req.Jobs {
        jobMap[req.Jobs[i].JobCode] = &req.Jobs[i]
        log.Printf("JobMap: number='%s' -> code='%s'", req.Jobs[i].JobCode, req.Jobs[i].JobName)
    }
    
    // Get job numbers for regular and overtime (entries reference by job number)
    regularJobNumbers := getUniqueJobNumbersForType(weekData.Entries, false)
    overtimeJobNumbers := getUniqueJobNumbersForType(weekData.Entries, true)
    
    log.Printf("Regular job numbers: %v", regularJobNumbers)
    log.Printf("Overtime job numbers: %v", overtimeJobNumbers)
    
    // Fill REGULAR TIME headers (Row 4)
    if len(regularJobNumbers) > 0 {
        for i := 0; i < len(regularJobNumbers) && i < len(codeColumns); i++ {
            f.SetCellValue(sheetName, codeColumns[i]+"4", "")
            f.SetCellValue(sheetName, jobColumns[i]+"4", "")
        }
        
        for i, jobNumberKey := range regularJobNumbers {
            if i >= len(codeColumns) {
                break
            }
            
            // jobNumberKey might have "N" prefix (e.g., "N92408")
            // Remove "N" to look up the actual job
            actualJobNumber := jobNumberKey
            hasNightPrefix := strings.HasPrefix(jobNumberKey, "N")
            if hasNightPrefix {
                actualJobNumber = jobNumberKey[1:]
            }
            
            job := jobMap[actualJobNumber]
            if job != nil {
                // Get the labour code
                labourCode := job.JobName
                // Add "N" prefix if this is a night shift
                if hasNightPrefix {
                    labourCode = "N" + labourCode
                }
                
                // CORRECT MAPPING:
                // C4, E4, G4... = LABOUR CODE (with "N" prefix if night)
                // D4, F4, H4... = JOB NUMBER (without "N" prefix)
                f.SetCellValue(sheetName, codeColumns[i]+"4", labourCode)      // "201", "N223", "H"
                f.SetCellValue(sheetName, jobColumns[i]+"4", actualJobNumber)   // "29699", "12215", "92408"
                log.Printf("  Row 4: %s='%s' (code), %s='%s' (number)", codeColumns[i], labourCode, jobColumns[i], actualJobNumber)
            } else {
                log.Printf("  WARNING: No job found for number '%s'", actualJobNumber)
            }
        }
    }
    
    // Fill OVERTIME headers (Row 15)
    if len(overtimeJobNumbers) > 0 {
        for i := 0; i < len(overtimeJobNumbers) && i < len(codeColumns); i++ {
            f.SetCellValue(sheetName, codeColumns[i]+"15", "")
            f.SetCellValue(sheetName, jobColumns[i]+"15", "")
        }
        
        for i, jobNumberKey := range overtimeJobNumbers {
            if i >= len(codeColumns) {
                break
            }
            
            actualJobNumber := jobNumberKey
            hasNightPrefix := strings.HasPrefix(jobNumberKey, "N")
            if hasNightPrefix {
                actualJobNumber = jobNumberKey[1:]
            }
            
            job := jobMap[actualJobNumber]
            if job != nil {
                labourCode := job.JobName
                if hasNightPrefix {
                    labourCode = "N" + labourCode
                }
                
                // CORRECT MAPPING:
                // C15, E15, G15... = LABOUR CODE (with "N" prefix if night)
                // D15, F15, H15... = JOB NUMBER (without "N" prefix)
                f.SetCellValue(sheetName, codeColumns[i]+"15", labourCode)      // "201", "OC"
                f.SetCellValue(sheetName, jobColumns[i]+"15", actualJobNumber)   // "92309"
                log.Printf("  Row 15: %s='%s' (code), %s='%s' (number)", codeColumns[i], labourCode, jobColumns[i], actualJobNumber)
            }
        }
    }
    
    // Organize entries by date and job number (with "N" prefix for night shifts)
    regularTimeEntries := make(map[string]map[string]float64)
    overtimeEntries := make(map[string]map[string]float64)
    
    for _, entry := range weekData.Entries {
        entryDate, err := time.Parse(time.RFC3339, entry.Date)
        if err != nil {
            log.Printf("Error parsing entry date '%s': %v", entry.Date, err)
            continue
        }
        
        dateKey := entryDate.Format("2006-01-02")
        // Use job number as the key, with "N" prefix if night shift
        jobNumberKey := entry.JobCode
        
        // DETAILED LOGGING for every entry
        log.Printf("  Processing entry: date=%s, jobCode=%s, hours=%.1f, overtime=%v, isNightShift=%v",
            dateKey, entry.JobCode, entry.Hours, entry.Overtime, entry.IsNightShift)
        
        if entry.IsNightShift {
            jobNumberKey = "N" + entry.JobCode
            log.Printf("    → NIGHT SHIFT DETECTED! Converting %s to %s", entry.JobCode, jobNumberKey)
        }
        
        if entry.Overtime {
            if overtimeEntries[dateKey] == nil {
                overtimeEntries[dateKey] = make(map[string]float64)
            }
            overtimeEntries[dateKey][jobNumberKey] += entry.Hours
        } else {
            if regularTimeEntries[dateKey] == nil {
                regularTimeEntries[dateKey] = make(map[string]float64)
            }
            regularTimeEntries[dateKey][jobNumberKey] += entry.Hours
        }
    }
    
    // Fill daily hours
    for dayOffset := 0; dayOffset < 7; dayOffset++ {
        currentDate := weekStart.AddDate(0, 0, dayOffset)
        dateKey := currentDate.Format("2006-01-02")
        dateSerial := timeToExcelDate(currentDate)
        
        regularRow := 5 + dayOffset
        overtimeRow := 16 + dayOffset
        
        f.SetCellValue(sheetName, fmt.Sprintf("B%d", regularRow), dateSerial)
        f.SetCellValue(sheetName, fmt.Sprintf("B%d", overtimeRow), dateSerial)
        
        // Regular hours - write to CODE columns (C, E, G...)
        if regHours, exists := regularTimeEntries[dateKey]; exists {
            for i, jobNumberKey := range regularJobNumbers {
                if i >= len(codeColumns) {
                    break
                }
                if hours, hasHours := regHours[jobNumberKey]; hasHours && hours > 0 {
                    cellRef := fmt.Sprintf("%s%d", codeColumns[i], regularRow)
                    f.SetCellValue(sheetName, cellRef, hours)
                    log.Printf("    Regular hours: %s = %.1f (job %s)", cellRef, hours, jobNumberKey)
                }
            }
        }
        
        // Overtime hours - write to CODE columns (C, E, G...)
        if otHours, exists := overtimeEntries[dateKey]; exists {
            for i, jobNumberKey := range overtimeJobNumbers {
                if i >= len(codeColumns) {
                    break
                }
                if hours, hasHours := otHours[jobNumberKey]; hasHours && hours > 0 {
                    cellRef := fmt.Sprintf("%s%d", codeColumns[i], overtimeRow)
                    f.SetCellValue(sheetName, cellRef, hours)
                    log.Printf("    Overtime hours: %s = %.1f (job %s)", cellRef, hours, jobNumberKey)
                }
            }
        }
    }
    
    log.Printf("=== Week %d completed ===", weekNum)
    return nil
}

func getUniqueJobNumbersForType(entries []Entry, isOvertime bool) []string {
    seen := make(map[string]bool)
    var result []string
    
    for _, entry := range entries {
        if entry.Overtime != isOvertime {
            continue
        }
        
        // Use job number as key, with "N" prefix for night shifts
        jobNumberKey := entry.JobCode
        if entry.IsNightShift {
            jobNumberKey = "N" + entry.JobCode
        }
        
        if !seen[jobNumberKey] {
            seen[jobNumberKey] = true
            result = append(result, jobNumberKey)
        }
    }
    
    return result
}

func timeToExcelDate(t time.Time) float64 {
    excelEpoch := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
    return t.Sub(excelEpoch).Hours() / 24.0
}

func generateBasicExcelFile(req TimecardRequest) ([]byte, error) {
    f := excelize.NewFile()
    defer f.Close()
    
    sheet := "Sheet1"
    f.SetCellValue(sheet, "A1", "Employee:")
    f.SetCellValue(sheet, "B1", req.EmployeeName)
    
    buffer, _ := f.WriteToBuffer()
    return buffer.Bytes(), nil
}

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

    allRecipients := append([]string{}, recipients...)
    allRecipients = append(allRecipients, ccRecipients...)

    fileName := fmt.Sprintf("timecard_%s_%s.xlsx",
        strings.ReplaceAll(employeeName, " ", "_"),
        time.Now().Format("2006-01-02"))

    message := buildEmailMessage(fromEmail, recipients, ccRecipients, subject, body, attachment, fileName)
    auth := smtp.PlainAuth("", smtpUser, smtpPass, smtpHost)
    addr := fmt.Sprintf("%s:%s", smtpHost, smtpPort)

    return smtp.SendMail(addr, auth, fromEmail, allRecipients, []byte(message))
}

func buildEmailMessage(from string, to []string, cc []string, subject string, body string, attachment []byte, fileName string) string {
    boundary := "==BOUNDARY=="
    var buf bytes.Buffer
    
    buf.WriteString(fmt.Sprintf("From: %s\r\n", from))
    buf.WriteString(fmt.Sprintf("To: %s\r\n", strings.Join(to, ", ")))
    if len(cc) > 0 {
        buf.WriteString(fmt.Sprintf("Cc: %s\r\n", strings.Join(cc, ", ")))
    }
    buf.WriteString(fmt.Sprintf("Subject: %s\r\n", subject))
    buf.WriteString("MIME-Version: 1.0\r\n")
    buf.WriteString(fmt.Sprintf("Content-Type: multipart/mixed; boundary=\"%s\"\r\n\r\n", boundary))
    
    buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
    buf.WriteString("Content-Type: text/plain; charset=\"utf-8\"\r\n\r\n")
    buf.WriteString(body)
    buf.WriteString("\r\n\r\n")
    
    if len(attachment) > 0 {
        buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
        buf.WriteString("Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n")
        buf.WriteString(fmt.Sprintf("Content-Disposition: attachment; filename=\"%s\"\r\n", fileName))
        buf.WriteString("Content-Transfer-Encoding: base64\r\n\r\n")
        
        encoded := base64.StdEncoding.EncodeToString(attachment)
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
    
    buf.WriteString(fmt.Sprintf("--%s--\r\n", boundary))
    return buf.String()
}
