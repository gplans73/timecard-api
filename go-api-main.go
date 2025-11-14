package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/gin-cors/cors"
	"github.com/gin-gonic/gin"
	"github.com/xuri/excelize/v2"
)

// Request/Response models matching your Swift code
type EmployeeInfo struct {
	Name  string  `json:"name"`
	Email *string `json:"email,omitempty"`
}

type TimecardEntryData struct {
	Date        string  `json:"date"`
	JobNumber   string  `json:"jobNumber"`
	Code        string  `json:"code"`
	Hours       float64 `json:"hours"`
	Notes       string  `json:"notes"`
	IsOvertime  bool    `json:"isOvertime"`
	IsNightShift bool   `json:"isNightShift"`
}

type PayPeriodInfo struct {
	WeekStart  string `json:"weekStart"`
	WeekEnd    string `json:"weekEnd"`
	WeekNumber int    `json:"weekNumber"`
	TotalWeeks int    `json:"totalWeeks"`
}

type TimecardExportRequest struct {
	Employee  EmployeeInfo        `json:"employee"`
	Entries   []TimecardEntryData `json:"entries"`
	PayPeriod PayPeriodInfo       `json:"payPeriod"`
}

type TimecardExportResponse struct {
	Success      bool    `json:"success"`
	ExcelFileURL *string `json:"excelFileURL,omitempty"`
	PDFFileURL   *string `json:"pdfFileURL,omitempty"`
	Error        *string `json:"error,omitempty"`
}

func main() {
	// Create uploads directory
	os.MkdirAll("uploads", 0755)
	
	r := gin.Default()
	
	// CORS middleware
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "healthy"})
	})

	// Main endpoint
	r.POST("/api/generate-timecard", handleGenerateTimecard)
	
	// Serve generated files
	r.Static("/uploads", "./uploads")

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	
	log.Printf("Server starting on port %s", port)
	r.Run(":" + port)
}

func handleGenerateTimecard(c *gin.Context) {
	var req TimecardExportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, TimecardExportResponse{
			Success: false,
			Error:   stringPtr("Invalid request format: " + err.Error()),
		})
		return
	}

	// Generate unique filename
	timestamp := time.Now().Format("20060102_150405")
	baseFilename := fmt.Sprintf("timecard_%s_%s", 
		sanitizeFilename(req.Employee.Name), timestamp)
	
	// Generate Excel file
	excelPath, err := generateExcel(req, baseFilename)
	if err != nil {
		log.Printf("Error generating Excel: %v", err)
		c.JSON(500, TimecardExportResponse{
			Success: false,
			Error:   stringPtr("Failed to generate Excel file: " + err.Error()),
		})
		return
	}

	// Generate PDF from Excel (simplified approach)
	pdfPath, err := generatePDFFromExcel(excelPath, baseFilename)
	if err != nil {
		log.Printf("Error generating PDF: %v", err)
		c.JSON(500, TimecardExportResponse{
			Success: false,
			Error:   stringPtr("Failed to generate PDF file: " + err.Error()),
		})
		return
	}

	// Return file URLs
	c.JSON(200, TimecardExportResponse{
		Success:      true,
		ExcelFileURL: stringPtr("/uploads/" + filepath.Base(excelPath)),
		PDFFileURL:   stringPtr("/uploads/" + filepath.Base(pdfPath)),
	})
}

func generateExcel(req TimecardExportRequest, baseFilename string) (string, error) {
	f := excelize.NewFile()
	defer f.Close()
	
	sheetName := "Timecard"
	f.SetSheetName("Sheet1", sheetName)

	// Set headers
	headers := []string{"Date", "Job Number", "Code", "Hours", "Notes", "Overtime", "Night Shift"}
	for i, header := range headers {
		cell := fmt.Sprintf("%c1", 'A'+i)
		f.SetCellValue(sheetName, cell, header)
	}

	// Set header style
	headerStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true},
		Fill: &excelize.Fill{Type: "pattern", Color: []string{"E0E0E0"}, Pattern: 1},
	})
	f.SetCellStyle(sheetName, "A1", fmt.Sprintf("%c1", 'A'+len(headers)-1), headerStyle)

	// Add data rows
	for i, entry := range req.Entries {
		row := i + 2
		f.SetCellValue(sheetName, fmt.Sprintf("A%d", row), entry.Date)
		f.SetCellValue(sheetName, fmt.Sprintf("B%d", row), entry.JobNumber)
		f.SetCellValue(sheetName, fmt.Sprintf("C%d", row), entry.Code)
		f.SetCellValue(sheetName, fmt.Sprintf("D%d", row), entry.Hours)
		f.SetCellValue(sheetName, fmt.Sprintf("E%d", row), entry.Notes)
		
		overtime := "No"
		if entry.IsOvertime {
			overtime = "Yes"
		}
		f.SetCellValue(sheetName, fmt.Sprintf("F%d", row), overtime)
		
		nightShift := "No"
		if entry.IsNightShift {
			nightShift = "Yes"
		}
		f.SetCellValue(sheetName, fmt.Sprintf("G%d", row), nightShift)
	}

	// Auto-adjust column widths
	for i := 0; i < len(headers); i++ {
		colName := string(rune('A' + i))
		f.SetColWidth(sheetName, colName, colName, 15)
	}

	// Add summary information
	summaryRow := len(req.Entries) + 4
	f.SetCellValue(sheetName, fmt.Sprintf("A%d", summaryRow), "Employee:")
	f.SetCellValue(sheetName, fmt.Sprintf("B%d", summaryRow), req.Employee.Name)
	
	f.SetCellValue(sheetName, fmt.Sprintf("A%d", summaryRow+1), "Pay Period:")
	f.SetCellValue(sheetName, fmt.Sprintf("B%d", summaryRow+1), 
		fmt.Sprintf("Week %d of %d (%s to %s)", 
			req.PayPeriod.WeekNumber, 
			req.PayPeriod.TotalWeeks,
			req.PayPeriod.WeekStart, 
			req.PayPeriod.WeekEnd))

	// Calculate total hours
	totalHours := 0.0
	overtimeHours := 0.0
	for _, entry := range req.Entries {
		totalHours += entry.Hours
		if entry.IsOvertime {
			overtimeHours += entry.Hours
		}
	}
	
	f.SetCellValue(sheetName, fmt.Sprintf("A%d", summaryRow+2), "Total Hours:")
	f.SetCellValue(sheetName, fmt.Sprintf("B%d", summaryRow+2), totalHours)
	
	f.SetCellValue(sheetName, fmt.Sprintf("A%d", summaryRow+3), "Overtime Hours:")
	f.SetCellValue(sheetName, fmt.Sprintf("B%d", summaryRow+3), overtimeHours)

	// Save file
	filename := baseFilename + ".xlsx"
	filepath := filepath.Join("uploads", filename)
	
	if err := f.SaveAs(filepath); err != nil {
		return "", err
	}

	return filepath, nil
}

func generatePDFFromExcel(excelPath, baseFilename string) (string, error) {
	// For now, create a simple HTML-based PDF approach
	// You can enhance this later with proper Excel->PDF conversion
	
	htmlContent := generateHTMLFromExcel(excelPath)
	if htmlContent == "" {
		return "", fmt.Errorf("failed to generate HTML content")
	}
	
	// Save HTML temporarily
	htmlPath := filepath.Join("uploads", baseFilename+".html")
	if err := os.WriteFile(htmlPath, []byte(htmlContent), 0644); err != nil {
		return "", err
	}
	
	// For now, return the HTML file (you can enhance this with wkhtmltopdf or similar)
	// In a production environment, you'd convert HTML to PDF here
	pdfPath := filepath.Join("uploads", baseFilename+".pdf")
	
	// Simple approach: copy HTML as PDF placeholder
	// Replace this with actual HTML->PDF conversion
	if err := os.WriteFile(pdfPath, []byte("PDF generation placeholder - integrate wkhtmltopdf here"), 0644); err != nil {
		return "", err
	}
	
	return pdfPath, nil
}

func generateHTMLFromExcel(excelPath string) string {
	// Read the Excel file and convert to HTML
	f, err := excelize.OpenFile(excelPath)
	if err != nil {
		return ""
	}
	defer f.Close()
	
	sheetName := f.GetSheetName(0)
	rows, err := f.GetRows(sheetName)
	if err != nil {
		return ""
	}
	
	html := `<!DOCTYPE html>
<html>
<head>
    <style>
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>Timecard Report</h1>
    <table>`
	
	for i, row := range rows {
		if i == 0 {
			html += "<tr>"
			for _, cell := range row {
				html += "<th>" + cell + "</th>"
			}
			html += "</tr>"
		} else {
			html += "<tr>"
			for _, cell := range row {
				html += "<td>" + cell + "</td>"
			}
			html += "</tr>"
		}
	}
	
	html += "</table></body></html>"
	return html
}

func sanitizeFilename(name string) string {
	// Remove special characters from filename
	result := ""
	for _, r := range name {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
			result += string(r)
		} else if r == ' ' {
			result += "_"
		}
	}
	return result
}

func stringPtr(s string) *string {
	return &s
}