// GO BACKEND FIX FOR NIGHT SHIFT ISSUE
// 
// This file contains the corrected Go code that should be in your main.go
// to properly handle night shift hours and write them to the "TOTAL NIGHT" row
//
// PROBLEM: Night shift hours are currently going to "TOTAL REGULAR" row instead of "TOTAL NIGHT" row
// SOLUTION: Separate hours into three categories and write to correct rows

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/xuri/excelize/v2"
)

// Entry struct - VERIFY this has NightShift field
type Entry struct {
	Date       string  `json:"date"`
	JobCode    string  `json:"job_code"`
	Hours      float64 `json:"hours"`
	Overtime   bool    `json:"overtime"`
	NightShift bool    `json:"night_shift"` // ⚠️ THIS MUST BE PRESENT
}

// Job struct
type Job struct {
	JobCode string `json:"job_code"`
	JobName string `json:"job_name"`
}

// TimecardRequest struct
type TimecardRequest struct {
	EmployeeName     string  `json:"employee_name"`
	PayPeriodNum     int     `json:"pay_period_num"`
	Year             int     `json:"year"`
	WeekStartDate    string  `json:"week_start_date"`
	WeekNumberLabel  string  `json:"week_number_label"`
	Jobs             []Job   `json:"jobs"`
	Entries          []Entry `json:"entries"`
}

// HoursBreakdown tracks hours by type
type HoursBreakdown struct {
	Regular  float64
	Night    float64
	Overtime float64
}

// CORRECTED: Handle generate-timecard endpoint
func handleGenerateTimecard(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var request TimecardRequest
	err := json.NewDecoder(r.Body).Decode(&request)
	if err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// 🔍 DEBUG: Log entries to verify night_shift field is received
	log.Printf("Received %d entries for employee: %s", len(request.Entries), request.EmployeeName)
	for i, entry := range request.Entries {
		log.Printf("  Entry %d: JobCode=%s, Hours=%.1f, Overtime=%v, NightShift=%v",
			i, entry.JobCode, entry.Hours, entry.Overtime, entry.NightShift)
	}

	// Generate Excel file
	excelData, err := generateTimecardExcel(request)
	if err != nil {
		log.Printf("Error generating Excel: %v", err)
		http.Error(w, "Failed to generate Excel", http.StatusInternalServerError)
		return
	}

	// Send Excel file as response
	w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"timecard_%s.xlsx\"", request.EmployeeName))
	w.Write(excelData)
}

// CORRECTED: Generate Excel with proper night shift handling
func generateTimecardExcel(request TimecardRequest) ([]byte, error) {
	// Open template file
	f, err := excelize.OpenFile("template.xlsx")
	if err != nil {
		return nil, fmt.Errorf("failed to open template: %v", err)
	}
	defer f.Close()

	// Fill in header information
	f.SetCellValue("Sheet1", "B2", request.EmployeeName)
	f.SetCellValue("Sheet1", "H2", fmt.Sprintf("PP #%d", request.PayPeriodNum))
	f.SetCellValue("Sheet1", "A4", request.WeekNumberLabel)

	// Parse week start date
	weekStart, err := time.Parse(time.RFC3339, request.WeekStartDate)
	if err != nil {
		return nil, fmt.Errorf("invalid week_start_date: %v", err)
	}

	// Set dates for each day of the week (columns C through I)
	dateColumns := []string{"C", "D", "E", "F", "G", "H", "I"} // Sun-Sat
	for i, col := range dateColumns {
		currentDate := weekStart.AddDate(0, 0, i)
		dateStr := currentDate.Format("01-02-06") // MM-DD-YY format
		cellRef := fmt.Sprintf("%s4", col)
		f.SetCellValue("Sheet1", cellRef, dateStr)
	}

	// ⭐️ KEY FIX: Separate hours by type (regular, night, overtime)
	// Map structure: jobCode -> day -> HoursBreakdown
	jobHours := make(map[string]map[int]*HoursBreakdown)

	// Initialize maps for each job
	for _, job := range request.Jobs {
		jobHours[job.JobCode] = make(map[int]*HoursBreakdown)
		for day := 0; day < 7; day++ {
			jobHours[job.JobCode][day] = &HoursBreakdown{}
		}
	}

	// Categorize entries by type
	for _, entry := range request.Entries {
		// Parse entry date
		entryDate, err := time.Parse(time.RFC3339, entry.Date)
		if err != nil {
			log.Printf("Warning: invalid entry date %s: %v", entry.Date, err)
			continue
		}

		// Calculate day index (0=Sunday, 6=Saturday)
		daysDiff := int(entryDate.Sub(weekStart).Hours() / 24)
		if daysDiff < 0 || daysDiff > 6 {
			log.Printf("Warning: entry date %s is outside week range", entry.Date)
			continue
		}

		// Get hours breakdown for this job/day
		breakdown, exists := jobHours[entry.JobCode][daysDiff]
		if !exists {
			log.Printf("Warning: job code %s not found in jobs list", entry.JobCode)
			continue
		}

		// ⭐️ KEY FIX: Categorize hours by type
		if entry.Overtime {
			breakdown.Overtime += entry.Hours
		} else if entry.NightShift {
			breakdown.Night += entry.Hours
		} else {
			breakdown.Regular += entry.Hours
		}
	}

	// Write hours to Excel template
	// Rows: 12=TOTAL REGULAR, 13=TOTAL NIGHT, 14=Overtime & Double-Time
	// Columns: C-I (Sun-Sat)

	// Determine row offset for each job in the template
	// This depends on your template structure - adjust as needed
	jobRowOffsets := make(map[string]int)
	baseRow := 5 // Starting row for job entries (adjust based on your template)
	
	for i, job := range request.Jobs {
		jobRowOffsets[job.JobCode] = baseRow + (i * 4) // Each job takes 4 rows (adjust if different)
		
		// Write job name/code to column B
		f.SetCellValue("Sheet1", fmt.Sprintf("B%d", baseRow+(i*4)), job.JobCode)
	}

	// Write hours for each job and day
	for _, job := range request.Jobs {
		jobRow := jobRowOffsets[job.JobCode]
		
		for day := 0; day < 7; day++ {
			col := dateColumns[day]
			breakdown := jobHours[job.JobCode][day]

			// Row 0: TOTAL REGULAR (relative to jobRow)
			if breakdown.Regular > 0 {
				regularRow := jobRow + 0 // Adjust offset based on your template
				cell := fmt.Sprintf("%s%d", col, regularRow)
				f.SetCellValue("Sheet1", cell, breakdown.Regular)
			}

			// Row 1: TOTAL NIGHT (relative to jobRow)
			if breakdown.Night > 0 {
				nightRow := jobRow + 1 // Adjust offset based on your template
				cell := fmt.Sprintf("%s%d", col, nightRow)
				f.SetCellValue("Sheet1", cell, breakdown.Night)
				log.Printf("✅ Writing %.1f night hours to %s (Job=%s, Day=%d)",
					breakdown.Night, cell, job.JobCode, day)
			}

			// Row 2: Overtime & Double-Time (relative to jobRow)
			if breakdown.Overtime > 0 {
				overtimeRow := jobRow + 2 // Adjust offset based on your template
				cell := fmt.Sprintf("%s%d", col, overtimeRow)
				f.SetCellValue("Sheet1", cell, breakdown.Overtime)
			}
		}
	}

	// Alternative approach if template has global TOTAL rows:
	// If your template has single TOTAL REGULAR / TOTAL NIGHT / TOTAL OVERTIME rows
	// that sum across all jobs, use this approach instead:
	
	/*
	// Sum across all jobs for each day
	for day := 0; day < 7; day++ {
		col := dateColumns[day]
		var totalRegular, totalNight, totalOvertime float64
		
		for _, job := range request.Jobs {
			breakdown := jobHours[job.JobCode][day]
			totalRegular += breakdown.Regular
			totalNight += breakdown.Night
			totalOvertime += breakdown.Overtime
		}
		
		// Write to template rows
		if totalRegular > 0 {
			f.SetCellValue("Sheet1", fmt.Sprintf("%s12", col), totalRegular)
		}
		if totalNight > 0 {
			f.SetCellValue("Sheet1", fmt.Sprintf("%s13", col), totalNight)
			log.Printf("✅ Writing %.1f total night hours to %s13", totalNight, col)
		}
		if totalOvertime > 0 {
			f.SetCellValue("Sheet1", fmt.Sprintf("%s14", col), totalOvertime)
		}
	}
	*/

	// Save to buffer
	buffer, err := f.WriteToBuffer()
	if err != nil {
		return nil, fmt.Errorf("failed to write Excel to buffer: %v", err)
	}

	return buffer.Bytes(), nil
}

func main() {
	// Health check endpoint
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	// Generate timecard endpoint
	http.HandleFunc("/api/generate-timecard", handleGenerateTimecard)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("🚀 Server starting on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

/*
IMPORTANT NOTES:

1. Row Structure Adjustment Required:
   - The code above has placeholder row offsets (jobRow + 0, jobRow + 1, jobRow + 2)
   - You MUST adjust these based on your actual Excel template structure
   - Check your template.xlsx to see:
     * What row number is "TOTAL REGULAR" for the first job?
     * What row number is "TOTAL NIGHT"?
     * What row number is "Overtime & Double-Time"?
     * How many rows does each job section take up?

2. Template Structure Options:
   
   Option A: Separate sections per job
   Row 5:  Job 1 - TOTAL REGULAR
   Row 6:  Job 1 - TOTAL NIGHT
   Row 7:  Job 1 - Overtime & Double-Time
   Row 8:  Job 1 - (blank or totals)
   Row 9:  Job 2 - TOTAL REGULAR
   Row 10: Job 2 - TOTAL NIGHT
   ...etc
   
   Option B: Global totals (all jobs combined)
   Row 12: TOTAL REGULAR (sum of all jobs)
   Row 13: TOTAL NIGHT (sum of all jobs)
   Row 14: Overtime & Double-Time (sum of all jobs)
   
   Use the appropriate code section based on your template structure.

3. Testing:
   - After making changes, rebuild and redeploy your Go backend
   - Run TestGoAPI.testNightShiftSpecifically() from Swift
   - Open generated Excel and verify:
     * Regular hours go to TOTAL REGULAR row
     * Night shift hours go to TOTAL NIGHT row
     * Overtime hours go to Overtime & Double-Time row

4. Debugging:
   - Check server logs for debug messages showing night_shift values
   - Look for "✅ Writing X night hours to..." messages
   - Verify the cell references match your template structure
*/
