# Timecard API Deployment Guide

## Prerequisites
1. GitHub account
2. Render.com account
3. Your iOS timecard app with the updated SendView.swift

## Step-by-Step Deployment

### 1. Create GitHub Repository

1. Go to GitHub.com and create a new repository named `timecard-api`
2. Clone the repository locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/timecard-api.git
   cd timecard-api
   ```

### 2. Set Up Go Project Structure

Create the following files in your repository:

**main.go** (copy from go-api-main.go)
**go.mod** (copy from go-mod.go)

Also create a **Dockerfile** for container deployment:

```dockerfile
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -o main .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/main .

EXPOSE 8080
CMD ["./main"]
```

### 3. Deploy to Render.com

1. Go to [Render.com](https://render.com) and sign up/log in
2. Click "New +" and select "Web Service"
3. Connect your GitHub repository
4. Configure the deployment:
   - **Name**: `timecard-api` (or your preferred name)
   - **Environment**: `Go`
   - **Build Command**: `go build -o main .`
   - **Start Command**: `./main`
   - **Plan**: Start with the free tier

5. Click "Create Web Service"

### 4. Get Your API URL

Once deployed, Render will give you a URL like:
`https://your-api-name.onrender.com`

### 5. Update Your iOS App

In `TimecardAPIService.swift`, update the `baseURL`:
```swift
private let baseURL = "https://your-api-name.onrender.com"
```

## Environment Variables (Optional)

You can set these in Render dashboard under "Environment":
- `PORT`: 8080 (usually auto-set by Render)
- Any other configuration variables you need

## Testing Your API

Test with curl:
```bash
curl -X POST https://your-api-name.onrender.com/api/generate-timecard \
  -H "Content-Type: application/json" \
  -d '{
    "employee": {
      "name": "Test User",
      "email": "test@example.com"
    },
    "entries": [
      {
        "date": "2024-01-01",
        "jobNumber": "JOB001",
        "code": "REG",
        "hours": 8.0,
        "notes": "Regular work",
        "isOvertime": false,
        "isNightShift": false
      }
    ],
    "payPeriod": {
      "weekStart": "2024-01-01",
      "weekEnd": "2024-01-07",
      "weekNumber": 1,
      "totalWeeks": 1
    }
  }'
```

## Enhancements

### Adding PDF Generation

To improve PDF generation, you can integrate wkhtmltopdf:

1. Add to Dockerfile:
```dockerfile
RUN apk add --no-cache wkhtmltopdf
```

2. Update the `generatePDFFromExcel` function in main.go:
```go
func generatePDFFromExcel(excelPath, baseFilename string) (string, error) {
    htmlContent := generateHTMLFromExcel(excelPath)
    htmlPath := filepath.Join("uploads", baseFilename+".html")
    pdfPath := filepath.Join("uploads", baseFilename+".pdf")
    
    // Write HTML file
    if err := os.WriteFile(htmlPath, []byte(htmlContent), 0644); err != nil {
        return "", err
    }
    
    // Convert HTML to PDF using wkhtmltopdf
    cmd := exec.Command("wkhtmltopdf", "--page-size", "A4", htmlPath, pdfPath)
    if err := cmd.Run(); err != nil {
        return "", fmt.Errorf("PDF conversion failed: %v", err)
    }
    
    return pdfPath, nil
}
```

### Adding File Cleanup

Add a cleanup routine to remove old files:

```go
func cleanupOldFiles() {
    // Run every hour to cleanup files older than 24 hours
    ticker := time.NewTicker(time.Hour)
    go func() {
        for range ticker.C {
            filepath.Walk("uploads", func(path string, info os.FileInfo, err error) error {
                if err != nil {
                    return nil
                }
                if time.Since(info.ModTime()) > 24*time.Hour {
                    os.Remove(path)
                }
                return nil
            })
        }
    }()
}
```

## Troubleshooting

1. **API not responding**: Check Render logs in the dashboard
2. **Build failures**: Ensure go.mod is properly formatted
3. **CORS issues**: The API includes CORS middleware, but verify the origins
4. **File generation errors**: Check the logs for specific Excel/PDF generation errors

## Next Steps

1. Deploy the Go API to Render.com
2. Update your iOS app with the correct API URL
3. Test the integration
4. Enhance PDF generation if needed
5. Add authentication if required for production use