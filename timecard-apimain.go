package main

import (
    "bytes"
    "embed"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "time"

    "github.com/xuri/excelize/v2"
)

//go:embed template.xlsx
var templateFS embed.FS

// Updated structs to match iOS app structure
type EntryModel struct {
    ID          string  `json:"id"`
    Date        string  `json:"date"`        // ISO date format from iOS
    JobNumber   string  `json:"jobNumber"`   // Matches iOS jobNumber
    Code        string  `json:"code"`        // Matches iOS code
    Hours       float64 `json:"hours"`
    Notes       string  `json:"notes"`
    IsOvertime  bool    `json:"isOvertime"`
    IsNightShift bool   `json:"isNightShift"`
}

type EmployeeInfo struct {
    Name  string `json:"name"`
    Email string `json:"email,omitempty"`
}

type PayPeriodInfo struct {
    WeekStart   string `json:"weekStart"`   // ISO date format
    WeekEnd     string `json:"weekEnd"`     // ISO date format  
    WeekNumber  int    `json:"weekNumber"`
    TotalWeeks  int    `json:"totalWeeks"`
}

type TimecardRequest struct {
    Employee   EmployeeInfo    `json:"employee"`
    Entries    []EntryModel    `json:"entries"`
    PayPeriod  PayPeriodInfo   `json:"payPeriod"`
}

type TimecardResponse struct {
    Success      bool   `json:"success"`
    ExcelFileURL string `json:"excelFileURL,omitempty"`
    PDFFileURL   string `json:"pdfFileURL,omitempty"`
    Error        string `json:"error,omitempty"`
}

func parseISO(d string) (time.Time, error) {
    formats := []string{
        "2006-01-02T15:04:05Z07:00", // Full ISO 8601 from iOS
        "2006-01-02T15:04:05Z",      // UTC ISO 8601
        "2006-01-02",                // Date only
        "06-01-02", 
        "2006/01/02", 
        "01/02/2006", 
        "02-01-2006", 
        "02/01/2006",
    }
    for _, f := range formats {
        if t, err := time.ParseInLocation(f, d, time.Local); err == nil {
            return t, nil
        }
    }
    return time.Time{}, fmt.Errorf("bad date: %q", d)
}

func enableCORS(w http.ResponseWriter) {
    w.Header().Set("Access-Control-Allow-Origin", "*")
    w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
}

func generateTimecardHandler(w http.ResponseWriter, r *http.Request) {
    enableCORS(w)
    
    if r.Method == http.MethodOptions {
        w.WriteHeader(http.StatusNoContent)
        return
    }
    
    if r.Method != http.MethodPost {
        http.Error(w, "use POST", http.StatusMethodNotAllowed)
        return
    }

    var req TimecardRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        log.Printf("JSON decode error: %v", err)
        http.Error(w, "bad json: "+err.Error(), http.StatusBadRequest)
        return
    }

    // Validate request
    if len(req.Entries) == 0 {
        http.Error(w, "no entries provided", http.StatusBadRequest)
        return
    }

    // Load template
    tmpl, err := templateFS.ReadFile("template.xlsx")
    if err != nil {
        log.Printf("Template read error: %v", err)
        http.Error(w, "template read: "+err.Error(), http.StatusInternalServerError)
        return
    }

    f, err := excelize.OpenReader(bytes.NewReader(tmpl))
    if err != nil {
        log.Printf("Excel open error: %v", err)
        http.Error(w, "open xlsx: "+err.Error(), http.StatusInternalServerError)
        return
    }
    defer func() { _ = f.Close() }()

    // Determine which sheet to use based on week number
    weekNum := req.PayPeriod.WeekNumber
    if weekNum < 1 || weekNum > 2 {
        weekNum = 1
    }

    type weekLayout struct {
        sheet        string
        empCell      string
        mainDatesTop string
        otDatesTop   string
    }

    layout := map[int]weekLayout{
        1: {sheet: "Week 1", empCell: "M2", mainDatesTop: "B5", otDatesTop: "B16"},
        2: {sheet: "Week 2", empCell: "M2", mainDatesTop: "B5", otDatesTop: "B16"},
    }[weekNum]

    // Set employee name
    if req.Employee.Name != "" {
        if err := f.SetCellValue(layout.sheet, layout.empCell, req.Employee.Name); err != nil {
            log.Printf("Set employee error: %v", err)
            http.Error(w, "set employee: "+err.Error(), http.StatusInternalServerError)
            return
        }
    }

    // Create date style
    dateStyle, err := f.NewStyle(&excelize.Style{
        Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
        NumFmt:    14, // short date format
    })
    if err != nil {
        log.Printf("Date style error: %v", err)
        http.Error(w, "date style: "+err.Error(), http.StatusInternalServerError)
        return
    }

    // Group entries by day of week (0=Sunday, 1=Monday, etc.)
    entryMap := make(map[int][]EntryModel)
    var weekStartDate time.Time
    
    for _, entry := range req.Entries {
        dt, err := parseISO(entry.Date)
        if err != nil {
            log.Printf("Parse date error for %s: %v", entry.Date, err)
            continue
        }
        
        if weekStartDate.IsZero() {
            // Calculate week start (Sunday) from first entry
            weekStartDate = dt.AddDate(0, 0, -int(dt.Weekday()))
        }
        
        dayOfWeek := int(dt.Weekday())
        entryMap[dayOfWeek] = append(entryMap[dayOfWeek], entry)
    }

    // Fill dates for each day of the week
    fillDatesAndData := func(top string, isOvertimeSection bool) error {
        col, row, err := excelize.CellNameToCoordinates(top)
        if err != nil {
            return err
        }
        
        for i := 0; i < 7; i++ { // Sunday through Saturday
            dayDate := weekStartDate.AddDate(0, 0, i)
            
            // Set date
            dateCell, _ := excelize.CoordinatesToCellName(col, row+i)
            if err := f.SetCellValue(layout.sheet, dateCell, dayDate); err != nil {
                return err
            }
            if err := f.SetCellStyle(layout.sheet, dateCell, dateCell, dateStyle); err != nil {
                return err
            }
            
            // Set hours data for this day
            entries := entryMap[i] // i corresponds to day of week
            var totalHours float64
            var notes []string
            var projects []string
            
            for _, entry := range entries {
                if isOvertimeSection && entry.IsOvertime {
                    totalHours += entry.Hours
                    if entry.Notes != "" {
                        notes = append(notes, entry.Notes)
                    }
                    if entry.JobNumber != "" {
                        projects = append(projects, entry.JobNumber)
                    }
                } else if !isOvertimeSection && !entry.IsOvertime {
                    totalHours += entry.Hours
                    if entry.Notes != "" {
                        notes = append(notes, entry.Notes)
                    }
                    if entry.JobNumber != "" {
                        projects = append(projects, entry.JobNumber)
                    }
                }
            }
            
            // Set hours in next column (you may need to adjust this based on your template)
            if totalHours > 0 {
                hoursCell, _ := excelize.CoordinatesToCellName(col+1, row+i)
                if err := f.SetCellValue(layout.sheet, hoursCell, totalHours); err != nil {
                    return err
                }
            }
        }
        return nil
    }

    // Fill main hours section (regular time)
    if err := fillDatesAndData(layout.mainDatesTop, false); err != nil {
        log.Printf("Main dates error: %v", err)
        http.Error(w, "main dates: "+err.Error(), http.StatusInternalServerError)
        return
    }
    
    // Fill overtime section
    if err := fillDatesAndData(layout.otDatesTop, true); err != nil {
        log.Printf("OT dates error: %v", err)
        http.Error(w, "ot dates: "+err.Error(), http.StatusInternalServerError)
        return
    }

    // Set week start date in header
    if !weekStartDate.IsZero() {
        _ = f.SetCellValue(layout.sheet, "B4", weekStartDate)
        _ = f.SetCellStyle(layout.sheet, "B4", "B4", dateStyle)
    }

    // Generate Excel file
    buf, err := f.WriteToBuffer()
    if err != nil {
        log.Printf("Write buffer error: %v", err)
        http.Error(w, "write xlsx: "+err.Error(), http.StatusInternalServerError)
        return
    }

    // For now, return the Excel file directly
    // In a production setup, you'd save to cloud storage and return URLs
    w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    w.Header().Set("Content-Disposition", `attachment; filename="Timecard.xlsx"`)
    w.Header().Set("Content-Length", fmt.Sprintf("%d", buf.Len()))
    w.WriteHeader(http.StatusOK)
    
    if _, err := w.Write(buf.Bytes()); err != nil {
        log.Println("write error:", err)
    }
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    enableCORS(w)
    w.WriteHeader(http.StatusOK)
    _, _ = w.Write([]byte("OK"))
}

func main() {
    http.HandleFunc("/api/generate-timecard", generateTimecardHandler)
    http.HandleFunc("/health", healthHandler)
    
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    
    log.Printf("Server starting on port %s", port)
    log.Fatal(http.ListenAndServe(":"+port, nil))
}