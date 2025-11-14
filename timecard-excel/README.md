# Timecard Excel API

A Go-based REST API that generates Excel timecards from JSON data and optionally emails them with PDF copies.

## Features

- Generate Excel timecard files from JSON timecard data
- Email timecards with both Excel and PDF attachments
- Support for Week 1 and Week 2 templates
- CORS support for web applications
- Health check endpoint
- Easy deployment to Render

## API Endpoints

### `POST /excel`
Generates an Excel timecard file and optionally emails it.

**Request Body:**
```json
{
  "employeeName": "John Doe",
  "weekNumber": 1,
  "rows": [
    {
      "date": "2024-01-01",
      "project": "Project A",
      "hours": 8.0,
      "type": "Regular",
      "notes": "Development work"
    }
  ],
  "totalOC": 40.0,
  "totalOT": 5.0,
  "sendEmail": true,
  "emailTo": ["manager@company.com", "hr@company.com"],
  "emailSubject": "Timecard - John Doe - Week 1",
  "emailBody": "Please find attached timecard for approval."
}
```

**Response:**
- Returns Excel file as download
- Headers include email status if email was requested

### `GET /health`
Health check endpoint for monitoring.

## Environment Variables

### Required for Email Functionality:
- `SMTP_HOST` - SMTP server hostname (e.g., smtp.gmail.com)
- `SMTP_PORT` - SMTP server port (e.g., 587)
- `SMTP_USER` - SMTP username (your email)
- `SMTP_PASSWORD` - SMTP password (use app-specific password for Gmail)
- `FROM_EMAIL` - From email address
- `FROM_NAME` - From display name

### Optional:
- `PORT` - Server port (default: 8080)

## Gmail Setup

For Gmail, you need to:
1. Enable 2-factor authentication
2. Generate an App Password
3. Use the App Password as `SMTP_PASSWORD`

## Deploy to Render

1. Fork/clone this repository
2. Connect your GitHub repo to Render
3. Create a new Web Service
4. Set environment variables in Render dashboard:
   ```
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=587
   SMTP_USER=your-email@gmail.com
   SMTP_PASSWORD=your-app-password
   FROM_EMAIL=your-email@gmail.com
   FROM_NAME=Timecard System
   ```
5. Deploy!

Your API will be available at: `https://your-service-name.onrender.com`

## Local Development

1. Clone the repository
2. Create a `.env` file with your environment variables
3. Run: `go mod tidy`
4. Run: `go run main.go`
5. Server starts at `http://localhost:8080`

## Testing

Test the API with curl:

```bash
curl -X POST http://localhost:8080/excel \
  -H "Content-Type: application/json" \
  -d '{
    "employeeName": "Test User",
    "weekNumber": 1,
    "rows": [
      {"date": "2024-01-01", "project": "Test", "hours": 8.0, "type": "Regular", "notes": "Testing"}
    ],
    "sendEmail": false
  }' \
  --output timecard.xlsx
```

## Template File

Make sure you have a `template.xlsx` file in your project root. This serves as the base template for generating timecards.