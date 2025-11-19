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

func main() {
    // Check for template file on startup
    if _, err := os.Stat("template.xlsx"); err != nil {
        log.Fatal("❌ template.xlsx not found! Make sure it's in the same directory as the executable.")
    }
    log.Println("✅ template.xlsx found")

    // Test LibreOffice on startup
    log.Println("🔍 Checking LibreOffice installation...")
    cmd := exec.Command("libreoffice", "--version")
    output, err := cmd.CombinedOutput()
    if err != nil {
        log.Printf("⚠️ LibreOffice check failed: %v, output: %s", err, string(output))
        log.Println("⚠️ PDF generation will be disabled")
    } else {
        log.Printf("✅ LibreOffice available: %s", strings.TrimSpace(string(output)))
    }

    // Health check endpoint
    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        w.Write([]byte("OK"))
    })

    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(map[string]interface{}{
            "status":  "ok",
            "message": "Timecard API is running",
            "version": "2.3.0",
            "endpoints": []string{
                "/api/generate-timecard",
                "/api/email-timecard",
                "/test/libreoffice",
                "/health",
            },
        })
    })

    http.HandleFunc("/api/generate-timecard", generateTimecardHandler)
    http.HandleFunc("/api/email-timecard", emailTimecardHandler)
    http.HandleFunc("/test/libreoffice", testLibreOfficeHandler)

    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    log.Printf("🚀 Server starting on port %s", port)
    if err := http.ListenAndServe(":"+port, nil); err != nil {
        log.Fatalf("❌ Server failed: %v", err)
    }
}

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
    Date     string  `json:"date"`
    JobCode  string  `json:"job_code"`
    Hours    float64 `json:"hours"`
    Overtime bool    `json:"overtime"`
}

type WeekData struct {
    WeekNumber    int     `json:"week_number"`
    WeekStartDate string  `json:"week_start_date"`
    WeekLabel     string  `json:"week_label"`
    Entries       []Entry `json:"entries"`
}

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

    // Save Excel file
    excelFilename := fmt.Sprintf("Timecard_%s_%d(%d).xlsx", req.EmployeeName, req.Year, req.PayPeriodNum)
    excelPath := filepath.Join(tempDir, excelFilename)

    if err := file.SaveAs(excelPath); err != nil {
        log.Printf("❌ Failed to save Excel: %v", err)
        respondError(w, err)
        return
    }

    log.Printf("✅ Excel file created: %s", excelPath)

    // Generate PDF if requested
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

    // If PDF was generated, return ZIP with both files
    if pdfPath != "" && fileExists(pdfPath) {
        log.Printf("📦 Creating ZIP archive with Excel and PDF")
        zipBuffer := new(bytes.Buffer)
        zipWriter := zip.NewWriter(zipBuffer)

        if err := addFileToZip(zipWriter, excelPath, excelFilename); err != nil {
            log.Printf("❌ Failed to add Excel to ZIP: %v", err)
            respondError(w, err)
            return
        }

        pdfFilename := filepath.Base(pdfPath)
        if err := addFileToZip(zipWriter, pdfPath, pdfFilename); err != nil {
            log.Printf("❌ Failed to add PDF to ZIP: %v", err)
            respondError(w, err)
            return
        }

        zipWriter.Close()

        w.Header().Set("Content-Type", "application/zip")
        w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"timecard_%s_%d(%d).zip\"", req.EmployeeName, req.Year, req.PayPeriodNum))
        w.Write(zipBuffer.Bytes())
        log.Printf("✅ Sent ZIP file: %d bytes", zipBuffer.Len())
    } else {
        // Return just Excel
        excelData, err := os.ReadFile(excelPath)
        if err != nil {
            log.Printf("❌ Failed to read Excel: %v", err)
            respondError(w, err)
            return
        }

        w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", excelFilename))
        w.Write(excelData)
        log.Printf("✅ Sent Excel file: %d bytes", len(excelData))
    }
}

func emailTimecardHandler(w http.ResponseWriter, r *http.Request) {
    log.Printf("📥 Received email request to %s", r.URL.Path)

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

    // Check SendGrid API key
    sendgridAPIKey := os.Getenv("SMTP_PASS") // We use SMTP_PASS as the SendGrid API key
    smtpFrom := os.Getenv("SMTP_FROM")

    if sendgridAPIKey == "" || smtpFrom == "" {
        log.Printf("⚠️ SendGrid not configured")
        w.WriteHeader(http.StatusServiceUnavailable)
        json.NewEncoder(w).Encode(map[string]string{
            "status":  "error",
            "message": "SMTP not configured on server",
        })
        return
    }

    log.Printf("📧 Sending email from %s to %s via SendGrid HTTP API", smtpFrom, req.To)

    // Generate Excel file from template
    file, err := createXLSXFile(req.TimecardRequest)
    if err != nil {
        respondError(w, err)
        return
    }
    defer file.Close()

    // Create temp directory
    tempDir, err := os.MkdirTemp("", "timecard-*")
    if err != nil {
        respondError(w, err)
        return
    }
    defer os.RemoveAll(tempDir)

    // Save Excel
    excelFilename := fmt.Sprintf("Timecard_%s_%d(%d).xlsx", req.EmployeeName, req.Year, req.PayPeriodNum)
    excelPath := filepath.Join(tempDir, excelFilename)
    if err := file.SaveAs(excelPath); err != nil {
        respondError(w, err)
        return
    }

    log.Printf("✅ Excel file created for email: %s", excelPath)

    // Generate PDF if requested
    var pdfPath string
    if req.IncludePDF {
        pdfFilename := fmt.Sprintf("Timecard_%s_%d(%d).pdf", req.EmployeeName, req.Year, req.PayPeriodNum)
        pdfPath = filepath.Join(tempDir, pdfFilename)

        log.Printf("🔄 Converting Excel to PDF for email...")
        if err := convertExcelToPDF(excelPath, pdfPath); err != nil {
            log.Printf("⚠️ PDF generation failed: %v", err)
            pdfPath = ""
        } else {
            log.Printf("✅ PDF file created for email: %s", pdfPath)
        }
    }

    // Send email via SendGrid HTTP API
    if err := sendEmailViaSendGrid(sendgridAPIKey, smtpFrom, req.To, req.CC, req.Subject, req.Body, excelPath, pdfPath); err != nil {
        log.Printf("❌ Failed to send email: %v", err)
        respondError(w, err)
        return
    }

    log.Printf("✅ Email sent successfully to %s", req.To)
    w.WriteHeader(http.StatusOK)
    json.NewEncoder(w).Encode(map[string]string{
        "status":  "success",
        "message": "Email sent successfully",
    })
}

func testLibreOfficeHandler(w http.ResponseWriter, r *http.Request) {
    log.Printf("🔍 Testing LibreOffice installation")
    cmd := exec.Command("libreoffice", "--version")
    output, err := cmd.CombinedOutput()
    if err != nil {
        log.Printf("❌ LibreOffice test failed: %v", err)
        w.WriteHeader(http.StatusInternalServerError)
        w.Write([]byte(fmt.Sprintf("❌ Error: %v\nOutput: %s", err, string(output))))
        return
    }
    log.Printf("✅ LibreOffice test passed")
    w.Write([]byte(fmt.Sprintf("✅ LibreOffice installed:\n%s", string(output))))
}

func convertExcelToPDF(excelPath, pdfPath string) error {
    outputDir := filepath.Dir(pdfPath)

    cmd := exec.Command("libreoffice",
        "--headless",
        "--convert-to", "pdf",
        "--outdir", outputDir,
        excelPath)

    log.Printf("🔧 Running: %s", cmd.String())
    output, err := cmd.CombinedOutput()
    if err != nil {
        return fmt.Errorf("LibreOffice conversion failed: %v, output: %s", err, string(output))
    }

    log.Printf("✅ LibreOffice output: %s", string(output))

    baseName := strings.TrimSuffix(filepath.Base(excelPath), filepath.Ext(excelPath))
    generatedPDF := filepath.Join(outputDir, baseName+".pdf")

    if generatedPDF != pdfPath {
        if err := os.Rename(generatedPDF, pdfPath); err != nil {
            return fmt.Errorf("failed to rename PDF: %v", err)
        }
    }

    return nil
}

func addFileToZip(zipWriter *zip.Writer, filePath, fileName string) error {
    fileData, err := os.ReadFile(filePath)
    if err != nil {
        return err
    }

    writer, err := zipWriter.Create(fileName)
    if err != nil {
        return err
    }

    _, err = writer.Write(fileData)
    return err
}

func fileExists(path string) bool {
    _, err := os.Stat(path)
    return err == nil
}

func respondError(w http.ResponseWriter, err error) {
    log.Printf("❌ Error: %v", err)
    w.WriteHeader(http.StatusInternalServerError)
    json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
}

func sendEmailViaSendGrid(apiKey, from, to, cc, subject, body, excelPath, pdfPath string) error {
    log.Printf("📧 Using SendGrid HTTP API")

    // Read attachments
    excelData, err := os.ReadFile(excelPath)
    if err != nil {
        return fmt.Errorf("failed to read Excel file: %v", err)
    }

    var pdfData []byte
    if pdfPath != "" && fileExists(pdfPath) {
        pdfData, _ = os.ReadFile(pdfPath)
    }

    // Build SendGrid API request
    type Attachment struct {
        Content     string `json:"content"`
        Type        string `json:"type"`
        Filename    string `json:"filename"`
        Disposition string `json:"disposition"`
    }

    type Email struct {
        Email string `json:"email"`
    }

    type Personalization struct {
        To []Email `json:"to"`
        Cc []Email `json:"cc,omitempty"`
    }

    type Content struct {
        Type  string `json:"type"`
        Value string `json:"value"`
    }

    type SendGridRequest struct {
        Personalizations []Personalization `json:"personalizations"`
        From             Email             `json:"from"`
        Subject          string            `json:"subject"`
        Content          []Content         `json:"content"`
        Attachments      []Attachment      `json:"attachments"`
    }

    // Build request
    req := SendGridRequest{
        Personalizations: []Personalization{
            {
                To: []Email{{Email: to}},
            },
        },
        From:    Email{Email: from},
        Subject: subject,
        Content: []Content{
            {
                Type:  "text/plain",
                Value: body,
            },
        },
        Attachments: []Attachment{
            {
                Content:     base64.StdEncoding.EncodeToString(excelData),
                Type:        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                Filename:    filepath.Base(excelPath),
                Disposition: "attachment",
            },
        },
    }

    // Add CC if provided
    if cc != "" {
        ccAddresses := strings.Split(cc, ",")
        for _, addr := range ccAddresses {
            req.Personalizations[0].Cc = append(req.Personalizations[0].Cc, Email{Email: strings.TrimSpace(addr)})
        }
    }

    // Add PDF if exists
    if len(pdfData) > 0 {
        req.Attachments = append(req.Attachments, Attachment{
            Content:     base64.StdEncoding.EncodeToString(pdfData),
            Type:        "application/pdf",
            Filename:    filepath.Base(pdfPath),
            Disposition: "attachment",
        })
    }

    // Encode JSON
    jsonData, err := json.Marshal(req)
    if err != nil {
        return fmt.Errorf("failed to encode JSON: %v", err)
    }

    // Send HTTP request to SendGrid
    httpReq, err := http.NewRequest("POST", "https://api.sendgrid.com/v3/mail/send", bytes.NewBuffer(jsonData))
    if err != nil {
        return fmt.Errorf("failed to create request: %v", err)
    }

    httpReq.Header.Set("Authorization", "Bearer "+apiKey)
    httpReq.Header.Set("Content-Type", "application/json")

    client := &http.Client{Timeout: 30 * time.Second}
    resp, err := client.Do(httpReq)
    if err != nil {
        return fmt.Errorf("HTTP request failed: %v", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode != 202 {
        bodyBytes, _ := io.ReadAll(resp.Body)
        return fmt.Errorf("SendGrid API error: %d - %s", resp.StatusCode, string(bodyBytes))
    }

    log.Printf("✅ Email sent via SendGrid HTTP API (status: %d)", resp.StatusCode)
    return nil
}

// createXLSXFile loads the template and populates it with timecard data
func createXLSXFile(req TimecardRequest) (*excelize.File, error) {
    log.Printf("📂 Loading template.xlsx...")

    // Load the template file (THIS IS THE KEY CHANGE!)
    file, err := excelize.OpenFile("template.xlsx")
    if err != nil {
        return nil, fmt.Errorf("failed to load template: %v", err)
    }

    log.Printf("✅ Template loaded successfully")
    
    // DEBUG: Log template structure
    sheetName := file.GetSheetName(0)
    log.Printf("🔍 Template sheet name: %s", sheetName)
    
    // Log some sample cells to understand the template structure
    sampleCells := []string{"A1", "B1", "C1", "D1", "E1", "A2", "B2", "C2", "D2", "E2", "A3", "B3", "C3", "D3", "E3"}
    for _, cell := range sampleCells {
        value, _ := file.GetCellValue(sheetName, cell)
        if value != "" {
            log.Printf("🔍 Cell %s = '%s'", cell, value)
        }
    }

    // Check if multi-week data is provided
    if req.Weeks != nil && len(req.Weeks) > 0 {
        log.Printf("📊 Processing multi-week timecard (%d weeks)", len(req.Weeks))

        // Rename original template to preserve it for copying
        originalTemplateName := file.GetSheetName(0)
        file.SetSheetName(originalTemplateName, "TEMPLATE_PRISTINE")
        
        // Process each week
        for i, weekData := range req.Weeks {
            // Copy from index 0 (the pristine template)
            newSheetIndex, err := file.CopySheet(0)
            if err != nil {
                return nil, fmt.Errorf("failed to copy template sheet for week %d: %v", i+1, err)
            }
            
            // Get the name of the newly copied sheet
            copiedSheetName := file.GetSheetName(newSheetIndex)
            
            // Rename it to the week label
            if err := file.SetSheetName(copiedSheetName, weekData.WeekLabel); err != nil {
                return nil, fmt.Errorf("failed to rename sheet to %s: %v", weekData.WeekLabel, err)
            }
            
            currentSheetName := weekData.WeekLabel
            log.Printf("📝 Created sheet: %s (index %d)", currentSheetName, newSheetIndex)
            
            // Populate this week's data
            if err := populateTimecardSheet(file, currentSheetName, req, weekData.Entries, weekData.WeekLabel, weekData.WeekNumber); err != nil {
                return nil, fmt.Errorf("failed to populate sheet %s: %v", currentSheetName, err)
            }
        }
        
        // Delete the pristine template sheet
        if err := file.DeleteSheet("TEMPLATE_PRISTINE"); err != nil {
            log.Printf("⚠️ Failed to delete pristine template: %v", err)
        }

        // Set the first week as active
        file.SetActiveSheet(0)
    } else {
        // Single week: use the template's existing sheet
        log.Printf("📊 Processing single-week timecard")
        templateSheetName := file.GetSheetName(0)

        if req.WeekNumberLabel != "" {
            file.SetSheetName(templateSheetName, req.WeekNumberLabel)
        }

        if err := populateTimecardSheet(file, file.GetSheetName(0), req, req.Entries, req.WeekNumberLabel, 1); err != nil {
            return nil, fmt.Errorf("failed to populate sheet: %v", err)
        }
    }

    log.Printf("✅ Excel file populated with data")
    return file, nil
}

// populateTimecardSheet fills in a single sheet with timecard data
func populateTimecardSheet(file *excelize.File, sheetName string, req TimecardRequest, entries []Entry, weekLabel string, weekNumber int) error {
    log.Printf("✍️ Populating sheet: %s with %d entries", sheetName, len(entries))

    // Set employee name (cell M2)
    file.SetCellValue(sheetName, "M2", req.EmployeeName)

    // Set pay period and year (cells AJ2 and AJ3)
    file.SetCellValue(sheetName, "AJ2", req.PayPeriodNum)
    file.SetCellValue(sheetName, "AJ3", req.Year)

    // Set week label (cell AJ4)
    file.SetCellValue(sheetName, "AJ4", weekLabel)

    // Parse week start date and set it (cell B4)
    weekStart, err := time.Parse(time.RFC3339, req.WeekStartDate)
    if err != nil {
        log.Printf("⚠️ Failed to parse week start date: %v", err)
        weekStart = time.Now()
    }
    // Excel date serial format (days since 1900-01-01, with adjustment for Excel's leap year bug)
    excelEpoch := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
    daysSinceEpoch := weekStart.Sub(excelEpoch).Hours() / 24
    file.SetCellValue(sheetName, "B4", daysSinceEpoch)

    // Job columns - up to 16 jobs can be displayed
    // Code columns: C, E, G, I, K, M, O, Q, S, U, W, Y, AA, AC, AE, AG
    // Job name columns: D, F, H, J, L, N, P, R, T, V, X, Z, AB, AD, AF, AH
    // Hours columns (same as job name columns): D, F, H, J, L, N, P, R, T, V, X, Z, AB, AD, AF, AH
    jobCodeColumns := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
    jobNameColumns := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}
    
    // Set job headers (Row 4)
    jobColumnMap := make(map[string]string) // Maps job code to its data column
    for i, job := range req.Jobs {
        if i >= len(jobCodeColumns) {
            log.Printf("⚠️ Too many jobs (%d), template only supports %d jobs", len(req.Jobs), len(jobCodeColumns))
            break
        }
        
        // Set job code in code column (row 4)
        file.SetCellValue(sheetName, jobCodeColumns[i]+"4", job.JobCode)
        
        // Set job name in job column (row 4)
        file.SetCellValue(sheetName, jobNameColumns[i]+"4", job.JobName)
        
        // Map job code to its data column for later use
        jobColumnMap[job.JobCode] = jobNameColumns[i]
        
        log.Printf("📋 Set job %d: Code=%s in %s4, Name=%s in %s4", i+1, job.JobCode, jobCodeColumns[i], job.JobName, jobNameColumns[i])
    }

    // Group entries by date and job
    type EntryKey struct {
        Date    string
        JobCode string
    }
    entryMap := make(map[EntryKey]Entry)
    for _, entry := range entries {
        key := EntryKey{Date: entry.Date, JobCode: entry.JobCode}
        entryMap[key] = entry
    }

    // Fill in hours for each entry
    for _, entry := range entryMap {
        // Parse the entry date
        entryDate, err := time.Parse(time.RFC3339, entry.Date)
        if err != nil {
            log.Printf("⚠️ Failed to parse entry date %s: %v", entry.Date, err)
            continue
        }

        // Find the column for this job
        jobCol, exists := jobColumnMap[entry.JobCode]
        if !exists {
            log.Printf("⚠️ Job code %s not found in job column map", entry.JobCode)
            continue
        }

        // Calculate day of week offset from week start (0=Sunday, 6=Saturday)
        dayOffset := int(entryDate.Sub(weekStart).Hours() / 24)
        if dayOffset < 0 || dayOffset > 6 {
            log.Printf("⚠️ Entry date %s is outside week range (offset=%d)", entry.Date, dayOffset)
            continue
        }

        // Determine row based on whether it's overtime and day of week
        var row int
        if entry.Overtime {
            // Overtime section: rows 16-22 (Sun-Sat)
            row = 16 + dayOffset
        } else {
            // Regular time section: rows 5-11 (Sun-Sat)
            row = 5 + dayOffset
        }

        // Set the hours in the appropriate cell
        cellRef := jobCol + strconv.Itoa(row)
        file.SetCellValue(sheetName, cellRef, entry.Hours)
        log.Printf("✏️ Set %s = %.2f hours (Job: %s, Date: %s, OT: %v)",
            cellRef, entry.Hours, entry.JobCode, entryDate.Format("Mon Jan 2"), entry.Overtime)
    }

    // Set date cells for each day (B5-B11 for regular, B16-B22 for overtime)
    // These should already be in the template, but we can ensure they're correct
    for i := 0; i < 7; i++ {
        dayDate := weekStart.AddDate(0, 0, i)
        daySerial := dayDate.Sub(excelEpoch).Hours() / 24
        
        // Regular time date column
        file.SetCellValue(sheetName, "B"+strconv.Itoa(5+i), daySerial)
        
        // Overtime date column
        file.SetCellValue(sheetName, "B"+strconv.Itoa(16+i), daySerial)
    }

    log.Printf("✅ Sheet %s populated successfully", sheetName)
    return nil
}

