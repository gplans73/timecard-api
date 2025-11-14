package main

import (
	"bytes"
	"fmt"
	"log"
	"os"

	"github.com/xuri/excelize/v2"
	"github.com/jung-kurt/gofpdf"
)

// Alternative PDF generation using gofpdf (simpler, more control)
func generatePDFFromExcelAlternative(excelData []byte, filename string) ([]byte, error) {
	// Save Excel data to temp file
	tmpExcel, err := os.CreateTemp("", "timecard-*.xlsx")
	if err != nil {
		return nil, fmt.Errorf("create temp excel: %w", err)
	}
	tmpExcelPath := tmpExcel.Name()
	defer os.Remove(tmpExcelPath)

	if _, err := tmpExcel.Write(excelData); err != nil {
		tmpExcel.Close()
		return nil, fmt.Errorf("write excel: %w", err)
	}
	tmpExcel.Close()

	// Open Excel with Excelize
	f, err := excelize.OpenFile(tmpExcelPath)
	if err != nil {
		return nil, fmt.Errorf("open excel: %w", err)
	}
	defer f.Close()

	// Create PDF
	pdf := gofpdf.New("L", "mm", "Letter", "") // Landscape, Letter size
	pdf.SetMargins(10, 10, 10)
	pdf.SetAutoPageBreak(true, 10)

	// Process each sheet
	sheets := f.GetSheetList()
	for sheetIdx, sheetName := range sheets {
		if sheetIdx > 0 {
			pdf.AddPage()
		} else {
			pdf.AddPage()
		}

		log.Printf("Processing sheet: %s", sheetName)

		// Add sheet title
		pdf.SetFont("Arial", "B", 14)
		pdf.CellFormat(0, 10, sheetName, "", 1, "C", false, 0, "")
		pdf.Ln(5)

		// Get all rows
		rows, err := f.GetRows(sheetName)
		if err != nil {
			log.Printf("Error reading sheet %s: %v", sheetName, err)
			continue
		}

		// Determine max columns
		maxCols := 0
		for _, row := range rows {
			if len(row) > maxCols {
				maxCols = len(row)
			}
		}

		if maxCols == 0 {
			continue
		}

		// Calculate column widths
		pageWidth := 279.0 - 20.0 // Letter landscape width minus margins
		colWidth := pageWidth / float64(maxCols)
		if colWidth < 15 {
			colWidth = 15 // Minimum column width
		}

		// Set font for data
		pdf.SetFont("Arial", "", 8)

		// Write rows
		for rowIdx, row := range rows {
			// Skip if all cells are empty
			isEmpty := true
			for _, cell := range row {
				if cell != "" {
					isEmpty = false
					break
				}
			}
			if isEmpty {
				continue
			}

			// Check if we need a new page
			if pdf.GetY() > 190 { // Near bottom of page
				pdf.AddPage()
			}

			// Determine row style (headers are usually bold)
			if rowIdx < 4 || rowIdx == 14 { // Rows 1-4 and 15 are headers
				pdf.SetFont("Arial", "B", 9)
				pdf.SetFillColor(220, 220, 220) // Light gray background
			} else {
				pdf.SetFont("Arial", "", 8)
				pdf.SetFillColor(255, 255, 255) // White background
			}

			// Write cells
			x := pdf.GetX()
			y := pdf.GetY()
			maxHeight := 6.0

			for colIdx := 0; colIdx < maxCols; colIdx++ {
				cellValue := ""
				if colIdx < len(row) {
					cellValue = row[colIdx]
				}

				// Truncate if too long
				if len(cellValue) > 20 {
					cellValue = cellValue[:17] + "..."
				}

				// Set border style
				border := "1"
				if rowIdx < 4 || rowIdx == 14 {
					border = "1" // Full border for headers
				}

				// Align numbers to right, text to left
				align := "L"
				if isNumeric(cellValue) {
					align = "R"
				}

				pdf.CellFormat(colWidth, maxHeight, cellValue, border, 0, align, true, 0, "")
			}

			pdf.Ln(-1) // Move to next line
		}
	}

	// Output to buffer
	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		return nil, fmt.Errorf("write pdf: %w", err)
	}

	pdfData := buf.Bytes()
	log.Printf("Generated PDF with gofpdf: %d bytes", len(pdfData))
	return pdfData, nil
}

// Helper to check if string is numeric
func isNumeric(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if (r < '0' || r > '9') && r != '.' && r != '-' && r != '+' {
			return false
		}
	}
	return true
}
