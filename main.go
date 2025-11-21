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
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"net/smtp"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
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
	SendEmail       bool       `json:"send_email"`
	EmailTo         string     `json:"email_to,omitempty"`
	EmailFrom       string     `json:"email_from,omitempty"`
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

func convertXLSXToPDFViaGotenberg(xlsxPath, pdfPath string) error {
	gotenbergURL := os.Getenv("GOTENBERG_URL")
	if gotenbergURL == "" {
		gotenbergURL = "http://localhost:3000"
	}

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	file, err := os.Open(xlsxPath)
	if err != nil {
		return fmt.Errorf("failed to open XLSX file: %v", err)
	}
	defer file.Close()

	part, err := writer.CreateFormFile("files", filepath.Base(xlsxPath))
	if err != nil {
		return fmt.Errorf("failed to create form file part: %v", err)
	}

	if _, err = io.Copy(part, file); err != nil {
		return fmt.Errorf("failed to copy XLSX file into form: %v", err)
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("failed to close multipart writer: %v", err)
	}

	req, err := http.NewRequest("POST", gotenbergURL+"/forms/libreoffice/convert", body)
	if err != nil {
		return fmt.Errorf("failed to create HTTP request: %v", err)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	client := &http.Client{Timeout: 2 * time.Minute}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("gotenberg request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("gotenberg returned status %d: %s", resp.StatusCode, string(respBody))
	}

	pdfBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read gotenberg response body: %v", err)
	}

	if err := os.WriteFile(pdfPath, pdfBytes, 0644); err != nil {
		return fmt.Errorf("failed to write PDF file: %v", err)
	}

	return nil
}

func convertXLSXToPDF(xlsxPath, pdfPath string) error {
	var stdout, stderr bytes.Buffer
	outDir := filepath.Dir(pdfPath)

	cmd := exec.Command("libreoffice", "--headless", "--convert-to", "pdf", "--outdir", outDir, xlsxPath)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("libreoffice conversion failed: %v, stderr: %s, stdout: %s", err, stderr.String(), stdout.String())
	}

	// LibreOffice creates a PDF with the same base name as the input XLSX file
	xlsxBaseName := filepath.Base(xlsxPath)
	pdfBaseName := xlsxBaseName[:len(xlsxBaseName)-len(filepath.Ext(xlsxBaseName))] + ".pdf"
	generatedPDFPath := filepath.Join(outDir, pdfBaseName)

	// Wait a bit for file system to sync (especially important on some cloud environments)
	time.Sleep(100 * time.Millisecond)

	// Verify the PDF was created
	if _, err := os.Stat(generatedPDFPath); os.IsNotExist(err) {
		return fmt.Errorf("PDF was not generated at expected path: %s", generatedPDFPath)
	}

	// If the generated PDF path differs from the desired path, rename it
	if generatedPDFPath != pdfPath {
		if err := os.Rename(generatedPDFPath, pdfPath); err != nil {
			return fmt.Errorf("failed to rename PDF from %s to %s: %v", generatedPDFPath, pdfPath, err)
		}
	}

	log.Printf("Successfully converted %s to %s", xlsxPath, pdfPath)
	return nil
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

		err := convertXLSXToPDFViaGotenberg(xlsxPath, pdfPath)
		if err != nil {
			log.Printf("Gotenberg PDF conversion failed for %s: %v", req.EmployeeName, err)
			err = convertXLSXToPDF(xlsxPath, pdfPath)
			if err != nil {
				log.Printf("LibreOffice PDF conversion fallback failed for %s: %v", req.EmployeeName, err)
				respondErr(w, fmt.Errorf("PDF conversion failed: %v", err))
				return
			}
		}

		pdfBytes, err := os.ReadFile(pdfPath)
		if err != nil {
			log.Printf("Failed to read PDF file %s: %v", pdfPath, err)
			respondErr(w, fmt.Errorf("failed to read generated PDF: %v", err))
			return
		}
		resp.PDFBase64 = base64.StdEncoding.EncodeToString(pdfBytes)
		log.Printf("Successfully generated PDF for %s (%d bytes)", req.EmployeeName, len(pdfBytes))

		// Send email if requested
		if req.SendEmail && req.EmailTo != "" {
			emailFrom := req.EmailFrom
			if emailFrom == "" {
				emailFrom = "noreply@yourdomain.com" // Default sender
			}

			attachments := make(map[string][]byte)
			attachments[fmt.Sprintf("timecard_%s_%s.xlsx", req.EmployeeName, timestamp)] = xlsxBytes
			attachments[fmt.Sprintf("timecard_%s_%s.pdf", req.EmployeeName, timestamp)] = pdfBytes

			subject := fmt.Sprintf("Timecard for %s - Pay Period %d, %d", req.EmployeeName, req.PayPeriodNum, req.Year)
			body := fmt.Sprintf("Please find attached the timecard for %s.\n\nPay Period: %d\nYear: %d\n\nBoth XLSX and PDF formats are attached.",
				req.EmployeeName, req.PayPeriodNum, req.Year)

			if err := sendEmailWithAttachments(req.EmailTo, emailFrom, subject, body, attachments); err != nil {
				log.Printf("Failed to send email to %s: %v", req.EmailTo, err)
				// Don't fail the whole request if email fails
			}
		}

		// Optional: Clean up temp files
		defer func() {
			os.Remove(xlsxPath)
			os.Remove(pdfPath)
		}()
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
	gotenbergURL := os.Getenv("GOTENBERG_URL")
	if gotenbergURL == "" {
		gotenbergURL = "http://localhost:3000"
	}

	gotenbergStatus := "unavailable"
	gotenbergErr := ""
	gotenbergClient := &http.Client{Timeout: 3 * time.Second}
	gotenbergResp, err := gotenbergClient.Get(gotenbergURL + "/health")
	if err == nil && gotenbergResp.StatusCode == http.StatusOK {
		gotenbergStatus = "ok"
	} else {
		if err != nil {
			gotenbergErr = err.Error()
		} else if gotenbergResp != nil {
			bodyBytes, _ := io.ReadAll(gotenbergResp.Body)
			gotenbergErr = fmt.Sprintf("status %d: %s", gotenbergResp.StatusCode, strings.TrimSpace(string(bodyBytes)))
		}
	}
	if gotenbergResp != nil {
		gotenbergResp.Body.Close()
	}

	var stdout, stderr bytes.Buffer
	cmd := exec.Command("libreoffice", "--version")
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		log.Printf("LibreOffice health check failed: %v, stderr: %s", err, stderr.String())
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte(fmt.Sprintf(`{"gotenberg":"%s","libreoffice_version":"%s","status":"libreoffice not available","error":"%s","gotenberg_error":"%s"}`, gotenbergStatus, "", err.Error(), gotenbergErr)))
		return
	}

	version := strings.TrimSpace(stdout.String())
	log.Printf("LibreOffice health check passed: %s", version)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf(`{"gotenberg":"%s","libreoffice_version":"%s","status":"ok","gotenberg_error":"%s"}`, gotenbergStatus, version, gotenbergErr)))
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	gotenbergURL := os.Getenv("GOTENBERG_URL")
	if gotenbergURL == "" {
		gotenbergURL = "http://localhost:3000"
	}
	log.Printf("Gotenberg URL configured as: %s", gotenbergURL)

	// SMTP environment variables configuration (compatible with SendGrid):
	// SMTP_HOST, SMTP_PORT, SMTP_USER ("apikey"), SMTP_PASS (SendGrid API key)
	log.Printf("SMTP configuration: host=%s port=%s user=%s (SendGrid compatible)", os.Getenv("SMTP_HOST"), os.Getenv("SMTP_PORT"), os.Getenv("SMTP_USER"))

	http.HandleFunc("/api/generate-timecard", generateTimecardHandler)
	http.HandleFunc("/health", healthHandler)
	log.Printf("Server listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

// sendEmailWithAttachments sends an email with file attachments using SMTP credentials from environment variables.
// SMTP_USER must be "apikey" and SMTP_PASS should be your SendGrid API key for SendGrid compatibility.
func sendEmailWithAttachments(to, from, subject, body string, attachments map[string][]byte) error {
	smtpHost := os.Getenv("SMTP_HOST")
	smtpPort := os.Getenv("SMTP_PORT")
	smtpUser := os.Getenv("SMTP_USER")
	smtpPass := os.Getenv("SMTP_PASS")

	if smtpHost == "" || smtpPort == "" || smtpUser == "" || smtpPass == "" {
		return fmt.Errorf("SMTP configuration incomplete: ensure SMTP_HOST, SMTP_PORT, SMTP_USER, and SMTP_PASS are set")
	}

	log.Printf("Attempting to send email via %s:%s to %s", smtpHost, smtpPort, to)

	// Build email message with MIME multipart
	boundary := "----=_NextPart_000_0000_01D00000.00000000"

	var emailBuffer bytes.Buffer
	emailBuffer.WriteString(fmt.Sprintf("From: %s\r\n", from))
	emailBuffer.WriteString(fmt.Sprintf("To: %s\r\n", to))
	emailBuffer.WriteString(fmt.Sprintf("Subject: %s\r\n", subject))
	emailBuffer.WriteString("MIME-Version: 1.0\r\n")
	emailBuffer.WriteString(fmt.Sprintf("Content-Type: multipart/mixed; boundary=\"%s\"\r\n\r\n", boundary))

	// Email body
	emailBuffer.WriteString(fmt.Sprintf("--%s\r\n", boundary))
	emailBuffer.WriteString("Content-Type: text/plain; charset=\"utf-8\"\r\n")
	emailBuffer.WriteString("Content-Transfer-Encoding: 7bit\r\n\r\n")
	emailBuffer.WriteString(body)
	emailBuffer.WriteString("\r\n\r\n")

	// Add attachments
	for filename, fileData := range attachments {
		emailBuffer.WriteString(fmt.Sprintf("--%s\r\n", boundary))

		// Determine content type based on file extension
		contentType := "application/octet-stream"
		if filepath.Ext(filename) == ".pdf" {
			contentType = "application/pdf"
		} else if filepath.Ext(filename) == ".xlsx" {
			contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
		}

		emailBuffer.WriteString(fmt.Sprintf("Content-Type: %s; name=\"%s\"\r\n", contentType, filename))
		emailBuffer.WriteString(fmt.Sprintf("Content-Disposition: attachment; filename=\"%s\"\r\n", filename))
		emailBuffer.WriteString("Content-Transfer-Encoding: base64\r\n\r\n")

		encoded := base64.StdEncoding.EncodeToString(fileData)
		// Split into 76-character lines per RFC 2045
		for i := 0; i < len(encoded); i += 76 {
			end := i + 76
			if end > len(encoded) {
				end = len(encoded)
			}
			emailBuffer.WriteString(encoded[i:end])
			emailBuffer.WriteString("\r\n")
		}
	}

	emailBuffer.WriteString(fmt.Sprintf("--%s--\r\n", boundary))

	// Send via SMTP with better error handling
	auth := smtp.PlainAuth("", smtpUser, smtpPass, smtpHost)
	addr := fmt.Sprintf("%s:%s", smtpHost, smtpPort)

	log.Printf("Connecting to SMTP server at %s", addr)
	err := smtp.SendMail(addr, auth, from, []string{to}, emailBuffer.Bytes())
	if err != nil {
		log.Printf("SMTP send failed: %v", err)
		return fmt.Errorf("failed to send email: %v", err)
	}

	log.Printf("Email sent successfully to %s with %d attachment(s)", to, len(attachments))
	return nil
}
