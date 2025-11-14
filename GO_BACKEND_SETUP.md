# Go Backend Setup Guide

This guide will help you deploy and configure the Go backend API for your timecard app.

## Prerequisites

- Go 1.21 or later
- Git
- A Render.com account (or another hosting service)
- SMTP credentials (Gmail, SendGrid, etc.)

## Local Development

### 1. Set Up the Project

Create a new directory for your Go backend:

```bash
mkdir timecard-api
cd timecard-api
```

Copy the `main.go` file to this directory.

### 2. Initialize Go Module

```bash
go mod init github.com/yourusername/timecard-api
go mod tidy
```

This will create `go.mod` and `go.sum` files and download dependencies.

### 3. Add Template File

Make sure you have the `template.xlsx` file in the same directory as `main.go`. This is the Excel template used for generating timecards.

### 4. Set Environment Variables

Create a `.env` file (don't commit this to Git):

```bash
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM=your-email@gmail.com
```

**For Gmail:**
1. Enable 2-factor authentication
2. Go to https://myaccount.google.com/apppasswords
3. Generate an App Password
4. Use that password (not your regular password)

### 5. Load Environment Variables

Install godotenv for local development:

```bash
go get github.com/joho/godotenv
```

Update `main.go` to load `.env`:

```go
import (
    // ... other imports
    "github.com/joho/godotenv"
)

func main() {
    // Load .env file in development
    if err := godotenv.Load(); err != nil {
        log.Println("No .env file found, using environment variables")
    }
    
    // ... rest of main
}
```

### 6. Run Locally

```bash
go run main.go
```

The server will start on `http://localhost:8080`

Test the health endpoint:

```bash
curl http://localhost:8080/health
```

## Deployment to Render.com

### 1. Prepare for Deployment

Create a `.gitignore` file:

```
.env
*.xlsx
!template.xlsx
```

### 2. Create Git Repository

```bash
git init
git add .
git commit -m "Initial commit"
```

Push to GitHub:

```bash
git remote add origin https://github.com/yourusername/timecard-api.git
git push -u origin main
```

### 3. Deploy to Render

1. Go to https://render.com
2. Sign up or log in
3. Click "New +" → "Web Service"
4. Connect your GitHub repository
5. Configure the service:

**Settings:**
- Name: `timecard-api`
- Environment: `Go`
- Build Command: `go build -o main main.go`
- Start Command: `./main`
- Instance Type: Free (or higher for production)

**Environment Variables:**
Add these in the Render dashboard:

```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM=your-email@gmail.com
```

6. Click "Create Web Service"

### 4. Wait for Deployment

Render will:
1. Clone your repository
2. Build the Go application
3. Start the server
4. Assign a URL like `https://timecard-api.onrender.com`

### 5. Test Your Deployment

```bash
curl https://timecard-api.onrender.com/health
```

## Alternative Hosting Options

### Heroku

1. Install Heroku CLI
2. Create `Procfile`:
```
web: ./main
```

3. Deploy:
```bash
heroku create timecard-api
heroku config:set SMTP_HOST=smtp.gmail.com
heroku config:set SMTP_PORT=587
heroku config:set SMTP_USERNAME=your-email@gmail.com
heroku config:set SMTP_PASSWORD=your-app-password
git push heroku main
```

### Railway

1. Go to https://railway.app
2. Connect GitHub repository
3. Add environment variables
4. Deploy automatically

### DigitalOcean App Platform

1. Go to DigitalOcean App Platform
2. Create new app from GitHub
3. Set environment variables
4. Deploy

## Configuration

### SMTP Providers

#### Gmail
```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
```
Use App Passwords (requires 2FA)

#### SendGrid
```
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=your-sendgrid-api-key
```

#### AWS SES
```
SMTP_HOST=email-smtp.us-east-1.amazonaws.com
SMTP_PORT=587
SMTP_USERNAME=your-ses-smtp-username
SMTP_PASSWORD=your-ses-smtp-password
```

#### Microsoft 365
```
SMTP_HOST=smtp.office365.com
SMTP_PORT=587
SMTP_USERNAME=your-email@company.com
SMTP_PASSWORD=your-password
```

## Update iOS App

Once deployed, update `TimecardAPIService.swift`:

```swift
private let baseURL = "https://your-app.onrender.com"
```

## Testing

### Test Generate Timecard

```bash
curl -X POST https://your-api-url.com/api/generate-timecard \
  -H "Content-Type: application/json" \
  -d '{
    "employee_name": "Test User",
    "pay_period_num": 1,
    "year": 2025,
    "week_start_date": "2025-01-06T00:00:00Z",
    "week_number_label": "Week 1",
    "jobs": [{"job_code": "TEST", "job_name": "Test Job"}],
    "entries": [{
      "date": "2025-01-06T00:00:00Z",
      "job_code": "TEST",
      "hours": 8.0,
      "overtime": false
    }]
  }' \
  --output test.xlsx
```

### Test Email Timecard

```bash
curl -X POST https://your-api-url.com/api/email-timecard \
  -H "Content-Type: application/json" \
  -d '{
    "employee_name": "Test User",
    "pay_period_num": 1,
    "year": 2025,
    "week_start_date": "2025-01-06T00:00:00Z",
    "week_number_label": "Week 1",
    "jobs": [{"job_code": "TEST", "job_name": "Test Job"}],
    "entries": [{
      "date": "2025-01-06T00:00:00Z",
      "job_code": "TEST",
      "hours": 8.0,
      "overtime": false
    }],
    "to": "your-email@example.com",
    "subject": "Test Timecard",
    "body": "This is a test."
  }'
```

## Monitoring

### Render Logs

View logs in Render dashboard:
1. Go to your service
2. Click "Logs" tab
3. Monitor requests and errors

### Health Checks

Set up a monitoring service like:
- UptimeRobot (free)
- Pingdom
- Better Uptime

Configure to ping `/health` every 5 minutes.

## Troubleshooting

### "SMTP configuration error"

Check environment variables are set correctly in Render dashboard.

### "Connection timeout"

Free tier may sleep after inactivity. First request takes 30-60 seconds. Consider:
- Using a paid tier for instant startup
- Implementing a keep-alive ping from iOS app

### "Template not found"

Ensure `template.xlsx` is committed to Git and deployed.

### "Invalid JSON"

Check date format is ISO 8601: `2025-01-06T00:00:00Z`

## Security Recommendations

### For Production

1. **Add API Key Authentication:**

```go
func requireAPIKey(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        key := r.Header.Get("X-API-Key")
        if key != os.Getenv("API_KEY") {
            http.Error(w, "unauthorized", http.StatusUnauthorized)
            return
        }
        next(w, r)
    }
}

http.HandleFunc("/api/generate-timecard", requireAPIKey(generateTimecardHandler))
```

Then in Swift:
```swift
urlRequest.setValue("your-api-key", forHTTPHeaderField: "X-API-Key")
```

2. **Rate Limiting:**

Use a package like `golang.org/x/time/rate`

3. **CORS Configuration:**

Only allow requests from your iOS app domain.

4. **HTTPS Only:**

Render provides this automatically.

5. **Input Validation:**

Add length limits and sanitization.

## Maintenance

### Updating the Template

1. Update `template.xlsx` locally
2. Commit and push:
```bash
git add template.xlsx
git commit -m "Update Excel template"
git push
```
3. Render will automatically redeploy

### Updating Dependencies

```bash
go get -u ./...
go mod tidy
git commit -am "Update dependencies"
git push
```

### Viewing Logs

```bash
# Render CLI
render logs
```

## Cost Estimate

**Render.com Free Tier:**
- ✅ 750 hours/month free
- ✅ Automatic HTTPS
- ✅ Custom domains
- ⚠️ Sleeps after 15 min inactivity

**Render.com Starter ($7/month):**
- ✅ Always on
- ✅ Faster startup
- ✅ Better performance

**SendGrid Free Tier:**
- ✅ 100 emails/day free
- ✅ More than enough for personal use

**Total Cost:**
- Development: $0/month (free tiers)
- Production: $7/month (Render Starter)

## Support

For issues:
1. Check Render logs
2. Test with curl commands
3. Verify environment variables
4. Review API_INTEGRATION.md documentation

---

**Created:** November 8, 2025
