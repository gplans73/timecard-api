package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"github.com/xuri/excelize/v2"
	"io"
	"log"
	"net/http"
	"net/smtp"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// setCellPreserveStyle writes a value into a cell while preserving the cell's original style (borders, number formats, alignment, etc).
// This is useful because some Excel clients will "repair" workbooks if the calc chain/style graph is inconsistent,
// and the repair process can strip formatting. We keep the template style intact by re-applying it after writes.
func setCellPreserveStyle(f *excelize.File, sheet, cell string, value any) error {
	styleID, _ := f.GetCellStyle(sheet, cell) // ignore errors; styleID=0 means "no explicit style"
	if err := f.SetCellValue(sheet, cell, value); err != nil {
		return err
	}
	if styleID != 0 {
		_ = f.SetCellStyle(sheet, cell, cell, styleID)
	}
	return nil
}

// removeCalcChain removes xl/calcChain.xml if present.
// Note: In excelize v2.9.0+, calcChain is handled automatically.
// This function is kept for compatibility but does nothing in newer versions.
// forceRecalcAndRemoveCalcChain post-processes an XLSX to:
// 1) remove xl/calcChain.xml (and related references), and
// 2) ensure Excel recalculates formulas when the file is opened.
func forceRecalcAndRemoveCalcChain(xlsx []byte) ([]byte, error) {
	zr, err := zip.NewReader(bytes.NewReader(xlsx), int64(len(xlsx)))
	if err != nil {
		return nil, fmt.Errorf("open xlsx zip: %w", err)
	}

	var out bytes.Buffer
	zw := zip.NewWriter(&out)

	for _, zf := range zr.File {
		name := zf.Name

		// Drop calcChain entirely (stale calcChain is the common cause of "formulas show but values don't update")
		if name == "xl/calcChain.xml" {
			continue
		}

		rc, err := zf.Open()
		if err != nil {
			_ = zw.Close()
			return nil, fmt.Errorf("read %s: %w", name, err)
		}
		b, err := io.ReadAll(rc)
		_ = rc.Close()
		if err != nil {
			_ = zw.Close()
			return nil, fmt.Errorf("read %s: %w", name, err)
		}

		switch name {
		case "xl/workbook.xml":
			b = ensureCalcPrAutoFull(b)
		case "xl/_rels/workbook.xml.rels":
			b = removeCalcChainRelationships(b)
		case "[Content_Types].xml":
			b = removeCalcChainContentType(b)
		}

		hdr := zf.FileHeader // copy
		w, err := zw.CreateHeader(&hdr)
		if err != nil {
			_ = zw.Close()
			return nil, fmt.Errorf("write %s: %w", name, err)
		}
		if _, err := w.Write(b); err != nil {
			_ = zw.Close()
			return nil, fmt.Errorf("write %s: %w", name, err)
		}
	}

	if err := zw.Close(); err != nil {
		return nil, fmt.Errorf("finalize xlsx zip: %w", err)
	}
	return out.Bytes(), nil
}

func ensureCalcPrAutoFull(b []byte) []byte {
	s := string(b)

	// Match <calcPr .../> (or <calcPr ...> ... </calcPr>)
	reCalcPr := regexp.MustCompile(`(?s)<calcPr[^>]*/?>`)
	loc := reCalcPr.FindStringIndex(s)
	if loc == nil {
		// No calcPr -> insert a minimal one before </workbook>
		insert := `<calcPr calcId="1" calcMode="auto" fullCalcOnLoad="1"/>`
		if strings.Contains(s, "</workbook>") {
			s = strings.Replace(s, "</workbook>", insert+"</workbook>", 1)
			return []byte(s)
		}
		return b
	}

	elem := s[loc[0]:loc[1]]

	// calcMode="auto"
	if regexp.MustCompile(`calcMode="[^"]*"`).MatchString(elem) {
		elem = regexp.MustCompile(`calcMode="[^"]*"`).ReplaceAllString(elem, `calcMode="auto"`)
	} else {
		elem = strings.Replace(elem, "<calcPr", `<calcPr calcMode="auto"`, 1)
	}

	// fullCalcOnLoad="1"
	if !strings.Contains(elem, `fullCalcOnLoad="`) {
		elem = strings.Replace(elem, "<calcPr", `<calcPr fullCalcOnLoad="1"`, 1)
	} else {
		elem = regexp.MustCompile(`fullCalcOnLoad="[^"]*"`).ReplaceAllString(elem, `fullCalcOnLoad="1"`)
	}

	// Replace the calcPr element in workbook.xml
	s = s[:loc[0]] + elem + s[loc[1]:]
	return []byte(s)
}

func removeCalcChainRelationships(b []byte) []byte {
	s := string(b)
	// Remove any relationship entries that reference calcChain (by Type or Target)
	re := regexp.MustCompile(`(?s)<Relationship[^>]*(?:calcChain)[^>]*/>`)
	s = re.ReplaceAllString(s, "")
	return []byte(s)
}

func removeCalcChainContentType(b []byte) []byte {
	s := string(b)
	re := regexp.MustCompile(`(?s)<Override[^>]*PartName="/xl/calcChain\.xml"[^>]*/>`)
	s = re.ReplaceAllString(s, "")
	return []byte(s)
}

// =============================================================================
// DATA STRUCTURES - Clear naming convention:
//   - job_number: The project/job identifier (e.g., "234", "1017")
//   - labour_code: The work type code (e.g., "227", "201", "On Call")
// =============================================================================

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

// Job represents a job/project with its number and display name
// job_number: The project identifier (e.g., "234", "1017")
// job_name: Human-readable name or description
type Job struct {
	JobNumber string `json:"job_number"`
	JobName   string `json:"job_name"`
}

// LabourCode represents a type of work
type LabourCode struct {
	Code string `json:"code"`
	Name string `json:"name"`
}

// Entry represents a single timecard entry
// job_number: The project/job identifier
// labour_code: The work type code (e.g., "227", "On Call")
type Entry struct {
	Date         string  `json:"date"`
	JobNumber    string  `json:"job_number"`
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

	// Debug: Log received data
	log.Printf("=== REQUEST DEBUG ===")
	log.Printf("Jobs received: %d", len(req.Jobs))
	for _, j := range req.Jobs {
		log.Printf("  Job: jobNumber='%s', jobName='%s'", j.JobNumber, j.JobName)
	}
	log.Printf("Entries received: %d", len(req.Entries))
	for _, e := range req.Entries {
		log.Printf("  Entry: date=%s, jobNumber='%s', labourCode='%s', hours=%.1f, overtime=%v, night=%v",
			e.Date, e.JobNumber, e.LabourCode, e.Hours, e.Overtime, e.IsNightShift)
	}
	log.Printf("On-Call Daily Amount: $%.2f, Per-Call Amount: $%.2f",
		getOnCallDailyAmount(req), getOnCallPerCallAmount(req))
	log.Printf("===================")

	excelData, err := generateExcelFile(req)
	if err != nil {
		log.Printf("Error generating Excel: %v", err)
		http.Error(w, fmt.Sprintf("Error generating timecard: %v", err), http.StatusInternalServerError)
		return
	}

	// Post-process: remove calcChain.xml and force Excel to recalculate on open
	excelData, err = forceRecalcAndRemoveCalcChain(excelData)
	if err != nil {
		log.Printf("Warning: Could not post-process Excel file: %v", err)
		// Continue anyway - the file should still be usable
	} else {
		log.Printf("Post-processed Excel: removed calcChain, added fullCalcOnLoad")
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

	// Post-process: remove calcChain.xml and force Excel to recalculate on open
	excelData, err = forceRecalcAndRemoveCalcChain(excelData)
	if err != nil {
		log.Printf("Warning: Could not post-process Excel file for email: %v", err)
		// Continue anyway
	} else {
		log.Printf("Post-processed Excel for email: removed calcChain, added fullCalcOnLoad")
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

	// Build job name lookup map: jobNumber -> jobName
	jobNameMap := make(map[string]string)
	for _, job := range req.Jobs {
		jobNameMap[job.JobNumber] = job.JobName
	}

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

		err = fillWeekSheet(f, sheetName, req, weekData, weekData.WeekNumber, jobNameMap)
		if err != nil {
			log.Printf("Error filling Week %d: %v", weekData.WeekNumber, err)
		}

		// Log marker cells after filling
		a3After, _ := f.GetCellValue(sheetName, "A3")
		ad3After, _ := f.GetCellValue(sheetName, "AD3")
		log.Printf("MARKER AFTER fill: sheet=%s A3=%q AD3=%q", sheetName, a3After, ad3After)
	}
	buffer, err := f.WriteToBuffer()
	if err != nil {
		return nil, err
	}
	return buffer.Bytes(), nil
}

func fillWeekSheet(f *excelize.File, sheetName string, req TimecardRequest, weekData WeekData, weekNum int, jobNameMap map[string]string) error {
	weekStart, err := time.Parse(time.RFC3339, weekData.WeekStartDate)
	if err != nil {
		return fmt.Errorf("error parsing week start date: %v", err)
	}

	log.Printf("=== Filling Week %d ===", weekNum)
	log.Printf("Week start: %s, Entries: %d", weekStart.Format("2006-01-02"), len(weekData.Entries))

	// Header info
	_ = setCellPreserveStyle(f, sheetName, "M2", req.EmployeeName)
	_ = setCellPreserveStyle(f, sheetName, "AJ2", req.PayPeriodNum)
	_ = setCellPreserveStyle(f, sheetName, "AJ3", req.Year)
	excelDate := timeToExcelDate(weekStart)
	_ = setCellPreserveStyle(f, sheetName, "B4", excelDate)
	_ = setCellPreserveStyle(f, sheetName, "AJ4", weekData.WeekLabel)

	// Write On Call rate cells used by template formulas
	// AM12 = Daily On Call rate, AM13 = Per Call rate
	onCallDailyAmount := getOnCallDailyAmount(req)
	onCallPerCallAmount := getOnCallPerCallAmount(req)

	_ = setCellPreserveStyle(f, sheetName, "AM12", onCallDailyAmount)
	_ = setCellPreserveStyle(f, sheetName, "AM13", onCallPerCallAmount)
	log.Printf("  On Call rates written: AM12=$%.2f (daily), AM13=$%.2f (perCall)",
		onCallDailyAmount, onCallPerCallAmount)

	// Column layout for the timecard template:
	// Labour code columns: C, E, G, I, K, M, O, Q, S, U, W, Y, AA, AC, AE, AG
	// Job number columns:  D, F, H, J, L, N, P, R, T, V, X, Z, AB, AD, AF, AH
	labourCodeColumns := []string{"C", "E", "G", "I", "K", "M", "O", "Q", "S", "U", "W", "Y", "AA", "AC", "AE", "AG"}
	jobNumberColumns := []string{"D", "F", "H", "J", "L", "N", "P", "R", "T", "V", "X", "Z", "AB", "AD", "AF", "AH"}

	// Get unique column keys for regular and overtime entries
	// Column key format: "jobNumber|labourCode|isNight"
	regularCols := getUniqueColumnsForType(weekData.Entries, false)
	overtimeCols := getUniqueColumnsForType(weekData.Entries, true)

	log.Printf("Regular columns: %v", regularCols)
	log.Printf("Overtime columns: %v", overtimeCols)

	// Fill Regular headers (Row 4)
	for i, colKey := range regularCols {
		if i >= len(labourCodeColumns) {
			log.Printf("Warning: More regular columns than available (%d), truncating", len(labourCodeColumns))
			break
		}
		jobNumber, labourCode, isNight := splitColumnKey(colKey)

		// Prepend "N" to labour code for night shift entries
		labourCodeToWrite := labourCode
		if isNight && labourCodeToWrite != "" {
			labourCodeToWrite = "N" + labourCodeToWrite
		}

		// Write labour code to column C, E, G, etc. (row 4)
		_ = setCellPreserveStyle(f, sheetName, labourCodeColumns[i]+"4", labourCodeToWrite)
		// Write job number to column D, F, H, etc. (row 4)
		_ = setCellPreserveStyle(f, sheetName, jobNumberColumns[i]+"4", jobNumber)

		log.Printf("  REG header col %d: labourCode='%s' -> %s4, jobNumber='%s' -> %s4",
			i, labourCodeToWrite, labourCodeColumns[i], jobNumber, jobNumberColumns[i])
	}

	// Fill Overtime headers (Row 15)
	for i, colKey := range overtimeCols {
		if i >= len(labourCodeColumns) {
			log.Printf("Warning: More overtime columns than available (%d), truncating", len(labourCodeColumns))
			break
		}
		jobNumber, labourCode, isNight := splitColumnKey(colKey)

		labourCodeToWrite := labourCode
		if isNight && labourCodeToWrite != "" {
			labourCodeToWrite = "N" + labourCodeToWrite
		}

		// Write labour code to column C, E, G, etc. (row 15)
		_ = setCellPreserveStyle(f, sheetName, labourCodeColumns[i]+"15", labourCodeToWrite)
		// Write job number to column D, F, H, etc. (row 15)
		_ = setCellPreserveStyle(f, sheetName, jobNumberColumns[i]+"15", jobNumber)

		log.Printf("  OT header col %d: labourCode='%s' -> %s15, jobNumber='%s' -> %s15",
			i, labourCodeToWrite, labourCodeColumns[i], jobNumber, jobNumberColumns[i])
	}

	// Organize entries by date and column key
	// Map: dateKey -> columnKey -> hours
	regularTimeEntries := make(map[string]map[string]float64)
	overtimeEntries := make(map[string]map[string]float64)

	for _, entry := range weekData.Entries {
		entryDate, err := time.Parse(time.RFC3339, entry.Date)
		if err != nil {
			log.Printf("Warning: Could not parse entry date '%s': %v", entry.Date, err)
			continue
		}

		dateKey := entryDate.Format("2006-01-02")
		colKey := columnKey(entry)

		log.Printf("  Processing entry: date=%s, jobNumber='%s', labourCode='%s', hours=%.2f, OT=%v, night=%v => key='%s'",
			dateKey, entry.JobNumber, entry.LabourCode, entry.Hours, entry.Overtime, entry.IsNightShift, colKey)

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

	// Fill each day (7 days in a week)
	for dayOffset := 0; dayOffset < 7; dayOffset++ {
		currentDate := weekStart.AddDate(0, 0, dayOffset)
		dateKey := currentDate.Format("2006-01-02")
		excelDateSerial := timeToExcelDate(currentDate)

		// Regular time row: 5-11 (dayOffset 0-6)
		// Overtime row: 16-22 (dayOffset 0-6)
		regularRow := 5 + dayOffset
		overtimeRow := 16 + dayOffset

		// Write dates to column B
		_ = setCellPreserveStyle(f, sheetName, fmt.Sprintf("B%d", regularRow), excelDateSerial)
		_ = setCellPreserveStyle(f, sheetName, fmt.Sprintf("B%d", overtimeRow), excelDateSerial)

		// Fill regular time hours
		if regularHours, exists := regularTimeEntries[dateKey]; exists {
			for i, colKey := range regularCols {
				if i >= len(jobNumberColumns) {
					break
				}
				if hours, ok := regularHours[colKey]; ok && hours > 0 {
					// Hours go in the job number column (D, F, H, etc.)
					cellRef := fmt.Sprintf("%s%d", jobNumberColumns[i], regularRow)
					_ = setCellPreserveStyle(f, sheetName, cellRef, hours)
					log.Printf("    REG: Wrote %.2f hours to %s (date=%s, key=%s)", hours, cellRef, dateKey, colKey)
				}
			}
		}

		// Fill overtime hours
		if otHours, exists := overtimeEntries[dateKey]; exists {
			for i, colKey := range overtimeCols {
				if i >= len(jobNumberColumns) {
					break
				}
				if hours, ok := otHours[colKey]; ok && hours > 0 {
					cellRef := fmt.Sprintf("%s%d", jobNumberColumns[i], overtimeRow)
					_ = setCellPreserveStyle(f, sheetName, cellRef, hours)
					log.Printf("    OT: Wrote %.2f hours to %s (date=%s, key=%s)", hours, cellRef, dateKey, colKey)
				}
			}
		}
	}

	log.Printf("=== Week %d completed ===", weekNum)
	return nil
}

// columnKey creates a unique key for grouping entries by job+labour+night
// Format: "jobNumber|labourCode|night" where night is "1" or "0"
func columnKey(e Entry) string {
	jobNumber := strings.TrimSpace(e.JobNumber)
	labourCode := strings.TrimSpace(e.LabourCode)
	night := "0"
	if e.IsNightShift {
		night = "1"
	}
	return fmt.Sprintf("%s|%s|%s", jobNumber, labourCode, night)
}

// splitColumnKey extracts components from a column key
// Returns: jobNumber, labourCode, isNight
func splitColumnKey(k string) (string, string, bool) {
	parts := strings.SplitN(k, "|", 3)
	jobNumber := ""
	labourCode := ""
	isNight := false

	if len(parts) > 0 {
		jobNumber = parts[0]
	}
	if len(parts) > 1 {
		labourCode = parts[1]
	}
	if len(parts) > 2 {
		isNight = parts[2] == "1"
	}
	return jobNumber, labourCode, isNight
}

// getUniqueColumnsForType returns unique column keys for either regular or overtime entries
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
	f.SetCellValue(sheet, "B6", "Job Number")
	f.SetCellValue(sheet, "C6", "Labour Code")
	f.SetCellValue(sheet, "D6", "Hours")
	f.SetCellValue(sheet, "E6", "Overtime")
	f.SetCellValue(sheet, "F6", "Night Shift")

	// Build job name map
	jobNameMap := make(map[string]string)
	for _, job := range req.Jobs {
		jobNameMap[job.JobNumber] = job.JobName
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
		f.SetCellValue(sheet, fmt.Sprintf("B%d", row), entry.JobNumber)
		f.SetCellValue(sheet, fmt.Sprintf("C%d", row), entry.LabourCode)
		f.SetCellValue(sheet, fmt.Sprintf("D%d", row), entry.Hours)

		overtimeStr := "No"
		if entry.Overtime {
			overtimeStr = "Yes"
			totalOvertimeHours += entry.Hours
		}
		f.SetCellValue(sheet, fmt.Sprintf("E%d", row), overtimeStr)

		nightStr := "No"
		if entry.IsNightShift {
			nightStr = "Yes"
		}
		f.SetCellValue(sheet, fmt.Sprintf("F%d", row), nightStr)

		// Check for On Call
		labourCodeUpper := strings.ToUpper(strings.TrimSpace(entry.LabourCode))
		if labourCodeUpper == "ON CALL" || labourCodeUpper == "ONCALL" || labourCodeUpper == "ONC" {
			onCallCount++
		}

		totalHours += entry.Hours
		row++
	}

	row++
	f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Hours:")
	f.SetCellValue(sheet, fmt.Sprintf("D%d", row), totalHours)
	row++
	f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "Total Overtime:")
	f.SetCellValue(sheet, fmt.Sprintf("D%d", row), totalOvertimeHours)

	if onCallCount > 0 {
		row += 2
		f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "On Call Daily:")
		f.SetCellValue(sheet, fmt.Sprintf("D%d", row), getOnCallDailyAmount(req))
		row++
		f.SetCellValue(sheet, fmt.Sprintf("A%d", row), "# of On Call:")
		f.SetCellValue(sheet, fmt.Sprintf("B%d", row), onCallCount)
		f.SetCellValue(sheet, fmt.Sprintf("C%d", row), "Total:")
		f.SetCellValue(sheet, fmt.Sprintf("D%d", row), getOnCallPerCallAmount(req)*float64(onCallCount))
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
