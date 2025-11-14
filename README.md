# Timecard API

A Go web service that generates Excel timecard files from JSON data.

## API Endpoints

### POST /api/generate-timecard

Generates an Excel timecard file from the provided data.

**Request Body:**
```json
{
  "employee": {
    "name": "John Doe",
    "email": "john@example.com"
  },
  "entries": [
    {
      "id": "uuid",
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
    "totalWeeks": 2
  }
}
```

**Response:**
Returns an Excel file as attachment.

### GET /health

Health check endpoint.

## Deployment

This service is designed to be deployed on Render.com using Docker.

## Local Development

```bash
go mod download
go run main.go
```

Server will start on port 8080 (or PORT environment variable).

## Required Files

- `main.go` - Main server code
- `go.mod` - Go module dependencies
- `template.xlsx` - Excel template file
- `Dockerfile` - Docker configuration