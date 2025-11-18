package main

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
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

// Environment variables for SMTP configuration (SendGrid, AWS SES, Mailgun, etc.)
const SMTP_HOST = "smtp.sendgrid.net"              // This should be literally "smtp" for SendGrid
const SMTP_PORT = "587"                            // Port is 587 for STARTTLS (recommended) or 465 for SSL/TLS
const SMTP_USER = "apikey"                         // For SendGrid, username should be "apikey"
const SMTP_PASS_ENV = "SMTP_PASS"                  // This is the environment variable name (e.g., your SendGrid API key)
const SMTP_FROM_ENV = "SMTP_FROM"                  // Sender email (must be verified in SendGrid/AWS SES)

// Environment variable should be set in your development environment properly.
// export SMTP_HOST="smtp.sendgrid.net"
// export SMTP_PORT="587"
// export SMTP_USER="apikey"
// export SMTP_PASS="your_actual_sendgrid_api_key"
// export SMTP_FROM="noreply@yourdomain.com"

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "ok",
			"message": "Timecard API is running",
			"endpoints": []string{
				"/api/generate-timecard",
				"/test/libreoffice",
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

	log.Printf("Server starting on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
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
	IncludePDF      bool       `json:"include_pdf"` // NEW: PDF generation flag
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
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req TimecardRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, err)
		return
	}

	log.Printf("📥 Request: %+v", req)
	log.Printf("🔧 IncludePDF: %v", req.IncludePDF)

	// Create xlsx file using excelize
	file, err := createXLSXFile(req)
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

	// Save Excel file
	excelFilename := fmt.Sprintf("Timecard_%s_%s.xlsx", req.EmployeeName, time.Now().Format("2006-01-02"))
	excelPath := filepath.Join(tempDir, excelFilename)

	if err := file.SaveAs(excelPath); err != nil {
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
			pdfPath = "" // Continue without PDF
		} else {
			log.Printf("✅ PDF file created: %s", pdfPath)
		}
	}

	// If PDF was generated, return ZIP archive with both files
	if pdfPath != "" && fileExists(pdfPath) {
		log.Printf("📦 Creating ZIP archive with Excel and PDF")
		zipBuffer := new(bytes.Buffer)
		zipWriter := zip.NewWriter(zipBuffer)

		// Add Excel to ZIP
		if err := addFileToZip(zipWriter, excelPath, excelFilename); err != nil {
			respondError(w, err)
			return
		}

		// Add PDF to ZIP
		pdfFilename := filepath.Base(pdfPath)
		if err := addFileToZip(zipWriter, pdfPath, pdfFilename); err != nil {
			respondError(w, err)
			return
		}

		zipWriter.Close()

		// Send ZIP file
		w.Header().Set("Content-Type", "application/zip")
		w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"timecard_%s.zip\"", time.Now().Format("2006-01-02")))
		w.Write(zipBuffer.Bytes())
		log.Printf("✅ Sent ZIP file: %d bytes", zipBuffer.Len())
	} else {
		// Return just Excel file
		excelData, err := os.ReadFile(excelPath)
		if err != nil {
			respondError(w, err)
			return
		}

		w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
		w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", excelFilename))
		w.Write(excelData)
		log.Printf("✅ Sent Excel file: %d bytes", len(excelData))
	}
}

// Convert Excel to PDF using LibreOffice
func convertExcelToPDF(excelPath, pdfPath string) error {
	outputDir := filepath.Dir(pdfPath)

	// Run LibreOffice headless conversion
	cmd := exec.Command("libreoffice",
		"--headless",
		"--convert-to", "pdf",
		"--outdir", outputDir,
		excelPath)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("LibreOffice conversion failed: %v, output: %s", err, string(output))
	}

	// LibreOffice creates PDF with same base name
	baseName := strings.TrimSuffix(filepath.Base(excelPath), filepath.Ext(excelPath))
	generatedPDF := filepath.Join(outputDir, baseName+".pdf")

	// Rename to desired output path if different
	if generatedPDF != pdfPath {
		if err := os.Rename(generatedPDF, pdfPath); err != nil {
			return fmt.Errorf("failed to rename PDF: %v", err)
		}
	}

	return nil
}

// Add file to ZIP archive
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

// Check if file exists
func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// Test LibreOffice installation
func testLibreOfficeHandler(w http.ResponseWriter, r *http.Request) {
	cmd := exec.Command("libreoffice", "--version")
	output, err := cmd.CombinedOutput()
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(fmt.Sprintf("❌ Error: %v\nOutput: %s", err, string(output))))
		return
	}
	w.Write([]byte(fmt.Sprintf("✅ LibreOffice installed:\n%s", string(output))))
}

func emailTimecardHandler(w http.ResponseWriter, r *http.Request) {
	// ... (keep your existing email handler code, but add PDF support similarly)
	w.Write([]byte("Email handler - add PDF support here if needed"))
}

func respondError(w http.ResponseWriter, err error) {
	log.Printf("❌ Error: %v", err)
	w.WriteHeader(http.StatusInternalServerError)
	json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
}

// createXLSXFile generates the Excel file (keep your existing implementation)
func createXLSXFile(req TimecardRequest) (*excelize.File, error) {
	// Your existing Excel generation logic here
	// This is just a placeholder - use your actual implementation
	file := excelize.NewFile()
	
	// Add your timecard generation logic here
	// ... (keep your existing code)
	
	return file, nil
}
