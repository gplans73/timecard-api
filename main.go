package main

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/xuri/excelize/v2"
)

type Entry struct {
	Date         time.Time `json:"date"`
	Hours        float64   `json:"hours"`
	Overtime     bool      `json:"overtime"`
	IsNightShift bool      `json:"is_night_shift"`
	JobCode      string    `json:"job_code"`
}

type Week struct {
	WeekNumber    int     `json:"week_number"`
	WeekLabel     string  `json:"week_label"`
	WeekStartDate string  `json:"week_start_date"`
	Entries       []Entry `json:"entries"`
}

type GenerateRequest struct {
	EmployeeName          string  `json:"employee_name"`
	Year                  int     `json:"year"`
	PayPeriodNum          int     `json:"pay_period_num"`
	WeekStartDate         string  `json:"week_start_date"`
	WeekNumberLabel       string  `json:"week_number_label"`
	OnCallDailyAmount     float64 `json:"on_call_daily_amount"`
	OnCallPerCallAmount   float64 `json:"on_call_per_call_amount"`
	Weeks                 []Week  `json:"weeks"`
}

func main() {
	http.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	http.HandleFunc("/api/generate-timecard", handleGenerate)

	port := os.Getenv("PORT")
	if port == "" {
		port = "10000"
	}

	log.Println("Server starting on port", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func handleGenerate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req GenerateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	f, err := excelize.OpenFile("template.xlsx")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// ===============================
	// WRITE RATE CELLS (DO NOT STYLE)
	// ===============================
	for _, sheet := range f.GetSheetList() {
		f.SetCellValue(sheet, "AM12", req.OnCallDailyAmount)
		f.SetCellValue(sheet, "AM13", req.OnCallPerCallAmount)

		log.Printf("On Call rates written to %s: AM12=$%.2f AM13=$%.2f",
			sheet,
			req.OnCallDailyAmount,
			req.OnCallPerCallAmount,
		)
	}

	// ===============================
	// FILL EACH WEEK (DATA ONLY)
	// ===============================
	for _, week := range req.Weeks {
		sheetName := week.WeekLabel
		if f.GetSheetIndex(sheetName) == -1 {
			continue
		}

		fillWeek(f, sheetName, week)
	}

	var buf bytes.Buffer
	if err := f.Write(&buf); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	w.Write(buf.Bytes())
}

func fillWeek(f *excelize.File, sheet string, week Week) {
	start, err := time.Parse("2006-01-02T15:04:05Z", week.WeekStartDate)
	if err != nil {
		return
	}

	for _, e := range week.Entries {
		dayOffset := int(e.Date.Sub(start).Hours() / 24)
		if dayOffset < 0 || dayOffset > 6 {
			continue
		}

		row := 6 + dayOffset

		col := findNextEmptyHourCell(f, sheet, row)
		if col == "" {
			continue
		}

		f.SetCellValue(sheet, col, e.Hours)

		log.Printf(
			"Filled %s %s row=%d col=%s hours=%.2f",
			sheet,
			e.Date.Format("2006-01-02"),
			row,
			col,
			e.Hours,
		)
	}
}

func findNextEmptyHourCell(f *excelize.File, sheet string, row int) string {
	for c := 'D'; c <= 'W'; c++ {
		cell := string(c) + itoa(row)
		val, _ := f.GetCellValue(sheet, cell)
		if val == "" {
			return cell
		}
	}
	return ""
}

func itoa(i int) string {
	return strconv.Itoa(i)
}
