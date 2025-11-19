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
			"version": "2.2.0",
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

	// Create xlsx file
	file, err := createXLSXFile(req)
	if err != nil {
		log.Printf("❌ Failed to create Excel: %v", err)
		respondError(w, err)
		return
	}

	// Create temp directory
	tempDir, err := os.MkdirTemp("", "timecard-*")
	if err != nil {
		log.Printf("❌ Failed to create temp dir: %v", err)
		respondError(w, err)
		return
	}
	defer os.RemoveAll(tempDir)

	// Save Excel file
	excelFilename := fmt.Sprintf("Timecard_%s_%s.xlsx", req.EmployeeName, time.Now().Format("2006-01-02"))
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
		pdfFilename := fmt.Sprintf("Timecard_%s_%s.pdf", req.EmployeeName, time.Now().Format("2006-01-02"))
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
		w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"timecard_%s.zip\"", time.Now().Format("2006-01-02")))
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

	// Generate Excel file
	file, err := createXLSXFile(req.TimecardRequest)
	if err != nil {
		respondError(w, err)
		return
	}

	// Create temp directory
	tempDir, err := os.MkdirTemp("", "timecard-*")
	if err != nil {
		respondError(w, err)
		return
	}
	defer os.RemoveAll(tempDir)

	// Save Excel
	excelFilename := fmt.Sprintf("Timecard_%s_%s.xlsx", req.EmployeeName, time.Now().Format("2006-01-02"))
	excelPath := filepath.Join(tempDir, excelFilename)
	if err := file.SaveAs(excelPath); err != nil {
		respondError(w, err)
		return
	}

	log.Printf("✅ Excel file created for email: %s", excelPath)

	// Generate PDF if requested
	var pdfPath string
	if req.IncludePDF {
		pdfFilename := fmt.Sprintf("Timecard_%s_%s.pdf", req.EmployeeName, time.Now().Format("2006-01-02"))
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

func createXLSXFile(req TimecardRequest) (*excelize.File, error) {
	file := excelize.NewFile()

	sheetName := "Timecard"
	_, err := file.NewSheet(sheetName)
	if err != nil {
		return nil, fmt.Errorf("failed to create sheet: %v", err)
	}

	file.DeleteSheet("Sheet1")

	file.SetColWidth(sheetName, "A", "A", 12)
	file.SetColWidth(sheetName, "B", "B", 20)
	file.SetColWidth(sheetName, "C", "C", 10)
	file.SetColWidth(sheetName, "D", "D", 10)

	headerStyle, _ := file.NewStyle(&excelize.Style{
		Font:      &excelize.Font{Bold: true, Size: 12},
		Fill:      excelize.Fill{Type: "pattern", Color: []string{"#4472C4"}, Pattern: 1},
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
	})

	row := 1
	file.SetCellValue(sheetName, "A"+strconv.Itoa(row), "TIMECARD")
	file.MergeCell(sheetName, "A"+strconv.Itoa(row), "D"+strconv.Itoa(row))
	file.SetCellStyle(sheetName, "A"+strconv.Itoa(row), "D"+strconv.Itoa(row), headerStyle)
	row++

	file.SetCellValue(sheetName, "A"+strconv.Itoa(row), "Employee:")
	file.SetCellValue(sheetName, "B"+strconv.Itoa(row), req.EmployeeName)
	row++

	file.SetCellValue(sheetName, "A"+strconv.Itoa(row), "Pay Period:")
	file.SetCellValue(sheetName, "B"+strconv.Itoa(row), req.PayPeriodNum)
	row++

	file.SetCellValue(sheetName, "A"+strconv.Itoa(row), "Year:")
	file.SetCellValue(sheetName, "B"+strconv.Itoa(row), req.Year)
	row += 2

	file.SetCellValue(sheetName, "A"+strconv.Itoa(row), "Date")
	file.SetCellValue(sheetName, "B"+strconv.Itoa(row), "Job Code")
	file.SetCellValue(sheetName, "C"+strconv.Itoa(row), "Hours")
	file.SetCellValue(sheetName, "D"+strconv.Itoa(row), "Overtime")
	file.SetCellStyle(sheetName, "A"+strconv.Itoa(row), "D"+strconv.Itoa(row), headerStyle)
	row++

	for _, entry := range req.Entries {
		file.SetCellValue(sheetName, "A"+strconv.Itoa(row), entry.Date)
		file.SetCellValue(sheetName, "B"+strconv.Itoa(row), entry.JobCode)
		file.SetCellValue(sheetName, "C"+strconv.Itoa(row), entry.Hours)
		overtimeText := "No"
		if entry.Overtime {
			overtimeText = "Yes"
		}
		file.SetCellValue(sheetName, "D"+strconv.Itoa(row), overtimeText)
		row++
	}

	row++
	totalHours := 0.0
	for _, entry := range req.Entries {
		totalHours += entry.Hours
	}
	file.SetCellValue(sheetName, "B"+strconv.Itoa(row), "Total Hours:")
	file.SetCellValue(sheetName, "C"+strconv.Itoa(row), totalHours)
	file.SetCellStyle(sheetName, "B"+strconv.Itoa(row), "C"+strconv.Itoa(row), headerStyle)

	return file, nil
}
