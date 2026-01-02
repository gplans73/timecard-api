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
	EmployeeName        string       `json:"employee_name"`
	PayPeriodNum        int          `json:"pay_period_num"`
	Year                int          `json:"year"`
	WeekStartDate       string       `json:"week_start_date"`
	WeekNumberLabel     string       `json:"week_number_label"`
	Jobs                []Job        `json:"jobs"`
	Entries             []Entry      `json:"entries"`
	Weeks               []WeekData   `json:"weeks,omitempty"`
	LabourCodes         []LabourCode `json:"labour_codes,omitempty"`
	OnCallDailyAmount   *float64     `json:"on_call_daily_amount,omitempty"`
	OnCallPerCallAmount *float64     `json:"on_call_per_call_amount,omitempty"`
}

// GetOnCallDailyAmount returns the on-call daily amount, defaulting to 300 if not set
func (r *TimecardRequest) GetOnCallDailyAmount() float64 {
	if r.OnCallDailyAmount != nil {
		return *r.OnCallDailyAmount
	}
	return 300.0
}

// GetOnCallPerCallAmount returns the per-call amount, defaulting to 50 if not set
func (r *TimecardRequest) GetOnCallPerCallAmount() float64 {
	if r.OnCallPerCallAmount != nil {
		return *r.OnCallPerCallAmount
	}
	return 50.0
}

type Job struct {
	JobCode string `json:"job_code"`
	JobName string `json:"job_name"`
}

type LabourCode struct {
	Code string `json:"code"`
	Name string `json:"name"`
}

type Entry struct {
	Date         string  `json:"date"`
	JobCode      string  `json:"job_code"`
	LabourCode   string  `json:"labour_code"`
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
	log.Printf("On-Call Daily Amount: $%.2f, Per-Call Amount: $%.2f",
		req.GetOnCallDailyAmount(), req.GetOnCallPerCallAmount())

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
		log.Printf("Warning: Template not found, creating basic file: %v", err)
		return generateBasicExcelFile(req)
	}
	defer f.Close()

	// Normalize weeks if needed
	if len(req.Weeks) == 0 && len(req.Entries) > 0 {
		var week1Start time.Time
		var parseErr error
		if req.WeekStartDate != "" {
			week1Start, parseErr = time.Parse(time.RFC3339, req.WeekStartDate)
		}
		if parseErr != nil || req.WeekStartDate == "" {
			earliest := time.Now().UTC()
			for _, e := range req.Entries {
				if t, err := time.Parse(time.RFC3339, e.Date); err == nil {
					if t.Before(earliest) {
						earliest = t
					}
				}
			}
			wd := int(earliest.Weekday())
			week1Start = time.Date(earliest.Year(), earliest.Month(), earliest.Day()-wd, 0, 0, 0, 0, time.UTC)
		}
		week2Start := week1Start.AddDate(0, 0, 7)

		w1 := WeekData{WeekNumber: 1, WeekStartDate: week1Start.Format(time.RFC3339), WeekLabel: "Week 1"}
		w2 := WeekData{WeekNumber: 2, WeekStartDate: week2Start.Format(time.RFC3339), WeekLabel: "Week 2"}

		for _, e := range req.Entries {
			t, err := time.Parse(time.RFC3339, e.Date)
			if err != nil {
				continue
			}
			if !t.Before(week2Start) {
				w2.Entries = append(w2.Entries, e)
			} else {
				w1.Entries = append(w1.Entries, e)
			}
		}
		if len(w1.Entries) > 0 {
			req.Weeks = append(req.Weeks, w1)
		}
		if len(w2.Entries) > 0 {
			req.Weeks = append(req.Weeks, w2)
		}
	}

	sheets := f.GetSheetList()
	if len(sheets) == 0 {
		return nil, fmt.Errorf("no sheets found in template")
	}

	log.Printf("Template has %d sheets: %v", len(sheets), sheets)

	for _, weekData := range req.Weeks {
		sheetIndex := weekData.WeekNumber - 1

		if sheetIndex < 0 || sheetIndex >= len(sheets) {
			log.Printf("Warning: Week %d requested but only %d sheets available, using sheet 0", weekData.WeekNumber, len(sheets))
			sheetIndex = 0
		}

		sheetName := sheets[sheetIndex]
		log.Printf("Filling sheet '%s' with Week %d data (%d entries)",
			sheetName, weekData.WeekNumber, len(weekData.Entries))

		err = fillWeekSheet(f, sheetName, req, weekData, weekData.WeekNumber)
		if err != nil {
			log.Printf("Error filling Week %d: %v", weekData.WeekNumber, err)
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

	// Fill header information
	f.SetCellValue(sheetName, "M2", req.EmployeeName)
	f.SetCellValue(sheetName, "AJ2", req.PayPeriodNum)
	f.SetCellValue(sheetName, "AJ3", req.Year)

	excelDate := timeToExcelDate(weekStart)
	f.SetCellValue(sheetName, "B4", excelDate)
	f.SetCellValue(sheetName, "AJ4", weekData.WeekLabel)

	// ============================================================
	// IMPORTANT: Write On Call rate cells that the template formulas reference
	// AL1 = Daily On Call rate (referenced by AK12 formula)
	// AM1 = Per Call rate (referenced by AK13 formula)
	// ============================================================
	onCallDailyAmount := req.GetOnCallDailyAmount()
	onCallPerCallAmount := req.GetOnCallPerCallAmount()

	f.SetCellValue(sheetName, "AL1", onCallDailyAmount)
	f.SetCellValue(sheetName, "AM1", onCallPerCallAmount)

	log.Printf("  On Call rates written: AL1=$%.2f (daily), AM1=$%.2f (perCall)",
		onCallDailyAmount, onCallPerCallAmount)
	// ============================================================

	codeColumns := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
	jobColumns := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}

	regularCols := getUniqueColumnsForType(weekData.Entries, false)
	overtimeCols := getUniqueColumnsForType(weekData.Entries, true)

	// Clear and fill regular time headers (Row 4)
	for i := 0; i < len(regularCols) && i < len(codeColumns); i++ {
		f.SetCellValue(sheetName, codeColumns[i]+"4", "")
		f.SetCellValue(sheetName, jobColumns[i]+"4", "")
	}

	for i, colKey := range regularCols {
		if i >= len(codeColumns) {
			break
		}
		isNight, job, labour := splitColumnKey(colKey)
		labourToWrite := labour
		if isNight && labourToWrite != "" {
			labourToWrite = "N" + labourToWrite
		}
		f.SetCellValue(sheetName, codeColumns[i]+"4", labourToWrite)
		f.SetCellValue(sheetName, jobColumns[i]+"4", job)
	}

	// Clear and fill overtime headers (Row 15)
	for i := 0; i < len(overtimeCols) && i < len(codeColumns); i++ {
		f.SetCellValue(sheetName, codeColumns[i]+"15", "")
		f.SetCellValue(sheetName, jobColumns[i]+"15", "")
	}

	for i, colKey := range overtimeCols {
		if i >= len(codeColumns) {
			break
		}
		isNight, job, labour := splitColumnKey(colKey)
		labourToWrite := labour
		if isNight && labourToWrite != "" {
			labourToWrite = "N" + labourToWrite
		}
		f.SetCellValue(sheetName, codeColumns[i]+"15", labourToWrite)
		f.SetCellValue(sheetName, jobColumns[i]+"15", job)
	}

	// Organize entries by date and column key
	regularTimeEntries := make(map[string]map[string]float64)
	overtimeEntries := make(map[string]map[string]float64)

	for _, entry := range weekData.Entries {
		entryDate, err := time.Parse(time.RFC3339, entry.Date)
		if err != nil {
			continue
		}

		dateKey := entryDate.Format("2006-01-02")
		job := strings.TrimSpace(entry.JobCode)
		labour := strings.TrimSpace(entry.LabourCode)

		colKey := fmt.Sprintf("%s|%s", job, labour)
		if entry.IsNightShift {
			colKey = "N-" + colKey
		}

		if entry.Overtime {
			if overtimeEntries[dateKey] == nil {
				overtimeEntries[dateKey] = make(map[string]float64)
			}
			overtimeEntries[dateKey][colKey] += entry.Hours
		} else {
			if regularTimeEntries[dateKey] == nil {
				regularTimeEntries[dateKey] = make(map[string]float64)
			}
			regularTimeEntries[dateKey][colKey] += entry.Hours
		}
	}

	// Fill hours data for each day
	for dayOffset := 0; dayOffset < 7; dayOffset++ {
		currentDate := weekStart.AddDate(0, 0, dayOffset)
		dateKey := currentDate.Format("2006-01-02")
		excelDateSerial := timeToExcelDate(currentDate)

		regularRow := 5 + dayOffset
		overtimeRow := 16 + dayOffset

		f.SetCellValue(sheetName, fmt.Sprintf("B%d", regularRow), excelDateSerial)
		f.SetCellValue(sheetName, fmt.Sprintf("B%d", overtimeRow), excelDateSerial)

		if regularHours, exists := regularTimeEntries[dateKey]; exists {
			for i, k := range regularCols {
				if i >= len(jobColumns) {
					break
				}
				if hours, hasHours := regularHours[k]; hasHours && hours > 0 {
					cellRef := fmt.Sprintf("%s%d", jobColumns[i], regularRow)
					f.SetCellValue(sheetName, cellRef, hours)
				}
			}
		}

		if otHours, exists := overtimeEntries[dateKey]; exists {
			for i, k := range overtimeCols {
				if i >= len(jobColumns) {
					break
				}
				if hours, hasHours := otHours[k]; hasHours && hours > 0 {
					cellRef := fmt.Sprintf("%s%d", jobColumns[i], overtimeRow)
					f.SetCellValue(sheetName, cellRef, hours)
				}
			}
		}
	}

	log.Printf("=== Week %d completed ===", weekNum)
	return nil
}

func columnKey(e Entry) string {
	base := fmt.Sprintf("%s|%s", strings.TrimSpace(e.JobCode), strings.TrimSpace(e.LabourCode))
	if e.IsNightShift {
		return "N-" + base
	}
	return base
}

func splitColumnKey(k string) (bool, string, string) {
	isNight := strings.HasPrefix(k, "N-")
	if isNight {
		k = strings.TrimPrefix(k, "N-")
	}
	parts := strings.SplitN(k, "|", 2)
	job := ""
	labour := ""
	if len(parts) > 0 {
		job = parts[0]
	}
	if len(parts) > 1 {
		labour = parts[1]
	}
	return isNight, job, labour
}

func getUniqueColumnsForType(entries []Entry, isOvertime bool) []string {
	seen := make(map[string]bool)
	var result []string

	for _, entry := range entries {
		if entry.Overtime != isOvertime {
			continue
		}
		k := columnKey(entry)
		if !seen[k] {
			seen[k] = true
			result = append(result, k)
		}
	}

	return result
}

func timeToExcelDate(t time.Time) float64 {
	excelEpoch := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
	duration := t.Sub(excelEpoch)
	days := duration.Hours() / 24.0
	return days
}

func generateBasicExcelFile(req TimecardRequest) ([]byte, error) {
	f := excelize.NewFile()
	defer f.Close()

	sheet := "Sheet1"
	f.SetCellValue(sheet, "A1", "Employee Name:")
	f.SetCellValue(sheet, "B1", req.EmployeeName)
	f.SetCellValue(sheet, "A2", "Pay Period:")
	f.SetCellValue(sheet, "B2", req.PayPeriodNum)
	f.SetCellValue(sheet, "A3", "Year:")
	f.SetCellValue(sheet, "B3", req.Year)
	f.SetCellValue(sheet, "A4", "Week:")
	f.SetCellValue(sheet, "B4", req.WeekNumberLabel)

	f.SetCellValue(sheet, "A6", "Date")
	f.SetCellValue(sheet, "B6", "Job Code")
	f.SetCellValue(sheet, "C6", "Labour Code")
	f.SetCellValue(sheet, "D6", "Job Name")
	f.SetCellValue(sheet, "E6", "Hours")
	f.SetCellValue(sheet, "F6", "Overtime")

	jobMap := make(map[string]string)
	for _, job := range req.Jobs {
		jobMap[job.JobCode] = job.JobName
	}

	row := 7
	totalHours := 0.0
	totalOvertimeHours := 0.0
	onCallCount := 0

	for _, entry := range req.Entries {
		t, err := time.Parse(time.RFC3339, entry.Date)
		if err != nil {
			continue
		}

		f.SetCellValue(sheet, fmt.Sprintf("A%d", row), t.Format("2006-01-02"))

		jobCodeToWrite := entry.JobCode
		if entry.IsNightShift {
			jobCodeToWrite = "N" + jobCodeToWrite
		}
		f.SetCellValue(sheet, fmt.Sprintf("B%d", row), jobCodeToWrite)
		f.SetCellValue(sheet, fmt.Sprintf("C%d", row), entry.LabourCode)
		f.SetCellValue(sheet, fmt.Sprintf("D%d", row), jobMap[entry.JobCode])
		f.SetCellValue(sheet, fmt.Sprintf("E%d", row), entry.Hours)

		overtimeStr := "No"
		if entry.Overtime {
			overtimeStr = "Yes"
			totalOvertimeHours += entry.Hours
		}
		f.SetCellValue(sheet, fmt.Sprintf("F%d", row), overtimeStr)

		labourUpper := strings.ToUpper(entry.LabourCode)
		if labourUpper == "ON CALL" || labourUpper == "ONC" || labourUpper == "O/C" {
			onCallCount++
		}

		totalHours += entry.Hours
		row++
	}

	row++
	f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Hours:")
	f.SetCellValue(sheet, fmt.Sprintf("E%d", row), totalHours)
	row++
	f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Overtime:")
	f.SetCellValue(sheet, fmt.Sprintf("E%d", row), totalOvertimeHours)

	if onCallCount > 0 {
		row += 2
		f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "On Call Daily:")
		f.SetCellValue(sheet, fmt.Sprintf("E%d", row), req.GetOnCallDailyAmount())
		row++
		f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "# of On Call:")
		f.SetCellValue(sheet, fmt.Sprintf("B%d", row), onCallCount)
		f.SetCellValue(sheet, fmt.Sprintf("D%d", row), "Total:")
		f.SetCellValue(sheet, fmt.Sprintf("E%d", row), req.GetOnCallPerCallAmount()*float64(onCallCount))
	}

	buffer, err := f.WriteToBuffer()
	if err != nil {
		return nil, err
	}

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

	err := smtp.SendMail(addr, auth, fromEmail, allRecipients, []byte(message))
	if err != nil {
		return fmt.Errorf("failed to send email: %v", err)
	}

	log.Printf("Email sent successfully to %s", to)
	return nil
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
	buf.WriteString(fmt.Sprintf("Content-Type: multipart/mixed; boundary=\"%s\"\r\n", boundary))
	buf.WriteString("\r\n")

	buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
	buf.WriteString("Content-Type: text/plain; charset=\"utf-8\"\r\n")
	buf.WriteString("Content-Transfer-Encoding: quoted-printable\r\n")
	buf.WriteString("\r\n")
	buf.WriteString(body)
	buf.WriteString("\r\n\r\n")

	if len(attachment) > 0 {
		buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
		buf.WriteString("Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n")
		buf.WriteString(fmt.Sprintf("Content-Disposition: attachment; filename=\"%s\"\r\n", fileName))
		buf.WriteString("Content-Transfer-Encoding: base64\r\n")
		buf.WriteString("\r\n")

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
