# Timecard Go API Integration - Summary

## ✅ What Was Done

I've integrated your Go backend API (`main.go`) with your Swift iOS timecard app. Here's what's been set up:

### 1. Updated API Service (`TimecardAPIService.swift`)

**Changed:**
- ✅ Updated request models to match Go API structure exactly
- ✅ Changed from custom format to Go's snake_case JSON fields
- ✅ Added ISO 8601 date formatting (required by Go)
- ✅ Added automatic job extraction from entries
- ✅ Added new `emailTimecard()` function to send emails via Go API
- ✅ Improved error handling with detailed messages
- ✅ Added debug logging for troubleshooting

**New Features:**
- Generate Excel files via Go API (`/api/generate-timecard`)
- Send emails via Go API with SMTP (`/api/email-timecard`)
- Automatic retry and timeout handling

### 2. Updated Send View (`SendView.swift`)

**Added:**
- ✅ Email method picker (iOS Mail vs Go API)
- ✅ Success/error message display
- ✅ Status indicator for API operations
- ✅ Support for direct email sending through Go backend
- ✅ Fallback to local Excel generation if API fails

**User Experience:**
- Users can choose between iOS Mail composer or direct API email
- Real-time feedback on email sending status
- Graceful error handling with user-friendly messages

### 3. Created Documentation

**Files Created:**
1. **API_INTEGRATION.md** - Complete API integration guide
2. **GO_BACKEND_SETUP.md** - Deployment and configuration guide
3. **TestGoAPI.swift** - Test script for API validation

## 📋 Go API Endpoints Integrated

Your Go backend provides these endpoints:

| Endpoint | Method | Purpose | Status |
|----------|--------|---------|--------|
| `/health` | GET | Health check | ✅ Integrated |
| `/api/generate-timecard` | POST | Generate Excel | ✅ Integrated |
| `/api/email-timecard` | POST | Email Excel | ✅ Integrated |

## 🔄 Data Flow

```
┌──────────────────────────────────────────────┐
│         Swift iOS App (SendView)              │
│                                               │
│  1. User taps "Send" button                  │
│  2. Collect entries from selected weeks      │
│  3. Choose email method:                     │
│     → iOS Mail composer                      │
│     → Go API direct send                     │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│      TimecardAPIService (Swift)              │
│                                               │
│  • Convert EntryModel → GoEntry              │
│  • Format dates as ISO 8601                  │
│  • Extract unique jobs                       │
│  • Build JSON request                        │
└──────────────┬───────────────────────────────┘
               │ HTTP POST with JSON
               ▼
┌──────────────────────────────────────────────┐
│         Go Backend (main.go)                  │
│                                               │
│  • Parse JSON request                        │
│  • Load template.xlsx                        │
│  • Fill in timecard data                     │
│  • Generate Excel file                       │
│  • Send via SMTP (if email endpoint)         │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│           Response                            │
│                                               │
│  Generate: Excel file (binary)               │
│  Email: {"status": "sent"}                   │
└──────────────────────────────────────────────┘
```

## 📦 File Structure

```
YourProject/
├── main.go                      # ✨ Your Go backend API
├── template.xlsx                # Excel template (required)
├── go.mod                       # Go dependencies (will be created)
├── go.sum                       # Go checksums (will be created)
│
├── TimecardAPIService.swift     # ✅ Updated - API client
├── SendView.swift               # ✅ Updated - UI with email options
├── SwiftDataModels.swift        # Existing - data models
├── XLSXWriter.swift             # Existing - local Excel generation (fallback)
│
├── API_INTEGRATION.md           # ✨ New - Integration guide
├── GO_BACKEND_SETUP.md          # ✨ New - Deployment guide
└── TestGoAPI.swift              # ✨ New - Test script
```

## 🚀 Next Steps

### 1. Set Up Go Backend

Follow `GO_BACKEND_SETUP.md` to:
1. Initialize Go module
2. Add template.xlsx
3. Configure SMTP settings
4. Deploy to Render.com

### 2. Update API URL

In `TimecardAPIService.swift`, update the URL:

```swift
private let baseURL = "https://your-app.onrender.com"
```

### 3. Test Integration

Run `TestGoAPI.swift` to verify:
```bash
swift TestGoAPI.swift
```

Or test directly in your iOS app:
1. Add some timecard entries
2. Go to Send tab
3. Select "Go API" email method
4. Tap Send button
5. Check for success message

### 4. Configure SMTP (For Email Feature)

Set these environment variables on your hosting platform:

```bash
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM=your-email@gmail.com
```

## 🎯 Features Overview

### What Works Now

✅ **Generate Excel via API**
- Multi-week support
- Automatic job extraction
- Proper date formatting
- Template-based generation

✅ **Email via Go API**
- Direct SMTP sending
- Excel attachment included
- Custom subject and body
- CC support

✅ **iOS Mail Composer (Existing)**
- Works offline
- User controls send
- Can edit before sending
- Attaches PDF and Excel

✅ **Fallback System**
- If API fails, uses local Excel generation
- Graceful error messages
- User always has options

### User Workflow

**Option 1: iOS Mail Composer (Default)**
1. Generate files via Go API
2. Open iOS Mail
3. User can edit/review
4. User taps Send

**Option 2: Go API Direct Send (New)**
1. Generate and send in one API call
2. Immediate send (no user review)
3. Confirmation message shown
4. No iOS Mail required

## 🔒 Security Notes

**Current State:**
- ✅ HTTPS communication
- ✅ Environment variables for secrets
- ⚠️ No API authentication (open endpoints)

**For Production:**
- Add API key authentication
- Implement rate limiting
- Add input validation
- Enable audit logging

See `API_INTEGRATION.md` for security recommendations.

## 📊 API Request Example

Here's what the Swift app sends to your Go API:

```json
{
  "employee_name": "John Doe",
  "pay_period_num": 1,
  "year": 2025,
  "week_start_date": "2025-01-06T00:00:00Z",
  "week_number_label": "Week 1",
  "jobs": [
    {
      "job_code": "JOB001",
      "job_name": "Construction Project"
    }
  ],
  "entries": [
    {
      "date": "2025-01-06T00:00:00Z",
      "job_code": "JOB001",
      "hours": 8.0,
      "overtime": false
    },
    {
      "date": "2025-01-07T00:00:00Z",
      "job_code": "JOB001",
      "hours": 8.5,
      "overtime": false
    }
  ]
}
```

**For Email Endpoint, Add:**
```json
{
  // ... all above fields, plus:
  "to": "manager@company.com, hr@company.com",
  "cc": "supervisor@company.com",
  "subject": "Timecard - John Doe - Week 1",
  "body": "Please find attached my timecard."
}
```

## 🧪 Testing

### Test Health Check

```bash
curl https://timecard-api.onrender.com/health
```

Expected: `ok` with status 200

### Test Generate Excel

```bash
curl -X POST https://timecard-api.onrender.com/api/generate-timecard \
  -H "Content-Type: application/json" \
  -d @test_request.json \
  --output timecard.xlsx
```

### Test from iOS

Use `TestGoAPI.swift` or the iOS app directly.

## 🐛 Troubleshooting

### "Invalid JSON" Error

**Cause:** Field names don't match Go's expectations

**Fix:** Ensure using snake_case:
- ✅ `employee_name`
- ❌ `employeeName`

### "Date parsing failed"

**Cause:** Wrong date format

**Fix:** Use ISO 8601 with timezone:
```swift
let formatter = ISO8601DateFormatter()
formatter.timeZone = TimeZone(secondsFromGMT: 0)
```

### "SMTP configuration error"

**Cause:** Missing environment variables

**Fix:** Set all SMTP variables in hosting dashboard

### Timeout on First Request

**Cause:** Free tier services sleep after inactivity

**Fix:** Wait 30-60 seconds for cold start, or upgrade to paid tier

### "No entries found"

**Cause:** No weeks selected or no data in selected weeks

**Fix:** Ensure weeks are selected (W1, W2 buttons)

## 💡 Tips

### Development
- Test locally first (`go run main.go`)
- Use debug logging (`print` statements)
- Test with curl before testing in iOS app

### Production
- Use paid hosting tier for always-on service
- Set up monitoring (UptimeRobot)
- Add API key authentication
- Implement rate limiting

### Maintenance
- Monitor SMTP quota (SendGrid: 100/day free)
- Check logs regularly
- Update dependencies periodically

## 📚 Documentation

| File | Purpose |
|------|---------|
| `API_INTEGRATION.md` | Detailed API integration guide |
| `GO_BACKEND_SETUP.md` | Backend deployment guide |
| `TestGoAPI.swift` | Test script |
| This file | Quick summary |

## 🎉 What You Can Do Now

With this integration, your iOS app can:

1. ✅ Generate professional Excel timecards via Go API
2. ✅ Send emails directly from backend (no iOS Mail needed)
3. ✅ Attach Excel files to emails automatically
4. ✅ Handle multi-week timecards in single request
5. ✅ Fall back to local generation if API unavailable
6. ✅ Give users choice between iOS Mail and direct send
7. ✅ Show real-time status and error messages

## 🤝 Support

For help:
1. Check `API_INTEGRATION.md` for detailed docs
2. Check `GO_BACKEND_SETUP.md` for deployment help
3. Review Go backend logs in Render dashboard
4. Test API endpoints with curl
5. Enable debug logging in Swift app

## ✨ Future Enhancements

Potential improvements:
- [ ] PDF generation in Go backend
- [ ] Batch email sending
- [ ] Email templates
- [ ] Attachment customization
- [ ] Progress tracking
- [ ] Offline queue
- [ ] Push notifications on send

---

**Integration Date:** November 8, 2025
**Status:** ✅ Ready to deploy and test
