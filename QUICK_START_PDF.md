# Quick Start: Excel to PDF in Go (No LibreOffice)

## TL;DR - Get PDF Working NOW

Your `main.go` currently won't work on Render.com because it needs LibreOffice installed. Here's the fastest fix:

---

## 🚀 Option 1: Free Solution (gofpdf)

### Step 1: Install Dependency

```bash
go get github.com/jung-kurt/gofpdf
```

### Step 2: Update Import in main.go

Add to your imports:
```go
import (
    // ... existing imports ...
    "github.com/jung-kurt/gofpdf"
)
```

Remove from imports (you don't need these anymore):
```go
"os/exec"
"path/filepath"
```

### Step 3: Replace the generatePDFFromExcel Function

Copy the entire function from `pdf_converter_alternative.go` into your `main.go`, replacing the existing `generatePDFFromExcel` function.

### Step 4: Test Locally

```bash
go run main.go
```

Then test with curl:
```bash
curl -X POST http://localhost:8080/api/generate-pdf \
  -H "Content-Type: application/json" \
  -d @test_request.json \
  --output test.pdf
```

### Step 5: Deploy to Render.com

```bash
git add .
git commit -m "Switch to gofpdf for PDF generation"
git push
```

**Done!** ✅ No LibreOffice needed, completely free.

---

## 💼 Option 2: Commercial Solution (UniDoc)

### Step 1: Install Dependencies

```bash
go get github.com/unidoc/unioffice
go get github.com/unidoc/unipdf/v3
```

### Step 2: Done!

Your `main.go` is already set up for UniDoc (I updated it). Just deploy:

```bash
git add .
git commit -m "Use UniDoc for PDF generation"
git push
```

**Note:** UniDoc requires a commercial license ($799/year) for production use. It's free for testing.

---

## 🧪 Testing

### Test Data (save as test_request.json)

```json
{
  "employee_name": "John Doe",
  "pay_period_num": 1,
  "year": 2025,
  "week_start_date": "2025-11-10T00:00:00Z",
  "week_number_label": "Week 1",
  "jobs": [
    {
      "job_code": "12215",
      "job_name": "201"
    },
    {
      "job_code": "92408",
      "job_name": "223"
    }
  ],
  "weeks": [
    {
      "week_number": 1,
      "week_start_date": "2025-11-10T00:00:00Z",
      "week_label": "Week 1",
      "entries": [
        {
          "date": "2025-11-10T00:00:00Z",
          "job_code": "12215",
          "hours": 8.0,
          "overtime": false,
          "night_shift": false
        },
        {
          "date": "2025-11-10T00:00:00Z",
          "job_code": "92408",
          "hours": 0.5,
          "overtime": false,
          "night_shift": true
        }
      ]
    }
  ]
}
```

### Test Commands

**Generate Excel:**
```bash
curl -X POST http://localhost:8080/api/generate-timecard \
  -H "Content-Type: application/json" \
  -d @test_request.json \
  --output test.xlsx
```

**Generate PDF:**
```bash
curl -X POST http://localhost:8080/api/generate-pdf \
  -H "Content-Type: application/json" \
  -d @test_request.json \
  --output test.pdf
```

Then open `test.pdf` to verify!

---

## 📊 Comparison

| Feature | gofpdf (Free) | UniDoc (Paid) | LibreOffice (Current) |
|---------|---------------|---------------|----------------------|
| **Cost** | Free | $799/year | Free |
| **Deployment** | Easy | Easy | Difficult |
| **Size** | ~5MB | ~15MB | ~700MB |
| **Speed** | Fast | Fast | Slow |
| **Quality** | Basic | High | Highest |
| **Works on Render** | ✅ Yes | ✅ Yes | ⚠️ Needs Docker |

---

## 🎯 My Recommendation

**Start with gofpdf** (Option 1):
- It's free
- It works immediately
- Good enough for most use cases
- Easy to deploy

**Upgrade to UniDoc later** if you need:
- Better formatting
- More Excel features
- Professional appearance

---

## 🔧 Troubleshooting

### "cannot find package"

```bash
go mod tidy
go get -u github.com/jung-kurt/gofpdf
```

### "undefined: generatePDFFromExcelAlternative"

You need to either:
- Copy the function from `pdf_converter_alternative.go` into `main.go`, OR
- Keep the file and change the function name in `generatePDFHandler`

### PDF is blank or broken

Check logs for errors:
```bash
go run main.go
# Look for "Generated PDF: X bytes"
```

### Render.com deployment fails

Make sure your `go.mod` includes the dependencies:
```bash
go mod tidy
git add go.mod go.sum
git commit -m "Update dependencies"
git push
```

---

## ✅ Success Checklist

- [ ] Installed PDF library (`gofpdf` or `unidoc`)
- [ ] Updated imports in `main.go`
- [ ] Replaced `generatePDFFromExcel` function
- [ ] Removed `os/exec` and `path/filepath` imports (no longer needed)
- [ ] Tested locally with curl
- [ ] Committed and pushed to Git
- [ ] Deployed to Render.com
- [ ] Tested `/api/generate-pdf` endpoint from production
- [ ] Tested from iOS app

---

## 🚀 One-Command Quick Fix (gofpdf)

If you want the absolute fastest solution:

```bash
# 1. Install
go get github.com/jung-kurt/gofpdf

# 2. Copy the alternative implementation
cat pdf_converter_alternative.go >> main.go

# 3. Update the function call in generatePDFHandler
# Change: pdfData, err := generatePDFFromExcel(excelData, ...)
# To:     pdfData, err := generatePDFFromExcelAlternative(excelData, ...)

# 4. Deploy
git add .
git commit -m "Switch to gofpdf for PDF generation"
git push
```

Done! 🎉

