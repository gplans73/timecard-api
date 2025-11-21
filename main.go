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
    "net/smtp"
    "net/url"
    "os"
    "os/exec"
    "path/filepath"
    "strconv"
    "strings"
    "sync"
    "time"

    "github.com/xuri/excelize/v2"
)

// ====== Microsoft Graph API Types ======

type GraphAuthResponse struct {
    TokenType    string `json:"token_type"`
    ExpiresIn    int    `json:"expires_in"`
    AccessToken  string `json:"access_token"`
}

type GraphConfig struct {
    TenantID     string
    ClientID     string
    ClientSecret string
    UserID       string
    mu           sync.RWMutex
    token        string
    tokenExpiry  time.Time
}

var graphClient *GraphConfig

// ====== Data Types ======

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
    JobType     string  `json:"job_type"`
    TusCode     string  `json:"tus_code"`
    Description string  `json:"description"`
}

type WeekData struct {
    WeekStartDate string  `json:"week_start_date"`
    WeekLabel     string  `json:"week_label"`
    Entries       []Entry `json:"entries"`
}

// ====== Helpers ======

// Initialize Microsoft Graph Client
func initGraphClient() {
    tenantID := os.Getenv("MICROSOFT_TENANT_ID")
    clientID := os.Getenv("MICROSOFT_CLIENT_ID")
    clientSecret := os.Getenv("MICROSOFT_CLIENT_SECRET")
    userID := os.Getenv("MICROSOFT_USER_ID")

    if tenantID != "" && clientID != "" && clientSecret != "" && userID != "" {
        graphClient = &GraphConfig{
            TenantID:     tenantID,
            ClientID:     clientID,
            ClientSecret: clientSecret,
            UserID:       userID,
        }
        log.Printf("✅ Microsoft Graph API configured (User: %s)", userID)
    } else {
        log.Printf("ℹ️  Microsoft Graph API not configured (will use LibreOffice)")
    }
}

// Get or refresh Microsoft Graph access token
func (gc *GraphConfig) getAccessToken() (string, error) {
    gc.mu.RLock()
    if gc.token != "" && time.Now().Before(gc.tokenExpiry) {
        token := gc.token
        gc.mu.RUnlock()
        return token, nil
    }
    gc.mu.RUnlock()

    gc.mu.Lock()
    defer gc.mu.Unlock()

    // Double-check after acquiring write lock
    if gc.token != "" && time.Now().Before(gc.tokenExpiry) {
        return gc.token, nil
    }

    tokenURL := fmt.Sprintf("https://login.microsoftonline.com/%s/oauth2/v2.0/token", gc.TenantID)

    data := url.Values{}
    data.Set("client_id", gc.ClientID)
    data.Set("client_secret", gc.ClientSecret)
    data.Set("scope", "https://graph.microsoft.com/.default")
    data.Set("grant_type", "client_credentials")

    req, err := http.NewRequest("POST", tokenURL, strings.NewReader(data.Encode()))
    if err != nil {
        return "", fmt.Errorf("failed to create token request: %w", err)
    }

    req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

    client := &http.Client{Timeout: 30 * time.Second}
    resp, err := client.Do(req)
    if err != nil {
        return "", fmt.Errorf("failed to get token: %w", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        body, _ := io.ReadAll(resp.Body)
        return "", fmt.Errorf("token request failed with status %d: %s", resp.StatusCode, string(body))
    }

    var authResp GraphAuthResponse
    if err := json.NewDecoder(resp.Body).Decode(&authResp); err != nil {
        return "", fmt.Errorf("failed to decode token response: %w", err)
    }

    gc.token = authResp.AccessToken
    gc.tokenExpiry = time.Now().Add(time.Duration(authResp.ExpiresIn-300) * time.Second) // 5 min buffer

    log.Printf("✅ Microsoft Graph token acquired (expires in %d seconds)", authResp.ExpiresIn)
    return gc.token, nil
}

// Convert Excel to PDF using Microsoft Graph API
func (gc *GraphConfig) convertExcelToPDFGraph(excelPath, pdfPath string) error {
    log.Printf("🔄 Converting Excel to PDF using Microsoft Graph API...")

    token, err := gc.getAccessToken()
    if err != nil {
        return fmt.Errorf("failed to get access token: %w", err)
    }

    // Read Excel file
    excelData, err := os.ReadFile(excelPath)
    if err != nil {
        return fmt.Errorf("failed to read Excel file: %w", err)
    }

    // Step 1: Upload to OneDrive
    uploadURL := fmt.Sprintf("https://graph.microsoft.com/v1.0/users/%s/drive/root:/temp-timecard-%d.xlsx:/content",
        gc.UserID, time.Now().UnixNano())

    uploadReq, err := http.NewRequest("PUT", uploadURL, bytes.NewReader(excelData))
    if err != nil {
        return fmt.Errorf("failed to create upload request: %w", err)
    }

    uploadReq.Header.Set("Authorization", "Bearer "+token)
    uploadReq.Header.Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    client := &http.Client{Timeout: 60 * time.Second}
    uploadResp, err := client.Do(uploadReq)
    if err != nil {
        return fmt.Errorf("failed to upload file: %w", err)
    }
    defer uploadResp.Body.Close()

    if uploadResp.StatusCode != http.StatusOK && uploadResp.StatusCode != http.StatusCreated {
        body, _ := io.ReadAll(uploadResp.Body)
        
        // Provide helpful error message for common issues
        if uploadResp.StatusCode == 503 {
            return fmt.Errorf("OneDrive service unavailable (HTTP 503). This usually means OneDrive is not provisioned for user %s. Please have the user log in to https://onedrive.live.com once to enable OneDrive", gc.UserID)
        }
        
        return fmt.Errorf("file upload failed with status %d: %s", uploadResp.StatusCode, string(body))
    }

    var uploadResult struct {
        ID   string `json:"id"`
        Name string `json:"name"`
    }
    if err := json.NewDecoder(uploadResp.Body).Decode(&uploadResult); err != nil {
        return fmt.Errorf("failed to decode upload response: %w", err)
    }

    log.Printf("✅ File uploaded to OneDrive (ID: %s)", uploadResult.ID)

    // Step 2: Convert to PDF
    convertURL := fmt.Sprintf("https://graph.microsoft.com/v1.0/users/%s/drive/items/%s/content?format=pdf",
        gc.UserID, uploadResult.ID)

    // Wait a moment for the file to be processed
    time.Sleep(2 * time.Second)

    convertReq, err := http.NewRequest("GET", convertURL, nil)
    if err != nil {
        return fmt.Errorf("failed to create convert request: %w", err)
    }

    convertReq.Header.Set("Authorization", "Bearer "+token)

    convertResp, err := client.Do(convertReq)
    if err != nil {
        return fmt.Errorf("failed to convert file: %w", err)
    }
    defer convertResp.Body.Close()

    if convertResp.StatusCode != http.StatusOK {
        body, _ := io.ReadAll(convertResp.Body)
        return fmt.Errorf("PDF conversion failed with status %d: %s", convertResp.StatusCode, string(body))
    }

    // Save PDF
    pdfData, err := io.ReadAll(convertResp.Body)
    if err != nil {
        return fmt.Errorf("failed to read PDF data: %w", err)
    }

    if err := os.WriteFile(pdfPath, pdfData, 0644); err != nil {
        return fmt.Errorf("failed to write PDF file: %w", err)
    }

    log.Printf("✅ PDF generated using Microsoft Graph API: %s", pdfPath)

    // Step 3: Clean up - delete the temporary file from OneDrive
    deleteURL := fmt.Sprintf("https://graph.microsoft.com/v1.0/users/%s/drive/items/%s",
        gc.UserID, uploadResult.ID)

    deleteReq, err := http.NewRequest("DELETE", deleteURL, nil)
    if err != nil {
        log.Printf("⚠️  Failed to create delete request: %v", err)
        return nil // Don't fail the whole operation
    }

    deleteReq.Header.Set("Authorization", "Bearer "+token)

    deleteResp, err := client.Do(deleteReq)
    if err != nil {
        log.Printf("⚠️  Failed to delete temporary file: %v", err)
        return nil
    }
    defer deleteResp.Body.Close()

    if deleteResp.StatusCode == http.StatusNoContent {
        log.Printf("🗑️  Temporary file deleted from OneDrive")
    }

    return nil
}

func respondError(w http.ResponseWriter, err error) {
    log.Printf("❌ Error: %v", err)
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusInternalServerError)
    _ = json.NewEncoder(w).Encode(map[string]string{
        "error": err.Error(),
    })
}

func convertExcelToPDF(excelPath, pdfPath string) error {
    log.Printf("🖨️  Converting Excel to PDF: %s -> %s", excelPath, pdfPath)

    var graphError error

    // Try Microsoft Graph API first if configured
    if graphClient != nil {
        log.Printf("🔄 Attempting conversion via Microsoft Graph API...")
        err := graphClient.convertExcelToPDFGraph(excelPath, pdfPath)
        if err == nil {
            return nil
        }
        graphError = err
        log.Printf("⚠️  Microsoft Graph conversion failed: %v", err)
        log.Printf("🔄 Falling back to LibreOffice...")
    } else {
        log.Printf("ℹ️  Microsoft Graph API not configured, using LibreOffice")
    }

    // Fallback to LibreOffice
    cmd := exec.Command("libreoffice",
        "--headless",
        "--convert-to", "pdf",
        "--outdir", filepath.Dir(pdfPath),
        excelPath,
    )

    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr

    if err := cmd.Run(); err != nil {
        libreOfficeError := fmt.Errorf("LibreOffice conversion failed: %v", err)
        
        if graphError != nil {
            return fmt.Errorf("PDF conversion failed: Graph API error (%v), LibreOffice error (%v). Please install LibreOffice or fix OneDrive access", graphError, libreOfficeError)
        }
        
        return fmt.Errorf("%v. Please install LibreOffice: https://www.libreoffice.org/download/", libreOfficeError)
    }

    log.Printf("✅ PDF generated using LibreOffice at: %s", pdfPath)
    return nil
}

func zipFiles(files map[string]string) ([]byte, error) {
    buf := new(bytes.Buffer)
    zipWriter := zip.NewWriter(buf)

    for name, path := range files {
        if path == "" {
            continue
        }
        f, err := os.Open(path)
        if err != nil {
            return nil, fmt.Errorf("failed to open file for zipping: %v", err)
        }

        w, err := zipWriter.Create(name)
        if err != nil {
            _ = f.Close()
            return nil, fmt.Errorf("failed to create zip entry: %v", err)
        }

        if _, err := io.Copy(w, f); err != nil {
            _ = f.Close()
            return nil, fmt.Errorf("failed to write file to zip: %v", err)
        }
        _ = f.Close()
    }

    if err := zipWriter.Close(); err != nil {
        return nil, fmt.Errorf("failed to close zip writer: %v", err)
    }

    return buf.Bytes(), nil
}

func pdfFilename(excelFilename string) string {
    base := strings.TrimSuffix(excelFilename, filepath.Ext(excelFilename))
    return base + ".pdf"
}

// ====== Excel Generation (Template-based) ======

func createXLSXFile(req TimecardRequest) (*excelize.File, error) {
    log.Printf("📂 Loading template.xlsx...")

    file, err := excelize.OpenFile("template.xlsx")
    if err != nil {
        return nil, fmt.Errorf("failed to load template: %v", err)
    }

    log.Printf("✅ Template loaded successfully")

    originalSheetName := file.GetSheetName(0)
    if originalSheetName == "" {
        return nil, fmt.Errorf("template has no sheets")
    }
    log.Printf("📄 Original sheet name: %s", originalSheetName)

    // If Weeks is empty but Entries provided, split them into up to 2 weeks
    if len(req.Weeks) == 0 && len(req.Entries) > 0 {
        var week1Entries, week2Entries []Entry
        var week1Start, week2Start time.Time

        for _, entry := range req.Entries {
            entryDate, err := time.Parse(time.RFC3339, entry.Date)
            if err != nil {
                log.Printf("⚠️ Skipping entry with invalid date %q: %v", entry.Date, err)
                continue
            }

            entryDate = entryDate.UTC().Truncate(24 * time.Hour)

            if week1Start.IsZero() {
                week1Start = entryDate
            }

            daysDiff := int(entryDate.Sub(week1Start).Hours() / 24.0)
            if daysDiff >= 7 {
                if week2Start.IsZero() {
                    week2Start = entryDate
                }
                week2Entries = append(week2Entries, entry)
            } else {
                week1Entries = append(week1Entries, entry)
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
        var sheetName string

        if i == 0 {
            // Use the original template sheet for Week 1
            sheetName = originalSheetName
            log.Printf("📄 Using original sheet for Week 1: %s", sheetName)
        } else {
            // Create or reuse "Week N" sheets for additional weeks
            sheetName = fmt.Sprintf("Week %d", i+1)

            index, err := file.GetSheetIndex(sheetName)
            if err != nil {
                log.Printf("⚠️ GetSheetIndex error for %s: %v (creating sheet anyway)", sheetName, err)
                if _, err := file.NewSheet(sheetName); err != nil {
                    return nil, fmt.Errorf("failed to create sheet %s: %w", sheetName, err)
                }
            } else if index == -1 {
                log.Printf("📄 Creating new sheet: %s", sheetName)
                if _, err := file.NewSheet(sheetName); err != nil {
                    return nil, fmt.Errorf("failed to create sheet %s: %w", sheetName, err)
                }
            } else {
                log.Printf("ℹ️ Sheet already exists: %s (index=%d)", sheetName, index)
            }
        }

        log.Printf("🗓️ Populating %s with Week %d data", sheetName, i+1)

        // Update per-week info
        req.WeekStartDate = week.WeekStartDate
        req.WeekNumberLabel = week.WeekLabel

        if err := populateTimecardSheet(file, sheetName, req, week.Entries, week.WeekLabel, i+1); err != nil {
            return nil, fmt.Errorf("failed to populate sheet for week %d: %v", i+1, err)
        }
    }

    file.SetActiveSheet(0)
    return file, nil
}

// FIXED populateTimecardSheet:
//
// - Hours go into CODE columns (C,E,G,...) only.
// - JOB names stay in JOB columns (D,F,H,...).
// - Regular rows: 5–11; OT rows: 16–22.
// - B4/B5–B11/B16–B22 set as Excel date serials.
func populateTimecardSheet(
    file *excelize.File,
    sheetName string,
    req TimecardRequest,
    entries []Entry,
    weekLabel string,
    weekNumber int,
) error {
    log.Printf("✍️ Populating sheet %q (week %d, %d entries)", sheetName, weekNumber, len(entries))

    // ---- 1) Header fields ----

    if val, err := file.GetCellValue(sheetName, "M2"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "M2", req.EmployeeName); err != nil {
            return fmt.Errorf("failed setting M2: %w", err)
        }
        log.Printf("✏️ Set M2 (Employee Name) = %s", req.EmployeeName)
    } else {
        log.Printf("⚠️ Skipping M2 (formula or error): %v", err)
    }

    if val, err := file.GetCellValue(sheetName, "AJ2"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "AJ2", req.PayPeriodNum); err != nil {
            return fmt.Errorf("failed setting AJ2: %w", err)
        }
        log.Printf("✏️ Set AJ2 (Pay Period) = %d", req.PayPeriodNum)
    } else {
        log.Printf("⚠️ Skipping AJ2 (formula or error): %v", err)
    }

    if val, err := file.GetCellValue(sheetName, "AJ3"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "AJ3", req.Year); err != nil {
            return fmt.Errorf("failed setting AJ3: %w", err)
        }
        log.Printf("✏️ Set AJ3 (Year) = %d", req.Year)
    } else {
        log.Printf("⚠️ Skipping AJ3 (formula or error): %v", err)
    }

    if err := file.SetCellValue(sheetName, "AJ4", weekLabel); err != nil {
        return fmt.Errorf("failed setting AJ4: %w", err)
    }
    log.Printf("✏️ Set AJ4 (Week Label) = %s", weekLabel)

    // ---- 2) Week start date → Excel serial in B4 ----

    var weekStart time.Time

    if req.WeekStartDate != "" {
        if t, err := time.Parse(time.RFC3339, req.WeekStartDate); err == nil {
            weekStart = t.UTC().Truncate(24 * time.Hour)
        } else {
            log.Printf("⚠️ Failed to parse WeekStartDate=%q: %v", req.WeekStartDate, err)
        }
    }

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

    if weekStart.IsZero() {
        weekStart = time.Now().UTC().Truncate(24 * time.Hour)
    }

    excelEpoch := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
    weekStartSerial := weekStart.Sub(excelEpoch).Hours() / 24.0

    if val, err := file.GetCellValue(sheetName, "B4"); err == nil && !strings.HasPrefix(val, "=") {
        if err := file.SetCellValue(sheetName, "B4", weekStartSerial); err != nil {
            return fmt.Errorf("failed setting B4: %w", err)
        }
        log.Printf("✏️ Set B4 (Week Start) = %.2f", weekStartSerial)
    } else {
        log.Printf("⚠️ Skipping B4 (formula or error): %v", err)
    }

    // ---- 3) Job headers ----

    codeCols := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
    nameCols := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}

    jobIndex := make(map[string]int)

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

        // Overtime headers (row 15)
        if err := file.SetCellValue(sheetName, codeCol+"15", job.JobCode); err != nil {
            return fmt.Errorf("failed setting %s15: %w", codeCol, err)
        }
        if err := file.SetCellValue(sheetName, nameCol+"15", job.JobName); err != nil {
            return fmt.Errorf("failed setting %s15: %w", nameCol, err)
        }

        jobIndex[job.JobCode] = i
        log.Printf("📋 Job %d: Code=%s Name=%s (cols %s/%s)", i+1, job.JobCode, job.JobName, codeCol, nameCol)
    }

    // ---- 4) Aggregate entries by (date, job, overtime) ----

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

    // ---- 5) Fill date columns B5–B11 (regular), B16–B22 (OT) ----

    for i := 0; i < 7; i++ {
        dayDate := weekStart.AddDate(0, 0, i)
        daySerial := dayDate.Sub(excelEpoch).Hours() / 24.0

        regRow := 5 + i
        regCell := "B" + strconv.Itoa(regRow)
        if val, _ := file.GetCellValue(sheetName, regCell); !strings.HasPrefix(val, "=") {
            if err := file.SetCellValue(sheetName, regCell, daySerial); err != nil {
                return fmt.Errorf("failed setting %s: %w", regCell, err)
            }
        }

        otRow := 16 + i
        otCell := "B" + strconv.Itoa(otRow)
        if val, _ := file.GetCellValue(sheetName, otCell); !strings.HasPrefix(val, "=") {
            if err := file.SetCellValue(sheetName, otCell, daySerial); err != nil {
                return fmt.Errorf("failed setting %s: %w", otCell, err)
            }
        }
    }

    // ---- 6) Write hours into CODE columns (C,E,G,...) ----

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

// ====== HTTP Handlers ======

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

    file, err := createXLSXFile(req)
    if err != nil {
        log.Printf("❌ Failed to create Excel: %v", err)
        respondError(w, err)
        return
    }
    defer file.Close()

    tempDir, err := os.MkdirTemp("", "timecard-*")
    if err != nil {
        log.Printf("❌ Failed to create temp dir: %v", err)
        respondError(w, err)
        return
    }
    defer os.RemoveAll(tempDir)

    excelFilename := fmt.Sprintf("Timecard_%s_%d(%d).xlsx", req.EmployeeName, req.Year, req.PayPeriodNum)
    excelPath := filepath.Join(tempDir, excelFilename)

    if err := file.SaveAs(excelPath); err != nil {
        log.Printf("❌ Failed to save Excel: %v", err)
        respondError(w, err)
        return
    }
    log.Printf("✅ Excel file created: %s", excelPath)

    var pdfPath string
    var pdfFileName string

    if req.IncludePDF {
        pdfFileName = pdfFilename(excelFilename)
        pdfPath = filepath.Join(tempDir, pdfFileName)

        log.Printf("🔄 Converting Excel to PDF...")
        if err := convertExcelToPDF(excelPath, pdfPath); err != nil {
            log.Printf("⚠️ PDF conversion failed: %v", err)
            pdfPath = ""
        } else {
            log.Printf("✅ PDF file created: %s", pdfPath)
        }
    }

    if pdfPath != "" {
        zipFilename := fmt.Sprintf("Timecard_%s_%d(%d).zip", req.EmployeeName, req.Year, req.PayPeriodNum)
        zipPath := filepath.Join(tempDir, zipFilename)

        files := map[string]string{
            excelFilename: excelPath,
            pdfFileName:   pdfPath,
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
        return
    }

    // Only Excel
    w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", excelFilename))
    http.ServeFile(w, r, excelPath)
}

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

    file, err := createXLSXFile(req.TimecardRequest)
    if err != nil {
        log.Printf("❌ Failed to create Excel: %v", err)
        respondError(w, err)
        return
    }
    defer file.Close()

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
    var pdfFileName string

    if req.IncludePDF {
        pdfFileName = pdfFilename(excelFilename)
        pdfPath = filepath.Join(tempDir, pdfFileName)

        log.Printf("🔄 Converting Excel to PDF for email...")
        if err := convertExcelToPDF(excelPath, pdfPath); err != nil {
            log.Printf("⚠️ PDF conversion failed for email: %v", err)
            pdfPath = ""
        } else {
            log.Printf("✅ PDF file created for email: %s", pdfPath)
        }
    }

    attachments := map[string]string{
        excelFilename: excelPath,
    }
    if pdfPath != "" {
        attachments[pdfFileName] = pdfPath
    }

    if err := sendEmailWithAttachments(req.To, req.CC, req.Subject, req.Body, attachments); err != nil {
        log.Printf("❌ Failed to send email: %v", err)
        respondError(w, err)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(map[string]string{
        "status": "email sent",
    })
}

// ====== Real SMTP sender ======

func sendEmailWithAttachments(to, cc, subject, body string, attachments map[string]string) error {
    // SMTP settings from environment
    smtpHost := os.Getenv("SMTP_HOST") // e.g. "smtp.sendgrid.net"
    smtpPort := os.Getenv("SMTP_PORT") // e.g. "587"
    smtpUser := os.Getenv("SMTP_USER") // e.g. "apikey"
    smtpPass := os.Getenv("SMTP_PASS") // e.g. "<sendgrid-api-key>"
    smtpFrom := os.Getenv("SMTP_FROM") // e.g. "timecard@logicalgroup.ca"

    if smtpHost == "" || smtpPort == "" || smtpUser == "" || smtpPass == "" || smtpFrom == "" {
        return fmt.Errorf("SMTP env vars not fully set (need SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM)")
    }

    // Build recipient list (To + Cc)
    var toAddrs []string
    if strings.TrimSpace(to) != "" {
        for _, addr := range strings.Split(to, ",") {
            a := strings.TrimSpace(addr)
            if a != "" {
                toAddrs = append(toAddrs, a)
            }
        }
    }
    if strings.TrimSpace(cc) != "" {
        for _, addr := range strings.Split(cc, ",") {
            a := strings.TrimSpace(addr)
            if a != "" {
                toAddrs = append(toAddrs, a)
            }
        }
    }
    if len(toAddrs) == 0 {
        return fmt.Errorf("no recipients specified")
    }

    boundary := fmt.Sprintf("TIME-CARD-%d", time.Now().UnixNano())
    var msg bytes.Buffer

    // Headers
    fmt.Fprintf(&msg, "From: %s\r\n", smtpFrom)
    fmt.Fprintf(&msg, "To: %s\r\n", to)
    if strings.TrimSpace(cc) != "" {
        fmt.Fprintf(&msg, "Cc: %s\r\n", cc)
    }
    fmt.Fprintf(&msg, "Subject: %s\r\n", subject)
    fmt.Fprintf(&msg, "MIME-Version: 1.0\r\n")
    fmt.Fprintf(&msg, "Content-Type: multipart/mixed; boundary=%s\r\n", boundary)
    fmt.Fprintf(&msg, "\r\n")

    // Text body
    fmt.Fprintf(&msg, "--%s\r\n", boundary)
    fmt.Fprintf(&msg, "Content-Type: text/plain; charset=\"utf-8\"\r\n")
    fmt.Fprintf(&msg, "Content-Transfer-Encoding: 7bit\r\n")
    fmt.Fprintf(&msg, "\r\n")
    fmt.Fprintf(&msg, "%s\r\n", body)

    // Attachments
    for filename, path := range attachments {
        if path == "" {
            continue
        }

        data, err := os.ReadFile(path)
        if err != nil {
            return fmt.Errorf("failed to read attachment %s: %w", path, err)
        }

        encoded := base64.StdEncoding.EncodeToString(data)

        fmt.Fprintf(&msg, "--%s\r\n", boundary)
        fmt.Fprintf(&msg, "Content-Type: application/octet-stream\r\n")
        fmt.Fprintf(&msg, "Content-Transfer-Encoding: base64\r\n")
        fmt.Fprintf(&msg, "Content-Disposition: attachment; filename=%q\r\n", filename)
        fmt.Fprintf(&msg, "\r\n")

        // Wrap base64 at 76 chars per line
        for i := 0; i < len(encoded); i += 76 {
            end := i + 76
            if end > len(encoded) {
                end = len(encoded)
            }
            fmt.Fprintf(&msg, "%s\r\n", encoded[i:end])
        }
    }

    fmt.Fprintf(&msg, "--%s--\r\n", boundary)

    addr := fmt.Sprintf("%s:%s", smtpHost, smtpPort)
    auth := smtp.PlainAuth("", smtpUser, smtpPass, smtpHost)

    log.Printf("📨 Sending email via SMTP %s as %s to %v", addr, smtpFrom, toAddrs)

    if err := smtp.SendMail(addr, auth, smtpFrom, toAddrs, msg.Bytes()); err != nil {
        return fmt.Errorf("failed to send email via SMTP: %w", err)
    }

    log.Printf("✅ Email sent successfully")
    return nil
}

// ====== Misc Handlers ======

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(map[string]string{
        "status": "ok",
    })
}

func testLibreOfficeHandler(w http.ResponseWriter, r *http.Request) {
    cmd := exec.Command("libreoffice", "--version")
    output, err := cmd.CombinedOutput()
    if err != nil {
        w.WriteHeader(http.StatusInternalServerError)
        _, _ = fmt.Fprintf(w, "LibreOffice test failed: %v\nOutput: %s", err, string(output))
        return
    }

    w.WriteHeader(http.StatusOK)
    _, _ = fmt.Fprintf(w, "LibreOffice is working:\n%s", string(output))
}

func testGraphAPIHandler(w http.ResponseWriter, r *http.Request) {
    if graphClient == nil {
        w.WriteHeader(http.StatusServiceUnavailable)
        w.Header().Set("Content-Type", "application/json")
        _ = json.NewEncoder(w).Encode(map[string]string{
            "status": "not_configured",
            "error":  "Microsoft Graph API is not configured. Please set MICROSOFT_TENANT_ID, MICROSOFT_CLIENT_ID, MICROSOFT_CLIENT_SECRET, and MICROSOFT_USER_ID environment variables.",
        })
        return
    }

    token, err := graphClient.getAccessToken()
    if err != nil {
        w.WriteHeader(http.StatusInternalServerError)
        w.Header().Set("Content-Type", "application/json")
        _ = json.NewEncoder(w).Encode(map[string]string{
            "status": "error",
            "error":  fmt.Sprintf("Failed to get access token: %v", err),
        })
        return
    }

    // Test API call - get user profile
    userURL := fmt.Sprintf("https://graph.microsoft.com/v1.0/users/%s", graphClient.UserID)
    req, _ := http.NewRequest("GET", userURL, nil)
    req.Header.Set("Authorization", "Bearer "+token)

    client := &http.Client{Timeout: 10 * time.Second}
    resp, err := client.Do(req)
    if err != nil {
        w.WriteHeader(http.StatusInternalServerError)
        w.Header().Set("Content-Type", "application/json")
        _ = json.NewEncoder(w).Encode(map[string]string{
            "status": "error",
            "error":  fmt.Sprintf("API call failed: %v", err),
        })
        return
    }
    defer resp.Body.Close()

    var result map[string]interface{}
    _ = json.NewDecoder(resp.Body).Decode(&result)

    w.WriteHeader(http.StatusOK)
    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(map[string]interface{}{
        "status":       "ok",
        "tenant_id":    graphClient.TenantID,
        "client_id":    graphClient.ClientID,
        "user_id":      graphClient.UserID,
        "token_valid":  token != "",
        "api_response": result,
    })
}

// ====== main ======

func main() {
    // Initialize Microsoft Graph API client
    initGraphClient()

    // Log SMTP configuration
    smtpHost := os.Getenv("SMTP_HOST")
    smtpPort := os.Getenv("SMTP_PORT")
    smtpUser := os.Getenv("SMTP_USER")
    if smtpHost != "" && smtpPort != "" && smtpUser != "" {
        log.Printf("✅ SMTP configured: %s:%s (user: %s)", smtpHost, smtpPort, smtpUser)
    } else {
        log.Printf("⚠️  SMTP not fully configured")
    }

    http.HandleFunc("/health", healthHandler)

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
    http.HandleFunc("/test/graph-api", testGraphAPIHandler)

    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    log.Printf("🚀 Server starting on port %s", port)
    if err := http.ListenAndServe(":"+port, nil); err != nil {
        log.Fatalf("Server failed: %v", err)
    }
}
