package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/smtp"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/xuri/excelize/v2"
)

// -------------------------
// Data structures
// -------------------------

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

type EmailTimecardRequest struct {
	TimecardRequest
	To      string  `json:"to"`
	CC      *string `json:"cc,omitempty"`
	Subject string  `json:"subject"`
	Body    string  `json:"body"`
}

// -------------------------
// Template debug structures
// -------------------------

type TemplateInfo struct {
	Path           string            `json:"path"`
	SizeBytes      int64             `json:"size_bytes"`
	ModTimeUTC     string            `json:"mod_time_utc"`
	SHA256         string            `json:"sha256"`
	Sheets         []string          `json:"sheets"`
	Markers        map[string]string `json:"markers"`
	RenderGitCommit string           `json:"render_git_commit,omitempty"`
}

var (
	templatePath = "template.xlsx"
)

// -------------------------
// Main
// -------------------------

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Log template fingerprint at startup (shows in Render logs)
	if info, err := loadTemplateInfo(templatePath); err != nil {
		log.Printf("TEMPLATE startup: NOT OK (%s): %v", templatePath, err)
	} else {
		log.Printf("TEMPLATE startup: OK path=%s size=%d sha256=%s sheets=%v markers=%v commit=%s",
			info.Path, info.SizeBytes, info.SHA256, info.Sheets, info.Markers, info.RenderGitCommit)
	}

	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/api/template-info", corsMiddleware(templateInfoHandler))
	http.HandleFunc("/api/generate-timecard", corsMiddleware(generateTimecardHandler))
	http.HandleFunc("/api/email-timecard", corsMiddleware(emailTimecardHandler))

	log.Printf("Server starting on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

// -------------------------
// Handlers
// -------------------------

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func templateInfoHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	info, err := loadTemplateInfo(templatePath)
	if err != nil {
		http.Error(w, fmt.Sprintf("template info error: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(info)
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

	// Add debug headers so the app can confirm which deployment/template it hit
	if info, err := loadTemplateInfo(templatePath); err == nil {
		w.Header().Set("X-Template-Sha256", info.SHA256)
		w.Header().Set("X-Template-Size", fmt.Sprintf("%d", info.SizeBytes))
		if info.RenderGitCommit != "" {
			w.Header().Set("X-Render-Git-Commit", info.RenderGitCommit)
		}
	}

	w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"timecard_%s.xlsx\"", req.EmployeeName))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(excelData)

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
	_ = json.NewEncoder(w).Encode(response)
}

// -------------------------
// Template info helpers
// -------------------------

func loadTemplateInfo(path string) (*TemplateInfo, error) {
	fi, err := os.Stat(path)
	if err != nil {
		return nil, err
	}

	sha, err := sha256OfFile(path)
	if err != nil {
		return nil, err
	}

	x, err := excelize.OpenFile(path)
	if err != nil {
		return nil, err
	}
	defer x.Close()

	sheets := x.GetSheetList()

	// Marker cells you can change to whatever you want.
	// A3 is a common place for your "Regular Time Testing" if it's actually a cell.
	markers := map[string]string{
		"Week 1!A3":  safeCellValue(x, "Week 1", "A3"),
		"Week 2!A3":  safeCellValue(x, "Week 2", "A3"),
		"Week 1!AD3": safeCellValue(x, "Week 1", "AD3"),
		"Week 2!AD3": safeCellValue(x, "Week 2", "AD3"),
	}

	info := &TemplateInfo{
		Path:            path,
		SizeBytes:       fi.Size(),
		ModTimeUTC:      fi.ModTime().UTC().Format(time.RFC3339),
		SHA256:          sha,
		Sheets:          sheets,
		Markers:         markers,
		RenderGitCommit: os.Getenv("RENDER_GIT_COMMIT"),
	}
	return info, nil
}

func sha256OfFile(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func safeCellValue(f *excelize.File, sheet, cell string) string {
	if sheet == "" {
		return ""
	}
	if !sheetExists(f, sheet) {
		return ""
	}
	v, err := f.GetCellValue(sheet, cell)
	if err != nil {
		return ""
	}
	return v
}

func sheetExists(f *excelize.File, sheet string) bool {
	for _, s := range f.GetSheetList() {
		if s == sheet {
			return true
		}
	}
	return false
}

// -------------------------
// Business logic
// -------------------------

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

		// Marker logs (before)
		beforeA3 := safeCellValue(f, sheetName, "A3")
		beforeAD3 := safeCellValue(f, sheetName, "AD3")
		log.Printf("MARKER BEFORE fill: sheet=%s A3=%q AD3=%q", sheetName, beforeA3, beforeAD3)

		log.Printf("Filling sheet '%s' with Week %d data (%d entries)",
			sheetName, weekData.WeekNumber, len(weekData.Entries))

		if err := fillWeekSheet(f, sheetName, req, weekData, weekData.WeekNumber); err != nil {
			log.Printf("Error filling Week %d: %v", weekData.WeekNumber, err)
		}

		// Marker logs (after)
		afterA3 := safeCellValue(f, sheetName, "A3")
		afterAD3 := safeCellValue(f, sheetName, "AD3")
		log.Printf("MARKER AFTER fill: sheet=%s A3=%q AD3=%q", sheetName, afterA3, afterAD3)
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

	// Header info
	_ = f.SetCellValue(sheetName, "M2", req.EmployeeName)
	_ = f.SetCellValue(sheetName, "AJ2", req.PayPeriodNum)
	_ = f.SetCellValue(sheetName, "AJ3", req.Year)

	excelDate := timeToExcelDate(weekStart)
	_ = f.SetCellValue(sheetName, "B4", excelDate)
	_ = f.SetCellValue(sheetName, "AJ4", weekData.WeekLabel)

	// Write On Call rate cells used by template formulas
	onCallDailyAmount := getOnCallDailyAmount(req)
	onCallPerCallAmount := getOnCallPerCallAmount(req)
	_ = f.SetCellValue(sheetName, "AL1", onCallDailyAmount)
	_ = f.SetCellValue(sheetName, "AM1", onCallPerCallAmount)

	log.Printf("  On Call rates written: AL1=$%.2f (daily), AM1=$%.2f (perCall)",
		onCallDailyAmount, onCallPerCallAmount)

	codeColumns := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
	jobColumns := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}

	regularCols := getUniqueColumnsForType(weekData.Entries, false)
	overtimeCols := getUniqueColumnsForType(weekData.Entries, true)

	// Regular headers (Row 4)
	for i := 0; i < len(regularCols) && i < len(codeColumns); i++ {
		_ = f.SetCellValue(sheetName, codeColumns[i]+"4", "")
		_ = f.SetCellValue(sheetName, jobColumns[i]+"4", "")
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
		_ = f.SetCellValue(sheetName, codeColumns[i]+"4", labourToWrite)
		_ = f.SetCellValue(sheetName, jobColumns[i]+"4", job)
	}

	// Overtime headers (Row 15)
	for i := 0; i < len(overtimeCols) && i < len(codeColumns); i++ {
		_ = f.SetCellValue(sheetName, codeColumns[i]+"15", "")
		_ = f.SetCellValue(sheetName, jobColumns[i]+"15", "")
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
		_ = f.SetCellValue(sheetName, codeColumns[i]+"15", labourToWrite)
		_ = f.SetCellValue(sheetName, jobColumns[i]+"15", job)
	}

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

	for dayOffset := 0; dayOffset < 7; dayOffset++ {
		currentDate := weekStart.AddDate(0, 0, dayOffset)
		dateKey := currentDate.Format("2006-01-02")
		excelDateSerial := timeToExcelDate(currentDate)

		regularRow := 5 + dayOffset
		overtimeRow := 16 + dayOffset

		_ = f.SetCellValue(sheetName, fmt.Sprintf("B%d", regularRow), excelDateSerial)
		_ = f.SetCellValue(sheetName, fmt.Sprintf("B%d", overtimeRow), excelDateSerial)

		if regularHours, exists := regularTimeEntries[dateKey]; exists {
			for i, k := range regularCols {
				if i >= len(jobColumns) {
					break
				}
				if hours, ok := regularHours[k]; ok && hours > 0 {
					cellRef := fmt.Sprintf("%s%d", jobColumns[i], regularRow)
					_ = f.SetCellValue(sheetName, cellRef, hours)
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
					_ = f.SetCellValue(sheetName, cellRef, hours)
				}
			}
		}
	}

	log.Printf("=== Week %d completed ===", weekNum)
	return nil
}

// -------------------------
// Column helpers
// -------------------------

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
	return duration.Hours() / 24.0
}

// -------------------------
// Basic Excel fallback
// -------------------------

func generateBasicExcelFile(req TimecardRequest) ([]byte, error) {
	f := excelize.NewFile()
	defer f.Close()

	sheet := "Sheet1"
	_ = f.SetCellValue(sheet, "A1", "Employee Name:")
	_ = f.SetCellValue(sheet, "B1", req.EmployeeName)
	_ = f.SetCellValue(sheet, "A2", "Pay Period:")
	_ = f.SetCellValue(sheet, "B2", req.PayPeriodNum)
	_ = f.SetCellValue(sheet, "A3", "Year:")
	_ = f.SetCellValue(sheet, "B3", req.Year)
	_ = f.SetCellValue(sheet, "A4", "Week:")
	_ = f.SetCellValue(sheet, "B4", req.WeekNumberLabel)

	_ = f.SetCellValue(sheet, "A6", "Date")
	_ = f.SetCellValue(sheet, "B6", "Job Code")
	_ = f.SetCellValue(sheet, "C6", "Labour Code")
	_ = f.SetCellValue(sheet, "D6", "Job Name")
	_ = f.SetCellValue(sheet, "E6", "Hours")
	_ = f.SetCellValue(sheet, "F6", "Overtime")

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

		_ = f.SetCellValue(sheet, fmt.Sprintf("A%d", row), t.Format("2006-01-02"))

		jobCodeToWrite := entry.JobCode
		if entry.IsNightShift {
			jobCodeToWrite = "N" + jobCodeToWrite
		}
		_ = f.SetCellValue(sheet, fmt.Sprintf("B%d", row), jobCodeToWrite)
		_ = f.SetCellValue(sheet, fmt.Sprintf("C%d", row), entry.LabourCode)
		_ = f.SetCellValue(sheet, fmt.Sprintf("D%d", row), jobMap[entry.JobCode])
		_ = f.SetCellValue(sheet, fmt.Sprintf("E%d", row), entry.Hours)

		overtimeStr := "No"
		if entry.Overtime {
			overtimeStr = "Yes"
			totalOvertimeHours += entry.Hours
		}
		_ = f.SetCellValue(sheet, fmt.Sprintf("F%d", row), overtimeStr)

		labourUpper := strings.ToUpper(entry.LabourCode)
		if labourUpper == "ON CALL" || labourUpper == "ONC" || labourUpper == "O/C" {
			onCallCount++
		}

		totalHours += entry.Hours
		row++
	}

	row++
	_ = f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Hours:")
	_ = f.SetCellValue(sheet, fmt.Sprintf("E%d", row), totalHours)
	row++
	_ = f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Overtime:")
	_ = f.SetCellValue(sheet, fmt.Sprintf("E%d", row), totalOvertimeHours)

	if onCallCount > 0 {
		row += 2
		_ = f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "On Call Daily:")
		_ = f.SetCellValue(sheet, fmt.Sprintf("E%d", row), getOnCallDailyAmount(req))
		row++
		_ = f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "# of On Call:")
		_ = f.SetCellValue(sheet, fmt.Sprintf("B%d", row), onCallCount)
		_ = f.SetCellValue(sheet, fmt.Sprintf("D%d", row), "Total:")
		_ = f.SetCellValue(sheet, fmt.Sprintf("E%d", row), getOnCallPerCallAmount(req)*float64(onCallCount))
	}

	buffer, err := f.WriteToBuffer()
	if err != nil {
		return nil, err
	}
	return buffer.Bytes(), nil
}

// -------------------------
// Email
// -------------------------

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
