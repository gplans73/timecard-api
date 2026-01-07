package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/smtp"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/xuri/excelize/v2"
)

// Data structures for timecard requests
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

// EmailTimecardRequest for the email endpoint
type EmailTimecardRequest struct {
	TimecardRequest
	To      string  `json:"to"`
	CC      *string `json:"cc,omitempty"`
	Subject string  `json:"subject"`
	Body    string  `json:"body"`
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Log template info at startup
	logTemplateInfo()

	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/api/generate-timecard", corsMiddleware(generateTimecardHandler))
	http.HandleFunc("/api/email-timecard", corsMiddleware(emailTimecardHandler))

	log.Printf("Server starting on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

func logTemplateInfo() {
	templatePath := "template.xlsx"
	data, err := os.ReadFile(templatePath)
	if err != nil {
		log.Printf("TEMPLATE startup: ERROR reading template: %v", err)
		return
	}

	hash := sha256.Sum256(data)
	hashStr := fmt.Sprintf("%x", hash)

	f, err := excelize.OpenFile(templatePath)
	if err != nil {
		log.Printf("TEMPLATE startup: ERROR opening template: %v", err)
		return
	}
	defer f.Close()

	sheets := f.GetSheetList()

	// Check marker cells
	markers := make(map[string]string)
	for _, sheet := range sheets {
		a3, _ := f.GetCellValue(sheet, "A3")
		ad3, _ := f.GetCellValue(sheet, "AD3")
		markers[sheet+"!A3"] = a3
		markers[sheet+"!AD3"] = ad3
	}

	commit := os.Getenv("RENDER_GIT_COMMIT")
	if commit == "" {
		commit = "unknown"
	}

	log.Printf("TEMPLATE startup: OK path=%s size=%d sha256=%s sheets=%v markers=%v commit=%s",
		templatePath, len(data), hashStr, sheets, markers, commit)
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

		if r.Method == http.MethodOptions {
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
		getOnCallDailyAmount(req), getOnCallPerCallAmount(req))

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

func getOnCallDailyAmount(req TimecardRequest) float64 {
	if req.OnCallDailyAmount != nil {
		return *req.OnCallDailyAmount
	}
	return 300.0
}

func getOnCallPerCallAmount(req TimecardRequest) float64 {
	if req.OnCallPerCallAmount != nil {
		return *req.OnCallPerCallAmount
	}
	return 50.0
}

func generateExcelFile(req TimecardRequest) ([]byte, error) {
	templatePath := "template.xlsx"
	f, err := excelize.OpenFile(templatePath)
	if err != nil {
		log.Printf("Warning: Template not found, creating basic file: %v", err)
		return generateBasicExcelFile(req)
	}
	defer f.Close()

	// If Weeks isn't provided, build Week 1/Week 2 from Entries
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
			log.Printf("Warning: Week %d requested but only %d sheets available, using sheet 0",
				weekData.WeekNumber, len(sheets))
			sheetIndex = 0
		}

		sheetName := sheets[sheetIndex]

		// Log marker cells before filling
		a3Before, _ := f.GetCellValue(sheetName, "A3")
		ad3Before, _ := f.GetCellValue(sheetName, "AD3")
		log.Printf("MARKER BEFORE fill: sheet=%s A3=%q AD3=%q", sheetName, a3Before, ad3Before)

		log.Printf("Filling sheet '%s' with Week %d data (%d entries)",
			sheetName, weekData.WeekNumber, len(weekData.Entries))

		err = fillWeekSheet(f, sheetName, req, weekData, weekData.WeekNumber)
		if err != nil {
			log.Printf("Error filling Week %d: %v", weekData.WeekNumber, err)
		}
		// Ensure template formatting (borders/column widths) stays intact after writing values
		if err == nil {
			if ferr := fixSheetFormatting(f, sheetName); ferr != nil {
				log.Printf("Warning: formatting fix failed for sheet %s: %v", sheetName, ferr)
			}
		}

		// Log marker cells after filling
		a3After, _ := f.GetCellValue(sheetName, "A3")
		ad3After, _ := f.GetCellValue(sheetName, "AD3")
		log.Printf("MARKER AFTER fill: sheet=%s A3=%q AD3=%q", sheetName, a3After, ad3After)
	}

	// Prevent Excel "We found a problem with some content" repair prompts.
	// When Excel repairs, it can strip borders/styles. Removing calcChain is a
	// well-known fix when generating XLSX via excelize.
	_ = f.DeleteCalcChain()

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

	// Build job code -> job name map for On Call detection
	jobNameMap := make(map[string]string)
	for _, job := range req.Jobs {
		jobNameMap[job.JobCode] = job.JobName
	}

	// Header info
	f.SetCellValue(sheetName, "M2", req.EmployeeName)
	f.SetCellValue(sheetName, "AJ2", req.PayPeriodNum)
	f.SetCellValue(sheetName, "AJ3", req.Year)

	excelDate := timeToExcelDate(weekStart)
	f.SetCellValue(sheetName, "B4", excelDate)
	f.SetCellValue(sheetName, "AJ4", weekData.WeekLabel)

	// Write On Call rate cells used by template formulas
	// AM12 = Daily On Call rate, AM13 = Per Call rate
	onCallDailyAmount := getOnCallDailyAmount(req)
	onCallPerCallAmount := getOnCallPerCallAmount(req)

	f.SetCellValue(sheetName, "AM12", onCallDailyAmount)
	f.SetCellValue(sheetName, "AM13", onCallPerCallAmount)

	log.Printf("  On Call rates written: AM12=$%.2f (daily), AM13=$%.2f (perCall)",
		onCallDailyAmount, onCallPerCallAmount)

	// Column layout
	codeColumns := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
	jobColumns := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}

	// Get unique column keys for regular and overtime entries
	regularCols := getUniqueColumnsForType(weekData.Entries, false, jobNameMap)
	overtimeCols := getUniqueColumnsForType(weekData.Entries, true, jobNameMap)

	// Fill Regular headers (Row 4) - only write to cells we need, don't clear others
	for i, colKey := range regularCols {
		if i >= len(codeColumns) {
			break
		}
		isNight, jobCode, labourCode, jobName := splitColumnKey(colKey)

		labourToWrite := labourCode
		if isNight && labourToWrite != "" {
			labourToWrite = "N" + labourToWrite
		}
		// If this is an On Call job, write "On Call" to the labour code column
		if strings.EqualFold(jobName, "On Call") {
			labourToWrite = "On Call"
		}

		f.SetCellValue(sheetName, codeColumns[i]+"4", labourToWrite)
		f.SetCellValue(sheetName, jobColumns[i]+"4", jobCode)
		log.Printf("  REG header col %d: labour='%s' job='%s' (key='%s')", i, labourToWrite, jobCode, colKey)
	}

	// Fill Overtime headers (Row 15) - only write to cells we need
	for i, colKey := range overtimeCols {
		if i >= len(codeColumns) {
			break
		}
		isNight, jobCode, labourCode, jobName := splitColumnKey(colKey)

		labourToWrite := labourCode
		if isNight && labourToWrite != "" {
			labourToWrite = "N" + labourToWrite
		}
		if strings.EqualFold(jobName, "On Call") {
			labourToWrite = "On Call"
		}

		f.SetCellValue(sheetName, codeColumns[i]+"15", labourToWrite)
		f.SetCellValue(sheetName, jobColumns[i]+"15", jobCode)
		log.Printf("  OT header col %d: labour='%s' job='%s' (key='%s')", i, labourToWrite, jobCode, colKey)
	}

	// Organize entries by date+column
	regularTimeEntries := make(map[string]map[string]float64)
	overtimeEntries := make(map[string]map[string]float64)

	for _, entry := range weekData.Entries {
		entryDate, err := time.Parse(time.RFC3339, entry.Date)
		if err != nil {
			continue
		}

		dateKey := entryDate.Format("2006-01-02")
		colKey := columnKey(entry, jobNameMap)

		log.Printf("  Processing entry: date=%s, job='%s', labour='%s', hours=%.2f, OT=%v, night=%v => key='%s'",
			dateKey, entry.JobCode, entry.LabourCode, entry.Hours, entry.Overtime, entry.IsNightShift, colKey)

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

	// Fill each day
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
				if hours, ok := regularHours[k]; ok && hours > 0 {
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
				if hours, ok := otHours[k]; ok && hours > 0 {
					cellRef := fmt.Sprintf("%s%d", jobColumns[i], overtimeRow)
					f.SetCellValue(sheetName, cellRef, hours)
				}
			}
		}
	}

	log.Printf("=== Week %d completed ===", weekNum)
	return nil
}

func columnKey(e Entry, jobNameMap map[string]string) string {
	jobCode := strings.TrimSpace(e.JobCode)
	labourCode := strings.TrimSpace(e.LabourCode)
	jobName := jobNameMap[jobCode]

	base := fmt.Sprintf("%s|%s|%s", jobCode, labourCode, jobName)
	if e.IsNightShift {
		return "N-" + base
	}
	return base
}

func splitColumnKey(k string) (bool, string, string, string) {
	isNight := strings.HasPrefix(k, "N-")
	if isNight {
		k = strings.TrimPrefix(k, "N-")
	}
	parts := strings.SplitN(k, "|", 3)
	jobCode := ""
	labourCode := ""
	jobName := ""
	if len(parts) > 0 {
		jobCode = parts[0]
	}
	if len(parts) > 1 {
		labourCode = parts[1]
	}
	if len(parts) > 2 {
		jobName = parts[2]
	}
	return isNight, jobCode, labourCode, jobName
}

func getUniqueColumnsForType(entries []Entry, isOvertime bool, jobNameMap map[string]string) []string {
	seen := make(map[string]bool)
	var result []string

	for _, entry := range entries {
		if entry.Overtime != isOvertime {
			continue
		}
		k := columnKey(entry, jobNameMap)
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
	return duration.Hours() / 24.0
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

		jobName := jobMap[entry.JobCode]
		if strings.EqualFold(jobName, "On Call") {
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
		f.SetCellValue(sheet, fmt.Sprintf("E%d", row), getOnCallDailyAmount(req))
		row++
		f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "# of On Call:")
		f.SetCellValue(sheet, fmt.Sprintf("B%d", row), onCallCount)
		f.SetCellValue(sheet, fmt.Sprintf("D%d", row), "Total:")
		f.SetCellValue(sheet, fmt.Sprintf("E%d", row), getOnCallPerCallAmount(req)*float64(onCallCount))
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

	recipients := splitAndTrim(to)
	var ccRecipients []string
	if cc != nil && *cc != "" {
		ccRecipients = splitAndTrim(*cc)
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

func splitAndTrim(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		t := strings.TrimSpace(p)
		if t != "" {
			out = append(out, t)
		}
	}
	return out
}

func getEnvFloat(key string) (*float64, error) {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return nil, nil
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil {
		return nil, err
	}
	return &f, nil
}


// fixSheetFormatting reapplies key cell styles from the template after values are written.
// This is a defensive workaround for cases where some Excel viewers / converters (or an Excel repair step)
// drop borders/column widths when opening a modified workbook.
func fixSheetFormatting(f *excelize.File, sheetName string) error {
	// 1) Widen summary value column so formulas don't show ### when totals are large.
	// (Template is tight; totals like 900 can overflow.)
	if err := f.SetColWidth(sheetName, "AK", "AK", 12); err != nil {
		return err
	}

	// 2) Re-apply the grid style for the main entry tables (Regular + OT)
	// Grab a "known good" grid cell style from the template.
	gridStyle, err := f.GetCellStyle(sheetName, "C5")
	if err != nil {
		return err
	}
	// Regular Time grid: C5:AI11
	if err := f.SetCellStyle(sheetName, "C5", "AI11", gridStyle); err != nil {
		return err
	}
	// Overtime grid: C16:AI22
	if err := f.SetCellStyle(sheetName, "C16", "AI22", gridStyle); err != nil {
		return err
	}

	// 3) Re-apply date/day styles to the left columns (keeps borders and date format)
	dayStyle, err := f.GetCellStyle(sheetName, "A5")
	if err != nil {
		return err
	}
	dateStyle, err := f.GetCellStyle(sheetName, "B5")
	if err != nil {
		return err
	}
	if err := f.SetCellStyle(sheetName, "A5", "A11", dayStyle); err != nil {
		return err
	}
	if err := f.SetCellStyle(sheetName, "B5", "B11", dateStyle); err != nil {
		return err
	}
	if err := f.SetCellStyle(sheetName, "A16", "A22", dayStyle); err != nil {
		return err
	}
	if err := f.SetCellStyle(sheetName, "B16", "B22", dateStyle); err != nil {
		return err
	}

	return nil
}

