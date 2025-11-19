package main

/*
Example environment variable configuration for SendGrid SMTP (do NOT hardcode in source):

export SMTP_HOST="smtp.sendgrid.net"
export SMTP_PORT="587"
export SMTP_USER="apikey"       # This must be literally "apikey" for SendGrid
export SMTP_PASS="your_sendgrid_api_key_here"

These environment variables should be set in your deployment environment securely.
*/

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/xuri/excelize/v2"
)

type TimecardRequest struct {
	EmployeeName    string     `json:"employee_name"`
	PayPeriodNum    int        `json:"pay_period_num"`
	Year           int        `json:"year"`
	WeekStartDate   string     `json:"week_start_date"`
	WeekNumberLabel string     `json:"week_number_label"`
	Jobs            []Job      `json:"jobs"`
	Entries         []Entry    `json:"entries"`
	Weeks           []WeekData `json:"weeks,omitempty"`
	IncludePDF      bool       `json:"include_pdf"`
}

type Job struct {
	JobCode string `json:"job_code"`
	JobName string `json:"job_name"`
}

type Entry struct {
	Date         string  `json:"date"`
	JobCode      string  `json:"job_code"`
	Hours        float64 `json:"hours"`
	Overtime     bool    `json:"overtime"`
	IsNightShift bool    `json:"is_night_shift"`
}

type WeekData struct {
	WeekNumber    int     `json:"week_number"`
	WeekStartDate string  `json:"week_start_date"`
	WeekLabel     string  `json:"week_label"`
	Entries       []Entry `json:"entries"`
}

type TimecardResponse struct {
	Success    bool   `json:"success"`
	Error      string `json:"error,omitempty"`
	XLSXBase64 string `json:"xlsx_base64,omitempty"`
	PDFBase64  string `json:"pdf_base64,omitempty"`
}

func convertXLSXToPDF(xlsxPath, pdfPath string) error {
	cmd := exec.Command("libreoffice", "--headless", "--convert-to", "pdf", "--outdir", filepath.Dir(pdfPath), xlsxPath)
	return cmd.Run()
}

func generateTimecardHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req TimecardRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondErr(w, err)
		return
	}

	// Create XLSX file using excelize
	file := excelize.NewFile()
	index, err := file.NewSheet("Sheet1")
	if err != nil {
		respondErr(w, err)
		return
	}
	file.SetCellValue("Sheet1", "A1", "Employee Name")
	file.SetCellValue("Sheet1", "B1", req.EmployeeName)
	file.SetCellValue("Sheet1", "A2", "Pay Period")
	file.SetCellValue("Sheet1", "B2", req.PayPeriodNum)
	file.SetCellValue("Sheet1", "A3", "Year")
	file.SetCellValue("Sheet1", "B3", req.Year)
	file.SetActiveSheet(index)

	// Additional example: write weeks and entries if present
	row := 5
	for _, week := range req.Weeks {
		file.SetCellValue("Sheet1", fmt.Sprintf("A%d", row), fmt.Sprintf("Week %d: %s", week.WeekNumber, week.WeekLabel))
		row++
		for _, entry := range week.Entries {
			file.SetCellValue("Sheet1", fmt.Sprintf("A%d", row), entry.Date)
			file.SetCellValue("Sheet1", fmt.Sprintf("B%d", row), entry.JobCode)
			file.SetCellValue("Sheet1", fmt.Sprintf("C%d", row), entry.Hours)
			file.SetCellValue("Sheet1", fmt.Sprintf("D%d", row), entry.Overtime)
			file.SetCellValue("Sheet1", fmt.Sprintf("E%d", row), entry.IsNightShift)
			row++
		}
		row++
	}

	dir := os.TempDir()
	timestamp := time.Now().Format("20060102_150405")
	xlsxPath := filepath.Join(dir, fmt.Sprintf("timecard_%s_%s.xlsx", req.EmployeeName, timestamp))
	if err := file.SaveAs(xlsxPath); err != nil {
		respondErr(w, err)
		return
	}
	xlsxBytes, err := os.ReadFile(xlsxPath)
	if err != nil {
		respondErr(w, err)
		return
	}
	resp := TimecardResponse{
		Success:    true,
		XLSXBase64: base64.StdEncoding.EncodeToString(xlsxBytes),
	}

	if req.IncludePDF {
		pdfPath := filepath.Join(dir, fmt.Sprintf("timecard_%s_%s.pdf", req.EmployeeName, timestamp))
		if err := convertXLSXToPDF(xlsxPath, pdfPath); err != nil {
			respondErr(w, err)
			return
		}
		pdfBytes, err := os.ReadFile(pdfPath)
		if err != nil {
			respondErr(w, err)
			return
		}
		resp.PDFBase64 = base64.StdEncoding.EncodeToString(pdfBytes)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func respondErr(w http.ResponseWriter, err error) {
	resp := TimecardResponse{Success: false, Error: err.Error()}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusInternalServerError)
	json.NewEncoder(w).Encode(resp)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	cmd := exec.Command("libreoffice", "--version")
	if err := cmd.Run(); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte(`{"status": "libreoffice not available"}`))
		return
	}
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status": "ok"}`))
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// SMTP environment variables configuration (compatible with SendGrid):
	// SMTP_HOST, SMTP_PORT, SMTP_USER ("apikey"), SMTP_PASS (SendGrid API key)
	log.Printf("SMTP configuration: host=%s port=%s user=%s (SendGrid compatible)", os.Getenv("SMTP_HOST"), os.Getenv("SMTP_PORT"), os.Getenv("SMTP_USER"))

	http.HandleFunc("/api/generate-timecard", generateTimecardHandler)
	http.HandleFunc("/health", healthHandler)
	log.Printf("Server listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
