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

	// Check SendGrid configuration
	if os.Getenv("SMTP_PASS") != "" && os.Getenv("SMTP_FROM") != "" {
		log.Printf("✅ SendGrid configured: from=%s", os.Getenv("SMTP_FROM"))
	} else {
		log.Printf("⚠️ SendGrid not configured (SMTP_PASS or SMTP_FROM missing)")
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
			"version": "2.5.0",
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
	sendgridAPIKey := os.Getenv("SMTP_PASS")
	smtpFrom := os.Getenv("SMTP_FROM")

	if sendgridAPIKey == "" || smtpFrom == "" {
		log.Printf("⚠️ SendGrid not configured")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{
			"status":  "error",
			"message": "SendGrid not configured on server (SMTP_PASS or SMTP_FROM missing)",
		})
		return
	}

	log.Printf("📧 Sending email from %s to %s via SendGrid", smtpFrom, req.To)

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
	log.Printf("📧 Using SendGrid HTTP API v3")

	// Read Excel attachment
	excelData, err := os.ReadFile(excelPath)
	if err != nil {
		return fmt.Errorf("failed to read Excel file: %v", err)
	}

	// Read PDF attachment if exists
	var pdfData []byte
	if pdfPath != "" && fileExists(pdfPath) {
		pdfData, _ = os.ReadFile(pdfPath)
	}

	// Build SendGrid API request structure
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

	// Build the request
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

	// Add CC recipients if provided
	if cc != "" {
		ccAddresses := strings.Split(cc, ",")
		for _, addr := range ccAddresses {
			addr = strings.TrimSpace(addr)
			if addr != "" {
				req.Personalizations[0].Cc = append(req.Personalizations[0].Cc, Email{Email: addr})
			}
		}
	}

	// Add PDF attachment if exists
	if len(pdfData) > 0 {
		req.Attachments = append(req.Attachments, Attachment{
			Content:     base64.StdEncoding.EncodeToString(pdfData),
			Type:        "application/pdf",
			Filename:    filepath.Base(pdfPath),
			Disposition: "attachment",
		})
		log.Printf("📎 Added PDF attachment: %s (%d bytes)", filepath.Base(pdfPath), len(pdfData))
	}

	// Encode to JSON
	jsonData, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("failed to encode JSON: %v", err)
	}

	// Send HTTP request to SendGrid API
	httpReq, err := http.NewRequest("POST", "https://api.sendgrid.com/v3/mail/send", bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create HTTP request: %v", err)
	}

	httpReq.Header.Set("Authorization", "Bearer "+apiKey)
	httpReq.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		return fmt.Errorf("HTTP request failed: %v", err)
	}
	defer resp.Body.Close()

	// SendGrid returns 202 Accepted on success
	if resp.StatusCode != 202 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("SendGrid API error: %d - %s", resp.StatusCode, string(bodyBytes))
	}

	log.Printf("✅ Email sent via SendGrid (status: %d)", resp.StatusCode)
	return nil
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
	log.Printf("🔍 Original template sheet name: %s", originalSheetName)

	// Check if multi-week data is provided
	if req.Weeks != nil && len(req.Weeks) > 0 {
		log.Printf("📊 Processing multi-week timecard (%d weeks)", len(req.Weeks))

		// Delete all sheets except the first one
		sheetList := file.GetSheetList()
		for i := 1; i < len(sheetList); i++ {
			if err := file.DeleteSheet(sheetList[i]); err != nil {
				log.Printf("⚠️ Could not delete sheet %s: %v", sheetList[i], err)
			}
		}

		// Process each week
		for i, weekData := range req.Weeks {
			var targetSheetName string

			if i == 0 {
				// First week: rename the original sheet
				targetSheetName = weekData.WeekLabel
				if err := file.SetSheetName(originalSheetName, targetSheetName); err != nil {
					return nil, fmt.Errorf("failed to rename first sheet to %s: %v", targetSheetName, err)
				}
				originalSheetName = targetSheetName
				log.Printf("📝 Renamed original sheet to: %s", targetSheetName)
			} else {
				// Subsequent weeks: copy the first week sheet
				targetSheetName = weekData.WeekLabel
				newSheetIndex, err := file.NewSheet(targetSheetName)
				if err != nil {
					return nil, fmt.Errorf("failed to create sheet for week %d: %v", i+1, err)
				}

				if err := file.CopySheet(0, newSheetIndex); err != nil {
					return nil, fmt.Errorf("failed to copy sheet for week %d: %v", i+1, err)
				}
				log.Printf("📝 Created and copied sheet: %s", targetSheetName)
			}

			// Populate this week's data
			if err := populateTimecardSheet(file, targetSheetName, req, weekData.Entries, weekData.WeekLabel, weekData.WeekNumber); err != nil {
				return nil, fmt.Errorf("failed to populate sheet %s: %v", targetSheetName, err)
			}
		}

		// Set the first week as active
		file.SetActiveSheet(0)
	} else {
		// Single week: use the template's existing sheet
		log.Printf("📊 Processing single-week timecard")

		// Delete all sheets except the first one
		sheetList := file.GetSheetList()
		for i := 1; i < len(sheetList); i++ {
			if err := file.DeleteSheet(sheetList[i]); err != nil {
				log.Printf("⚠️ Could not delete sheet %s: %v", sheetList[i], err)
			}
		}

		if req.WeekNumberLabel != "" {
			file.SetSheetName(originalSheetName, req.WeekNumberLabel)
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

	// Check if cells have formulas before overwriting
	m2Value, _ := file.GetCellValue(sheetName, "M2")
	if !strings.HasPrefix(m2Value, "=") {
		file.SetCellValue(sheetName, "M2", req.EmployeeName)
		log.Printf("✏️ Set M2 (Employee Name) = %s", req.EmployeeName)
	} else {
		log.Printf("⚠️ Skipping M2 (contains formula): %s", m2Value)
	}

	aj2Value, _ := file.GetCellValue(sheetName, "AJ2")
	if !strings.HasPrefix(aj2Value, "=") {
		file.SetCellValue(sheetName, "AJ2", req.PayPeriodNum)
		log.Printf("✏️ Set AJ2 (PP#) = %d", req.PayPeriodNum)
	} else {
		log.Printf("⚠️ Skipping AJ2 (contains formula): %s", aj2Value)
	}

	aj3Value, _ := file.GetCellValue(sheetName, "AJ3")
	if !strings.HasPrefix(aj3Value, "=") {
		file.SetCellValue(sheetName, "AJ3", req.Year)
		log.Printf("✏️ Set AJ3 (Year) = %d", req.Year)
	} else {
		log.Printf("⚠️ Skipping AJ3 (contains formula): %s", aj3Value)
	}

	file.SetCellValue(sheetName, "AJ4", weekLabel)
	log.Printf("✏️ Set AJ4 (Week Label) = %s", weekLabel)

	// Parse week start date
	weekStart, err := time.Parse(time.RFC3339, req.WeekStartDate)
	if err != nil {
		log.Printf("⚠️ Failed to parse week start date: %v", err)
		weekStart = time.Now()
	}
	excelEpoch := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
	daysSinceEpoch := weekStart.Sub(excelEpoch).Hours() / 24

	b4Value, _ := file.GetCellValue(sheetName, "B4")
	if !strings.HasPrefix(b4Value, "=") {
		file.SetCellValue(sheetName, "B4", daysSinceEpoch)
		log.Printf("✏️ Set B4 (Week Start) = %.2f", daysSinceEpoch)
	} else {
		log.Printf("⚠️ Skipping B4 (contains formula): %s", b4Value)
	}

	// Job columns
	jobCodeColumns := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
	jobNameColumns := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}

	jobColumnMap := make(map[string]string)
	for i, job := range req.Jobs {
		if i >= len(jobCodeColumns) {
			log.Printf("⚠️ Too many jobs (%d), template only supports %d jobs", len(req.Jobs), len(jobCodeColumns))
			break
		}

		file.SetCellValue(sheetName, jobCodeColumns[i]+"4", job.JobCode)
		file.SetCellValue(sheetName, jobNameColumns[i]+"4", job.JobName)
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
		entryDate, err := time.Parse(time.RFC3339, entry.Date)
		if err != nil {
			log.Printf("⚠️ Failed to parse entry date %s: %v", entry.Date, err)
			continue
		}

		jobCol, exists := jobColumnMap[entry.JobCode]
		if !exists {
			log.Printf("⚠️ Job code %s not found in job column map", entry.JobCode)
			continue
		}

		dayOffset := int(entryDate.Sub(weekStart).Hours() / 24)
		if dayOffset < 0 || dayOffset > 6 {
			log.Printf("⚠️ Entry date %s is outside week range (offset=%d)", entry.Date, dayOffset)
			continue
		}

		var row int
		if entry.Overtime {
			row = 16 + dayOffset
		} else {
			row = 5 + dayOffset
		}

		cellRef := jobCol + strconv.Itoa(row)
		file.SetCellValue(sheetName, cellRef, entry.Hours)
		log.Printf("✏️ Set %s = %.2f hours (Job: %s, Date: %s, OT: %v)",
			cellRef, entry.Hours, entry.JobCode, entryDate.Format("Mon Jan 2"), entry.Overtime)
	}

	// Set date cells for each day
	for i := 0; i < 7; i++ {
		dayDate := weekStart.AddDate(0, 0, i)
		daySerial := dayDate.Sub(excelEpoch).Hours() / 24

		// Regular time dates
		regularCell := "B" + strconv.Itoa(5+i)
		regValue, _ := file.GetCellValue(sheetName, regularCell)
		if !strings.HasPrefix(regValue, "=") {
			file.SetCellValue(sheetName, regularCell, daySerial)
		}

		// Overtime dates
		overtimeCell := "B" + strconv.Itoa(16+i)
		otValue, _ := file.GetCellValue(sheetName, overtimeCell)
		if !strings.HasPrefix(otValue, "=") {
			file.SetCellValue(sheetName, overtimeCell, daySerial)
		}
	}

	log.Printf("✅ Sheet %s populated successfully", sheetName)
	return nil
}
