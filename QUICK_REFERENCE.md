# Quick Reference - Go API Integration

## 🚀 Quick Start

### 1. Deploy Go Backend
```bash
# On Render.com
1. Create Web Service from GitHub repo
2. Set environment variables (SMTP_*)
3. Deploy
```

### 2. Update iOS App
```swift
// In TimecardAPIService.swift, line 13:
private let baseURL = "https://your-app.onrender.com"
```

### 3. Test
```bash
chmod +x test-api.sh
./test-api.sh https://your-app.onrender.com
```

---

## 📡 API Endpoints

### Health Check
```bash
GET /health
Response: "ok"
```

### Generate Excel
```bash
POST /api/generate-timecard
Content-Type: application/json
Response: Excel file (.xlsx)
```

### Send Email
```bash
POST /api/email-timecard
Content-Type: application/json
Response: {"status": "sent"}
```

---

## 🔑 Environment Variables

Set these in your hosting dashboard:

```bash
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM=your-email@gmail.com
```

**Gmail Setup:**
1. Enable 2FA at https://myaccount.google.com
2. Generate App Password at https://myaccount.google.com/apppasswords
3. Use that password (not regular password)

---

## 📦 JSON Request Format

### Generate/Email Request

```json
{
  "employee_name": "John Doe",
  "pay_period_num": 1,
  "year": 2025,
  "week_start_date": "2025-01-06T00:00:00Z",
  "week_number_label": "Week 1",
  "jobs": [
    {"job_code": "JOB001", "job_name": "Construction"}
  ],
  "entries": [
    {
      "date": "2025-01-06T00:00:00Z",
      "job_code": "JOB001",
      "hours": 8.0,
      "overtime": false
    }
  ]
}
```

### Email Request (additional fields)

```json
{
  // ... all above fields, plus:
  "to": "manager@company.com",
  "cc": "supervisor@company.com",
  "subject": "Timecard - John Doe",
  "body": "Please find attached."
}
```

---

## 🧪 Test Commands

### Test Health
```bash
curl https://your-api.onrender.com/health
```

### Test Generate
```bash
curl -X POST https://your-api.onrender.com/api/generate-timecard \
  -H "Content-Type: application/json" \
  -d '{...}' \
  --output timecard.xlsx
```

### Test Email
```bash
curl -X POST https://your-api.onrender.com/api/email-timecard \
  -H "Content-Type: application/json" \
  -d '{...}'
```

---

## 🔧 Swift Code Snippets

### Generate Excel
```swift
let (excelData, _) = try await apiService.generateTimecardFiles(
    employeeName: "John Doe",
    emailRecipients: ["manager@company.com"],
    entries: allEntries,
    weekStart: startDate,
    weekEnd: endDate,
    weekNumber: 1,
    totalWeeks: 2,
    ppNumber: 1
)

// Use excelData
let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("timecard.xlsx")
try excelData.write(to: url)
```

### Send Email
```swift
try await apiService.emailTimecard(
    employeeName: "John Doe",
    emailRecipients: ["manager@company.com"],
    ccRecipients: ["hr@company.com"],
    subject: "Timecard - Week 1",
    body: "Please find attached.",
    entries: allEntries,
    weekStart: startDate,
    weekEnd: endDate,
    weekNumber: 1,
    totalWeeks: 2,
    ppNumber: 1
)
```

---

## 🐛 Common Issues

### "Invalid JSON"
**Fix:** Check field names are snake_case
- ✅ `employee_name`
- ❌ `employeeName`

### "Date parsing failed"
**Fix:** Use ISO 8601 format with timezone
```swift
let formatter = ISO8601DateFormatter()
formatter.timeZone = TimeZone(secondsFromGMT: 0)
```

### "SMTP configuration error"
**Fix:** Set all SMTP_* environment variables

### "Connection timeout"
**Fix:** Wait 30-60s for cold start, or use paid tier

---

## 📊 Response Codes

| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | ✅ Use response |
| 400 | Bad Request | ❌ Check JSON format |
| 405 | Wrong Method | ❌ Use POST |
| 500 | Server Error | ❌ Check logs |

---

## 📁 Files Overview

| File | Purpose |
|------|---------|
| `main.go` | Go backend API |
| `template.xlsx` | Excel template |
| `TimecardAPIService.swift` | iOS API client |
| `SendView.swift` | iOS send UI |
| `API_INTEGRATION.md` | Full integration guide |
| `GO_BACKEND_SETUP.md` | Deployment guide |
| `test-api.sh` | Test script |

---

## 💰 Cost

**Free Tier:**
- Render.com: 750 hours/month
- SendGrid: 100 emails/day
- **Total: $0/month**

**Production:**
- Render Starter: $7/month (always on)
- SendGrid: Free tier sufficient
- **Total: $7/month**

---

## 📚 Documentation

- **Quick Start:** This file
- **Full Integration:** `API_INTEGRATION.md`
- **Deployment:** `GO_BACKEND_SETUP.md`
- **Summary:** `INTEGRATION_SUMMARY.md`

---

## ✅ Checklist

### Backend Setup
- [ ] Go backend deployed
- [ ] SMTP variables set
- [ ] Template.xlsx included
- [ ] Health check passes

### iOS Integration
- [ ] API URL updated
- [ ] Test API calls work
- [ ] Error handling tested
- [ ] Email method toggle works

### Testing
- [ ] Health endpoint responds
- [ ] Excel generation works
- [ ] Email sending works
- [ ] Error messages display

---

## 🆘 Help

**Stuck?**
1. Check logs in Render dashboard
2. Test with curl/test-api.sh
3. Review API_INTEGRATION.md
4. Enable debug logging in Swift

**Still need help?**
- Check environment variables
- Verify template.xlsx exists
- Test SMTP credentials
- Review request JSON format

---

**Last Updated:** November 8, 2025
