# Excel to PDF Conversion in Go - Complete Guide

## Current Implementation (LibreOffice)

Your code currently uses LibreOffice's `soffice` command-line tool:

```go
cmd := exec.Command("soffice", "--headless", "--convert-to", "pdf", ...)
```

**Pros:**
- ✅ High-quality PDF output
- ✅ Perfect formatting preservation
- ✅ Handles complex Excel features (formulas, charts, etc.)

**Cons:**
- ❌ Requires LibreOffice installed on server (~500MB)
- ❌ Slow (spawns external process)
- ❌ Complex deployment on Render.com
- ❌ Memory intensive

---

## Option 1: UniDoc (Pure Go) ⭐ RECOMMENDED

**Library:** `github.com/unidoc/unioffice` + `github.com/unidoc/unipdf/v3`

### Installation

```bash
go get github.com/unidoc/unioffice
go get github.com/unidoc/unipdf/v3
```

### Pros
- ✅ Pure Go (no external dependencies)
- ✅ Fast (no process spawning)
- ✅ Good Excel support
- ✅ Professional PDF output
- ✅ Small deployment size

### Cons
- ⚠️ **Commercial license required** for production ($799/year per developer)
- ⚠️ Free for evaluation and testing
- ❌ Styling may not be 100% identical to LibreOffice

### Implementation

I've already updated your `main.go` with this implementation. The key function is:

```go
func generatePDFFromExcel(excelData []byte, filename string) ([]byte, error) {
    // Open Excel with UniDoc
    wb, err := spreadsheet.Open(tmpExcelPath)
    
    // Create PDF
    c := creator.New()
    
    // Process sheets and cells
    for _, sheet := range wb.Sheets() {
        // Read cells, create table, add to PDF
    }
    
    return pdfData, nil
}
```

### Usage

No changes needed - just install the dependencies:

```bash
go get github.com/unidoc/unioffice
go get github.com/unidoc/unipdf/v3
go mod tidy
```

Then deploy!

---

## Option 2: gofpdf + Excelize (Pure Go, Free)

**Library:** `github.com/jung-kurt/gofpdf` + your existing `excelize`

### Installation

```bash
go get github.com/jung-kurt/gofpdf
```

### Pros
- ✅ Pure Go (no external dependencies)
- ✅ **Completely free** (MIT license)
- ✅ Fast
- ✅ Uses your existing Excelize library
- ✅ Small deployment size
- ✅ Good control over PDF layout

### Cons
- ⚠️ Requires manual styling/formatting
- ⚠️ Won't preserve complex Excel formatting
- ⚠️ More code to maintain

### Implementation

I've created `pdf_converter_alternative.go` with this implementation:

```go
func generatePDFFromExcelAlternative(excelData []byte, filename string) ([]byte, error) {
    // Open Excel with Excelize (you already have this)
    f, err := excelize.OpenFile(tmpExcelPath)
    
    // Create PDF with gofpdf
    pdf := gofpdf.New("L", "mm", "Letter", "")
    
    // Read Excel rows with Excelize
    rows, err := f.GetRows(sheetName)
    
    // Write to PDF
    for _, row := range rows {
        for _, cell := range row {
            pdf.CellFormat(colWidth, height, cell, "1", 0, "L", true, 0, "")
        }
    }
    
    return pdfData, nil
}
```

### To Use This Option

1. Install gofpdf:
   ```bash
   go get github.com/jung-kurt/gofpdf
   ```

2. In `main.go`, replace the `generatePDFFromExcel` function with the one from `pdf_converter_alternative.go`

3. Or rename the function and call it instead:
   ```go
   pdfData, err := generatePDFFromExcelAlternative(excelData, ...)
   ```

---

## Option 3: Custom PDF with UniPDF Only

**Library:** `github.com/unidoc/unipdf/v3` (without unioffice)

### Installation

```bash
go get github.com/unidoc/unipdf/v3
```

### Approach

Instead of reading Excel, manually create PDF from your data structures:

```go
func generatePDFDirectly(req TimecardRequest) ([]byte, error) {
    c := creator.New()
    
    // Add title
    p := c.NewParagraph(req.EmployeeName)
    c.Draw(p)
    
    // Create table from your data
    table := c.NewTable(7) // 7 days
    
    for _, entry := range req.Entries {
        // Add rows directly from your structs
        cell := table.NewCell()
        cell.SetContent(c.NewParagraph(entry.JobCode))
    }
    
    c.Draw(table)
    return pdfData, nil
}
```

### Pros
- ✅ Complete control
- ✅ No Excel parsing needed
- ✅ Fast

### Cons
- ⚠️ Requires commercial license
- ⚠️ More code to write
- ⚠️ Can't leverage Excel template

---

## Option 4: Keep LibreOffice but Optimize

If you want to keep LibreOffice, here's how to make it work better on Render.com:

### Dockerfile for Render.com

Create a `Dockerfile`:

```dockerfile
FROM golang:1.21-alpine

# Install LibreOffice
RUN apk add --no-cache libreoffice

# Copy your app
WORKDIR /app
COPY . .

# Build
RUN go mod download
RUN go build -o server .

# Run
CMD ["./server"]
```

### Render.com Configuration

In `render.yaml`:

```yaml
services:
  - type: web
    name: timecard-api
    env: docker
    dockerfilePath: ./Dockerfile
```

### Pros
- ✅ Best PDF quality
- ✅ Perfect formatting

### Cons
- ❌ Large Docker image (~700MB)
- ❌ Slower builds
- ❌ Higher memory usage
- ❌ Slower cold starts

---

## Comparison Table

| Option | Cost | Quality | Speed | Deployment Size | Complexity |
|--------|------|---------|-------|-----------------|------------|
| **LibreOffice** | Free | ⭐⭐⭐⭐⭐ | ⭐⭐ | ❌ Large | ⭐⭐⭐ |
| **UniDoc** | $799/yr | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ✅ Small | ⭐⭐⭐⭐ |
| **gofpdf** | Free | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ✅ Small | ⭐⭐⭐ |
| **UniPDF Direct** | $799/yr | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ✅ Small | ⭐⭐ |

---

## My Recommendation

### For Immediate Use (Free)

**Use Option 2: gofpdf + Excelize**

Reasons:
- ✅ Completely free
- ✅ No external dependencies
- ✅ Easy deployment on Render.com
- ✅ Fast performance
- ✅ You already have Excelize

Steps:
1. `go get github.com/jung-kurt/gofpdf`
2. Replace `generatePDFFromExcel` with the alternative version
3. Deploy

### For Production (Commercial)

**Use Option 1: UniDoc**

Reasons:
- ✅ Professional quality
- ✅ Better Excel feature support
- ✅ Worth the investment for production app
- ✅ Active development and support

---

## Testing Your PDF Generation

### Test Endpoint

Add this test endpoint to your `main.go`:

```go
func testPDFHandler(w http.ResponseWriter, r *http.Request) {
    // Generate sample timecard
    req := TimecardRequest{
        EmployeeName: "Test Employee",
        PayPeriodNum: 1,
        Year: 2025,
        // ... sample data
    }
    
    excelData, _ := generateExcelFile(req)
    pdfData, err := generatePDFFromExcel(excelData, "test.xlsx")
    
    if err != nil {
        http.Error(w, err.Error(), 500)
        return
    }
    
    w.Header().Set("Content-Type", "application/pdf")
    w.Write(pdfData)
}
```

Register it:
```go
http.HandleFunc("/test-pdf", testPDFHandler)
```

Then visit: `https://your-app.onrender.com/test-pdf`

---

## Code Changes Summary

### Current Code (Using LibreOffice)

```go
// Requires LibreOffice installed
cmd := exec.Command("soffice", "--headless", ...)
```

### Option 1 Code (UniDoc) - ALREADY APPLIED

```go
import "github.com/unidoc/unioffice/spreadsheet"
import "github.com/unidoc/unipdf/v3/creator"

func generatePDFFromExcel(...) {
    wb, _ := spreadsheet.Open(tmpExcelPath)
    c := creator.New()
    // ... process sheets
}
```

### Option 2 Code (gofpdf) - IN pdf_converter_alternative.go

```go
import "github.com/jung-kurt/gofpdf"

func generatePDFFromExcelAlternative(...) {
    f, _ := excelize.OpenFile(tmpExcelPath)
    pdf := gofpdf.New("L", "mm", "Letter", "")
    rows, _ := f.GetRows(sheetName)
    // ... write rows to PDF
}
```

---

## Next Steps

1. **Choose an option** based on your budget and requirements
2. **Install dependencies** with `go get`
3. **Update `generatePDFFromExcel`** function if needed
4. **Test locally** with `go run main.go`
5. **Deploy to Render.com** (it will work without LibreOffice!)
6. **Test the `/api/generate-pdf` endpoint** from your iOS app

---

## License Notes

### UniDoc Licensing

- **Free for:** Evaluation, testing, open-source projects
- **Paid for:** Commercial production use
- **Price:** $799/year per developer
- **Website:** https://unidoc.io/pricing

### gofpdf Licensing

- **License:** MIT (completely free for any use)
- **No restrictions**

---

## Questions?

**Q: Which should I use?**
A: Start with **gofpdf** (free), upgrade to **UniDoc** if you need better quality.

**Q: Will this work on Render.com?**
A: Yes! Both options are pure Go with no external dependencies.

**Q: What about PDF quality?**
A: gofpdf will be simpler/plainer, UniDoc will look more like the original Excel.

**Q: Do I need to change my Swift code?**
A: No! The API endpoint stays the same, just the backend changes.

---

## Current Status

✅ **UniDoc implementation** is already in your `main.go`
✅ **gofpdf alternative** is in `pdf_converter_alternative.go`
⏳ **Ready to test** - just install dependencies and deploy!

