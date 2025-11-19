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

	// Check if multi-week data is provided
	if req.Weeks != nil && len(req.Weeks) > 0 {
		log.Printf("📊 Processing multi-week timecard (%d weeks)", len(req.Weeks))

		// Get the template sheet name (usually "Sheet1" or "Timecard")
		templateSheetName := file.GetSheetName(0)

		for i, weekData := range req.Weeks {
			sheetName := weekData.WeekLabel // e.g., "Week 1", "Week 2"

			if i == 0 {
				// Rename the first sheet
				file.SetSheetName(templateSheetName, sheetName)
				log.Printf("📝 Renamed template sheet to: %s", sheetName)
			} else {
				// Clone the first sheet to preserve all formatting
				sourceIndex := 0
				newIndex, err := file.NewSheet(sheetName)
				if err != nil {
					return nil, fmt.Errorf("failed to create sheet %s: %v", sheetName, err)
				}
				
				// Copy from the first sheet (Week 1) to preserve formatting
				if err := file.CopySheet(sourceIndex, newIndex); err != nil {
					return nil, fmt.Errorf("failed to copy sheet: %v", err)
				}
				log.Printf("📝 Created sheet: %s (cloned from Week 1)", sheetName)
			}

			// Populate the sheet with this week's data
			if err := populateTimecardSheet(file, sheetName, req, weekData.Entries, weekData.WeekLabel, weekData.WeekNumber); err != nil {
				return nil, fmt.Errorf("failed to populate sheet %s: %v", sheetName, err)
			}
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

	// Set employee name (cell E2)
	file.SetCellValue(sheetName, "E2", req.EmployeeName)

	// Set pay period and year (cells AL2 and AL3)
	file.SetCellValue(sheetName, "AL2", req.PayPeriodNum)
	file.SetCellValue(sheetName, "AL3", req.Year)

	// Set week label (cell AK4)
	file.SetCellValue(sheetName, "AK4", weekLabel)

	// Parse dates and populate entries
	// The template has date columns starting at row 6
	// Columns: B=Sunday, D=Monday, F=Tuesday, H=Wednesday, J=Thursday, L=Friday, N=Saturday
	dateColumnMap := map[string]string{
		"Sunday":    "B",
		"Monday":    "D",
		"Tuesday":   "F",
		"Wednesday": "H",
		"Thursday":  "J",
		"Friday":    "L",
		"Saturday":  "N",
	}

	// Map to store entries by date and job
	type EntryKey struct {
		Date    string
		JobCode string
	}
	entryMap := make(map[EntryKey]Entry)

	for _, entry := range entries {
		key := EntryKey{Date: entry.Date, JobCode: entry.JobCode}
		entryMap[key] = entry
	}

	// Create a map of job codes to row numbers (starting at row 6)
	jobRowMap := make(map[string]int)
	startRow := 6
	for i, job := range req.Jobs {
		row := startRow + i
		jobRowMap[job.JobCode] = row

		// Set job code in column A
		file.SetCellValue(sheetName, "A"+strconv.Itoa(row), job.JobCode)
	}

	// Fill in hours for each entry
	for key, entry := range entryMap {
		// Parse the date to get the day of week
		t, err := time.Parse(time.RFC3339, entry.Date)
		if err != nil {
			log.Printf("⚠️ Failed to parse date %s: %v", entry.Date, err)
			continue
		}

		dayOfWeek := t.Weekday().String()
		col, ok := dateColumnMap[dayOfWeek]
		if !ok {
			log.Printf("⚠️ Unknown day of week: %s", dayOfWeek)
			continue
		}

		row, ok := jobRowMap[entry.JobCode]
		if !ok {
			log.Printf("⚠️ Job code not found: %s", entry.JobCode)
			continue
		}

		// Set the hours
		cellRef := col + strconv.Itoa(row)
		file.SetCellValue(sheetName, cellRef, entry.Hours)

		// If overtime, you might want to mark it (depends on your template)
		// For example, you could use a different cell or format
		if entry.Overtime {
			// Set overtime hours in the next column (if your template supports it)
			// This is an example - adjust based on your actual template structure
			overtimeCol := string(rune(col[0]) + 1) // Next column
			overtimeCellRef := overtimeCol + strconv.Itoa(row)
			file.SetCellValue(sheetName, overtimeCellRef, entry.Hours)
		}
	}

	// The template should have formulas for totals, so we don't need to calculate them manually
	// If your template doesn't have formulas, you can add them here

	log.Printf("✅ Sheet %s populated successfully", sheetName)
	return nil
}
