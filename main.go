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
	EmployeeName         string       `json:"employee_name"`
	PayPeriodNum         int          `json:"pay_period_num"`
	Year                 int          `json:"year"`
	WeekStartDate        string       `json:"week_start_date"`
	WeekNumberLabel      string       `json:"week_number_label"`
	Jobs                 []Job        `json:"jobs"`
	Entries              []Entry      `json:"entries"`
	Weeks                []WeekData   `json:"weeks,omitempty"`
	LabourCodes          []LabourCode `json:"labour_codes,omitempty"`
	OnCallDailyAmount    *float64     `json:"on_call_daily_amount,omitempty"`    // Customizable on-call daily stipend
	OnCallPerCallAmount  *float64     `json:"on_call_per_call_amount,omitempty"` // Customizable per-call amount
}

// GetOnCallDailyAmount returns the on-call daily amount, defaulting to 300 if not set
func (r *TimecardRequest) GetOnCallDailyAmount() float64 {
	if r.OnCallDailyAmount != nil {
		return *r.OnCallDailyAmount
	}
	return 300.0 // Default value
}

// GetOnCallPerCallAmount returns the per-call amount, defaulting to 50 if not set
func (r *TimecardRequest) GetOnCallPerCallAmount() float64 {
	if r.OnCallPerCallAmount != nil {
		return *r.OnCallPerCallAmount
	}
	return 50.0 // Default value
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

	// Health check endpoint
	http.HandleFunc("/health", healthHandler)

	// API endpoints
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

	// Debug: Log all received data
	log.Printf("=== REQUEST DEBUG ===")
	log.Printf("Jobs received: %d", len(req.Jobs))
	for _, job := range req.Jobs {
		log.Printf("  Job: number='%s', code='%s'", job.JobCode, job.JobName)
	}
	log.Printf("Entries received: %d", len(req.Entries))
	for _, entry := range req.Entries {
		log.Printf("  Entry: date=%s, jobCode='%s', labourCode='%s', hours=%.1f, overtime=%v, nightShift=%v",
			entry.Date, entry.JobCode, entry.LabourCode, entry.Hours, entry.Overtime, entry.IsNightShift)
	}
	log.Printf("On-Call Daily Amount: $%.2f", req.GetOnCallDailyAmount())
	log.Printf("On-Call Per-Call Amount: $%.2f", req.GetOnCallPerCallAmount())
	log.Printf("===================")

	// Generate Excel file
	excelData, err := generateExcelFile(req)
	if err != nil {
		log.Printf("Error generating Excel: %v", err)
		http.Error(w, fmt.Sprintf("Error generating timecard: %v", err), http.StatusInternalServerError)
		return
	}

	// Send Excel file
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

	// Generate Excel file
	excelData, err := generateExcelFile(req.TimecardRequest)
	if err != nil {
		log.Printf("Error generating Excel: %v", err)
		http.Error(w, fmt.Sprintf("Error generating timecard: %v", err), http.StatusInternalServerError)
		return
	}

	log.Printf("Generated Excel file (%d bytes) for email attachment", len(excelData))

	// Send email via SMTP
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

	log.Printf("Email sent successfully to %s", req.To)
}

func generateExcelFile(req TimecardRequest) ([]byte, error) {
	// Open template file
	templatePath := "template.xlsx"
	f, err := excelize.OpenFile(templatePath)
	if err != nil {
		log.Printf("Warning: Template not found, creating basic file: %v", err)
		// If template doesn't exist, create a basic file
		return generateBasicExcelFile(req)
	}
	defer f.Close()

	// Normalize: if Weeks is empty but top-level Entries provided, partition them into Week 1 and Week 2
	if len(req.Weeks) == 0 && len(req.Entries) > 0 {
		// Parse overall week start; if missing or invalid, infer from earliest entry date (start of its week)
		var week1Start time.Time
		var parseErr error
		if req.WeekStartDate != "" {
			week1Start, parseErr = time.Parse(time.RFC3339, req.WeekStartDate)
		}
		if parseErr != nil || req.WeekStartDate == "" {
			// find earliest entry date
			earliest := time.Now().UTC()
			for _, e := range req.Entries {
				if t, err := time.Parse(time.RFC3339, e.Date); err == nil {
					if t.Before(earliest) {
						earliest = t
					}
				}
			}
			// normalize to Sunday start of that week (Excel template assumes Sun-Sat)
			wd := int(earliest.Weekday()) // 0=Sun
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
		// Only include weeks that actually have entries
		if len(w1.Entries) > 0 {
			req.Weeks = append(req.Weeks, w1)
		}
		if len(w2.Entries) > 0 {
			req.Weeks = append(req.Weeks, w2)
		}
	}

	// Get the sheets
	sheets := f.GetSheetList()
	if len(sheets) == 0 {
		return nil, fmt.Errorf("no sheets found in template")
	}

	log.Printf("Template has %d sheets: %v", len(sheets), sheets)

	// Process each week based on its WeekNumber, not array index
	// This is the key fix - use week_number to determine which sheet to fill
	for _, weekData := range req.Weeks {
		// Determine which sheet to use based on WeekNumber (1-indexed)
		sheetIndex := weekData.WeekNumber - 1 // Convert to 0-indexed

		if sheetIndex < 0 || sheetIndex >= len(sheets) {
			log.Printf("Warning: Week %d requested but only %d sheets available, using sheet 0", weekData.WeekNumber, len(sheets))
			sheetIndex = 0
		}

		sheetName := sheets[sheetIndex]
		log.Printf("Filling sheet '%s' (index %d) with Week %d data (%d entries)",
			sheetName, sheetIndex, weekData.WeekNumber, len(weekData.Entries))

		err = fillWeekSheet(f, sheetName, req, weekData, weekData.WeekNumber)
		if err != nil {
			log.Printf("Error filling Week %d: %v", weekData.WeekNumber, err)
		}
	}

	// Write to buffer
	buffer, err := f.WriteToBuffer()
	if err != nil {
		return nil, err
	}

	return buffer.Bytes(), nil
}

// fillWeekSheet fills a single week sheet with data
func fillWeekSheet(f *excelize.File, sheetName string, req TimecardRequest, weekData WeekData, weekNum int) error {
	// Parse week start date
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

	// Set week start date as Excel date serial
	excelDate := timeToExcelDate(weekStart)
	f.SetCellValue(sheetName, "B4", excelDate)

	// Set week number label
	f.SetCellValue(sheetName, "AJ4", weekData.WeekLabel)

	// Template layout:
	//   - CODE columns (C,E,G,...) are the "Labour Codes" header cells AND the hour-entry cells.
	//   - JOB columns  (D,F,H,...) are the "Job" header cells (job number).
	codeColumns := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
	jobColumns := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}

	// IMPORTANT: columns must be keyed by (job_code + labour_code) so that:
	//   job 92408 + labour 227 is a DIFFERENT column than job 92408 + labour 206
	// Night shift is treated as a separate column by prefixing with "N-".
	regularCols := getUniqueColumnsForType(weekData.Entries, false)
	overtimeCols := getUniqueColumnsForType(weekData.Entries, true)

	log.Printf("Regular columns: %v", regularCols)
	log.Printf("Overtime columns: %v", overtimeCols)

	// ---- REGULAR TIME HEADERS (Row 4) ----
	for i := 0; i < len(regularCols) && i < len(codeColumns); i++ {
		f.SetCellValue(sheetName, codeColumns[i]+"4", "")
		f.SetCellValue(sheetName, jobColumns[i]+"4", "")
	}

	for i, colKey := range regularCols {
		if i >= len(codeColumns) {
			log.Printf("Warning: More than %d regular columns, truncating", len(codeColumns))
			break
		}
		isNight, job, labour := splitColumnKey(colKey)

		labourToWrite := labour
		if isNight && labourToWrite != "" {
			labourToWrite = "N" + labourToWrite
		}
		f.SetCellValue(sheetName, codeColumns[i]+"4", labourToWrite)
		f.SetCellValue(sheetName, jobColumns[i]+"4", job)

		log.Printf("  REG header col %d: labour='%s' job='%s' (key='%s')", i, labourToWrite, job, colKey)
	}

	// ---- OVERTIME HEADERS (Row 15) ----
	for i := 0; i < len(overtimeCols) && i < len(codeColumns); i++ {
		f.SetCellValue(sheetName, codeColumns[i]+"15", "")
		f.SetCellValue(sheetName, jobColumns[i]+"15", "")
	}

	for i, colKey := range overtimeCols {
		if i >= len(codeColumns) {
			log.Printf("Warning: More than %d overtime columns, truncating", len(codeColumns))
			break
		}
		isNight, job, labour := splitColumnKey(colKey)

		labourToWrite := labour
		if isNight && labourToWrite != "" {
			labourToWrite = "N" + labourToWrite
		}
		f.SetCellValue(sheetName, codeColumns[i]+"15", labourToWrite)
		f.SetCellValue(sheetName, jobColumns[i]+"15", job)

		log.Printf("  OT header col %d: labour='%s' job='%s' (key='%s')", i, labourToWrite, job, colKey)
	}

	// Organize entries by date and (job|labour) column key
	regularTimeEntries := make(map[string]map[string]float64) // date -> colKey -> hours
	overtimeEntries := make(map[string]map[string]float64)    // date -> colKey -> hours

	// Track if this week has any On Call entries
	hasOnCallEntry := false
	onCallEntryCount := 0

	for _, entry := range weekData.Entries {
		entryDate, err := time.Parse(time.RFC3339, entry.Date)
		if err != nil {
			log.Printf("Error parsing entry date: %v", err)
			continue
		}

		dateKey := entryDate.Format("2006-01-02")
		job := strings.TrimSpace(entry.JobCode)
		labour := strings.TrimSpace(entry.LabourCode)

		// Check if this is an On Call entry (labour code contains "On Call" or "ONC" or "O/C")
		labourUpper := strings.ToUpper(labour)
		if labourUpper == "ON CALL" || labourUpper == "ONC" || labourUpper == "O/C" ||
			strings.Contains(labourUpper, "ON CALL") {
			hasOnCallEntry = true
			onCallEntryCount++
		}

		// Build a stable key for this cell column
		colKey := fmt.Sprintf("%s|%s", job, labour)
		if entry.IsNightShift {
			colKey = "N-" + colKey
		}

		log.Printf("  Processing entry: date=%s, job='%s', labour='%s', hours=%.2f, OT=%v, night=%v => key='%s'",
			dateKey, job, labour, entry.Hours, entry.Overtime, entry.IsNightShift, colKey)

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

	// Fill date column and hours data
	// Days: Sunday (row 5) through Saturday (row 11)
	for dayOffset := 0; dayOffset < 7; dayOffset++ {
		currentDate := weekStart.AddDate(0, 0, dayOffset)
		dateKey := currentDate.Format("2006-01-02")
		excelDateSerial := timeToExcelDate(currentDate)

		regularRow := 5 + dayOffset
		overtimeRow := 16 + dayOffset

		// Set date in column B for both regular and overtime sections
		f.SetCellValue(sheetName, fmt.Sprintf("B%d", regularRow), excelDateSerial)
		f.SetCellValue(sheetName, fmt.Sprintf("B%d", overtimeRow), excelDateSerial)

		// Fill regular time hours
		// IMPORTANT: Hours are written to jobColumns (D, F, H...), NOT codeColumns (C, E, G...)
		if regularHours, exists := regularTimeEntries[dateKey]; exists {
			for i, k := range regularCols {
				if i >= len(jobColumns) {
					break
				}
				if hours, hasHours := regularHours[k]; hasHours && hours > 0 {
					cellRef := fmt.Sprintf("%s%d", jobColumns[i], regularRow)
					f.SetCellValue(sheetName, cellRef, hours)
					log.Printf("    Writing REG: %s = %.2f (key %s)", cellRef, hours, k)
				}
			}
		}

		// Fill overtime hours
		// IMPORTANT: Hours are written to jobColumns (D, F, H...), NOT codeColumns (C, E, G...)
		if otHours, exists := overtimeEntries[dateKey]; exists {
			for i, k := range overtimeCols {
				if i >= len(jobColumns) {
					break
				}
				if hours, hasHours := otHours[k]; hasHours && hours > 0 {
					cellRef := fmt.Sprintf("%s%d", jobColumns[i], overtimeRow)
					f.SetCellValue(sheetName, cellRef, hours)
					log.Printf("    Writing OT: %s = %.2f (key %s)", cellRef, hours, k)
				}
			}
		}
	}

	// Write On Call amounts using customizable values from request
	// These cells are typically in a summary section of the template
	// Adjust cell references based on your actual template layout
	if hasOnCallEntry {
		onCallDailyAmount := req.GetOnCallDailyAmount()
		onCallPerCallAmount := req.GetOnCallPerCallAmount()

		log.Printf("  On Call detected: daily=$%.2f, perCall=$%.2f, count=%d",
			onCallDailyAmount, onCallPerCallAmount, onCallEntryCount)

		// Write On Call daily stipend (one per week if any on-call exists)
		// Common template locations - adjust these to match your template:
		// AI12 or similar for "On Call" amount
		f.SetCellValue(sheetName, "AI12", onCallDailyAmount)

		// Write # of On Call amount (per-call amount × count)
		// AI13 or similar for "# of On Call" amount
		perCallTotal := onCallPerCallAmount * float64(onCallEntryCount)
		f.SetCellValue(sheetName, "AI13", perCallTotal)

		log.Printf("  Wrote On Call: AI12=$%.2f (daily), AI13=$%.2f (perCall×%d)",
			onCallDailyAmount, perCallTotal, onCallEntryCount)
	}

	log.Printf("=== Week %d completed ===", weekNum)
	return nil
}

// columnKey returns a unique column key for an entry, including night-shift separation.
// Format: "job|labour" or "N-job|labour" (using "N-" prefix).
func columnKey(e Entry) string {
	base := fmt.Sprintf("%s|%s", strings.TrimSpace(e.JobCode), strings.TrimSpace(e.LabourCode))
	if e.IsNightShift {
		return "N-" + base
	}
	return base
}

// splitColumnKey parses a column key back into (isNight, job, labour).
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

// getUniqueColumnsForType returns unique (job|labour) column keys from entries filtered by overtime type.
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

// getMapKeys returns the keys of a Job map for debugging
func getMapKeys(m map[string]*Job) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

// timeToExcelDate converts a Go time.Time to Excel date serial number
// Excel's epoch is December 30, 1899
func timeToExcelDate(t time.Time) float64 {
	// Excel epoch: December 30, 1899
	excelEpoch := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
	duration := t.Sub(excelEpoch)
	days := duration.Hours() / 24.0
	return days
}

// generateBasicExcelFile creates a basic Excel file when template is not available
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

	// Headers
	f.SetCellValue(sheet, "A6", "Date")
	f.SetCellValue(sheet, "B6", "Job Code")
	f.SetCellValue(sheet, "C6", "Labour Code")
	f.SetCellValue(sheet, "D6", "Job Name")
	f.SetCellValue(sheet, "E6", "Hours")
	f.SetCellValue(sheet, "F6", "Overtime")

	// Create job lookup
	jobMap := make(map[string]string)
	for _, job := range req.Jobs {
		jobMap[job.JobCode] = job.JobName
	}

	// Add entries
	row := 7
	totalHours := 0.0
	totalOvertimeHours := 0.0
	onCallEntryCount := 0

	for _, entry := range req.Entries {
		// Parse date
		t, err := time.Parse(time.RFC3339, entry.Date)
		if err != nil {
			log.Printf("Error parsing date: %v", err)
			continue
		}

		f.SetCellValue(sheet, fmt.Sprintf("A%d", row), t.Format("2006-01-02"))

		// Prefix job code with "N" if night shift for output consistency
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

		// Check for On Call entries
		labourUpper := strings.ToUpper(entry.LabourCode)
		if labourUpper == "ON CALL" || labourUpper == "ONC" || labourUpper == "O/C" ||
			strings.Contains(labourUpper, "ON CALL") {
			onCallEntryCount++
		}

		totalHours += entry.Hours
		row++
	}

	// Add totals
	row++
	f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Hours:")
	f.SetCellValue(sheet, fmt.Sprintf("E%d", row), totalHours)
	row++
	f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Overtime:")
	f.SetCellValue(sheet, fmt.Sprintf("E%d", row), totalOvertimeHours)

	// Add On Call summary with customizable amounts
	if onCallEntryCount > 0 {
		row++
		row++
		f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "On Call Daily Amount:")
		f.SetCellValue(sheet, fmt.Sprintf("E%d", row), req.GetOnCallDailyAmount())
		row++
		f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "# of On Call:")
		f.SetCellValue(sheet, fmt.Sprintf("B%d", row), onCallEntryCount)
		f.SetCellValue(sheet, fmt.Sprintf("D%d", row), "Total:")
		f.SetCellValue(sheet, fmt.Sprintf("E%d", row), req.GetOnCallPerCallAmount()*float64(onCallEntryCount))
	}

	// Write to buffer
	buffer, err := f.WriteToBuffer()
	if err != nil {
		return nil, err
	}

	return buffer.Bytes(), nil
}

// sendEmail sends an email with Excel attachment via SMTP
func sendEmail(to string, cc *string, subject string, body string, attachment []byte, employeeName string) error {
	// Get SMTP configuration from environment variables
	smtpHost := os.Getenv("SMTP_HOST")
	smtpPort := os.Getenv("SMTP_PORT")
	smtpUser := os.Getenv("SMTP_USER")
	smtpPass := os.Getenv("SMTP_PASS")
	fromEmail := os.Getenv("SMTP_FROM")

	// Check if SMTP is configured
	if smtpHost == "" || smtpPort == "" || smtpUser == "" || smtpPass == "" {
		return fmt.Errorf("SMTP not configured - please set SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS environment variables")
	}

	if fromEmail == "" {
		fromEmail = smtpUser // Use SMTP user as sender if FROM not specified
	}

	// Parse recipients
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

	// Combine all recipients for SMTP
	allRecipients := append([]string{}, recipients...)
	allRecipients = append(allRecipients, ccRecipients...)

	// Create email message with attachment
	fileName := fmt.Sprintf("timecard_%s_%s.xlsx",
		strings.ReplaceAll(employeeName, " ", "_"),
		time.Now().Format("2006-01-02"))

	message := buildEmailMessage(fromEmail, recipients, ccRecipients, subject, body, attachment, fileName)

	// Connect to SMTP server
	auth := smtp.PlainAuth("", smtpUser, smtpPass, smtpHost)
	addr := fmt.Sprintf("%s:%s", smtpHost, smtpPort)

	// Send email
	err := smtp.SendMail(addr, auth, fromEmail, allRecipients, []byte(message))
	if err != nil {
		return fmt.Errorf("failed to send email: %v", err)
	}

	log.Printf("Email sent successfully to %s", to)
	return nil
}

// buildEmailMessage constructs a MIME email message with attachment
func buildEmailMessage(from string, to []string, cc []string, subject string, body string, attachment []byte, fileName string) string {
	boundary := "==BOUNDARY=="

	var buf bytes.Buffer

	// Headers
	buf.WriteString(fmt.Sprintf("From: %s\r\n", from))
	buf.WriteString(fmt.Sprintf("To: %s\r\n", strings.Join(to, ", ")))
	if len(cc) > 0 {
		buf.WriteString(fmt.Sprintf("Cc: %s\r\n", strings.Join(cc, ", ")))
	}
	buf.WriteString(fmt.Sprintf("Subject: %s\r\n", subject))
	buf.WriteString("MIME-Version: 1.0\r\n")
	buf.WriteString(fmt.Sprintf("Content-Type: multipart/mixed; boundary=\"%s\"\r\n", boundary))
	buf.WriteString("\r\n")

	// Body
	buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
	buf.WriteString("Content-Type: text/plain; charset=\"utf-8\"\r\n")
	buf.WriteString("Content-Transfer-Encoding: quoted-printable\r\n")
	buf.WriteString("\r\n")
	buf.WriteString(body)
	buf.WriteString("\r\n\r\n")

	// Attachment
	if len(attachment) > 0 {
		buf.WriteString(fmt.Sprintf("--%s\r\n", boundary))
		buf.WriteString("Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n")
		buf.WriteString(fmt.Sprintf("Content-Disposition: attachment; filename=\"%s\"\r\n", fileName))
		buf.WriteString("Content-Transfer-Encoding: base64\r\n")
		buf.WriteString("\r\n")

		// Encode attachment in base64
		encoded := base64.StdEncoding.EncodeToString(attachment)
		// Split into 76-character lines as per RFC 2045
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

	// End boundary
	buf.WriteString(fmt.Sprintf("--%s--\r\n", boundary))

	return buf.String()
}
