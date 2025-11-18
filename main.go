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

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "ok",
			"message": "Timecard API is running",
			"endpoints": []string{
				"/api/generate-timecard",
				"/api/email-timecard",
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
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req TimecardRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, err)
		return
	}

	log.Printf("📥 Generating timecard for %s (IncludePDF: %v)", req.EmployeeName, req.IncludePDF)

	// Create xlsx file
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
			respondError(w, err)
			return
		}

		pdfFilename := filepath.Base(pdfPath)
		if err := addFileToZip(zipWriter, pdfPath, pdfFilename); err != nil {
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
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req EmailTimecardRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, err)
		return
	}

	// Check SMTP configuration
	smtpHost := os.Getenv("SMTP_HOST")
	if smtpHost == "" {
		respondError(w, fmt.Errorf("SMTP not configured on server"))
		return
	}

	log.Printf("📧 Email handler called (SMTP not fully implemented yet)")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "error",
		"message": "SMTP not configured on server",
	})
}

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

func convertExcelToPDF(excelPath, pdfPath string) error {
	outputDir := filepath.Dir(pdfPath)

	cmd := exec.Command("libreoffice",
		"--headless",
		"--convert-to", "pdf",
		"--outdir", outputDir,
		excelPath)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("LibreOffice conversion failed: %v, output: %s", err, string(output))
	}

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

func createXLSXFile(req TimecardRequest) (*excelize.File, error) {
	file := excelize.NewFile()

	// Create sheet with proper error handling
	sheetName := "Timecard"
	_, err := file.NewSheet(sheetName)
	if err != nil {
		return nil, fmt.Errorf("failed to create sheet: %v", err)
	}

	// Delete default sheet
	file.DeleteSheet("Sheet1")

	// Set column widths
	file.SetColWidth(sheetName, "A", "A", 12)
	file.SetColWidth(sheetName, "B", "B", 20)
	file.SetColWidth(sheetName, "C", "C", 10)
	file.SetColWidth(sheetName, "D", "D", 10)

	// Header style
	headerStyle, _ := file.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 12},
		Fill: excelize.Fill{Type: "pattern", Color: []string{"#4472C4"}, Pattern: 1},
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
	})

	// Title
	row := 1
	file.SetCellValue(sheetName, "A"+strconv.Itoa(row), "TIMECARD")
	file.MergeCell(sheetName, "A"+strconv.Itoa(row), "D"+strconv.Itoa(row))
	file.SetCellStyle(sheetName, "A"+strconv.Itoa(row), "D"+strconv.Itoa(row), headerStyle)
	row++

	// Employee info
	file.SetCellValue(sheetName, "A"+strconv.Itoa(row), "Employee:")
	file.SetCellValue(sheetName, "B"+strconv.Itoa(row), req.EmployeeName)
	row++

	file.SetCellValue(sheetName, "A"+strconv.Itoa(row), "Pay Period:")
	file.SetCellValue(sheetName, "B"+strconv.Itoa(row), req.PayPeriodNum)
	row++

	file.SetCellValue(sheetName, "A"+strconv.Itoa(row), "Year:")
	file.SetCellValue(sheetName, "B"+strconv.Itoa(row), req.Year)
	row += 2

	// Column headers
	file.SetCellValue(sheetName, "A"+strconv.Itoa(row), "Date")
	file.SetCellValue(sheetName, "B"+strconv.Itoa(row), "Job Code")
	file.SetCellValue(sheetName, "C"+strconv.Itoa(row), "Hours")
	file.SetCellValue(sheetName, "D"+strconv.Itoa(row), "Overtime")
	file.SetCellStyle(sheetName, "A"+strconv.Itoa(row), "D"+strconv.Itoa(row), headerStyle)
	row++

	// Add entries
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

	// Total hours
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
