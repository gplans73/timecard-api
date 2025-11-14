# Quick SMTP Configuration for Render

Copy and paste these into your Render environment variables:

## For Gmail (Testing/Personal Use)

```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=xxxx xxxx xxxx xxxx
SMTP_FROM=your-email@gmail.com
```

**Get Gmail App Password:**
https://myaccount.google.com/apppasswords

---

## For Office 365 / Outlook

```
SMTP_HOST=smtp.office365.com
SMTP_PORT=587
SMTP_USER=your-email@outlook.com
SMTP_PASS=your-password
SMTP_FROM=your-email@outlook.com
```

---

## For SendGrid (Production Recommended)

```
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASS=SG.xxxxxxxxxxxxxxxxxxxxx
SMTP_FROM=noreply@yourdomain.com
```

**Get SendGrid API Key:**
https://sendgrid.com (Free tier: 100 emails/day)

---

## How to Add in Render

1. Go to: https://render.com/dashboard
2. Click your `timecard-api` service
3. Click "Environment" tab
4. Click "+ Add Environment Variable"
5. Add each variable above
6. Click "Save Changes"
7. Service will auto-redeploy

## Test It

```bash
curl -X POST https://timecard-api.onrender.com/api/email-timecard \
  -H "Content-Type: application/json" \
  -d '{
    "employee_name": "Test",
    "pay_period_num": 1,
    "year": 2025,
    "week_start_date": "2025-01-06T00:00:00Z",
    "week_number_label": "Week 1",
    "jobs": [{"job_code": "TEST", "job_name": "Test"}],
    "entries": [{"date": "2025-01-06T00:00:00Z", "job_code": "TEST", "hours": 8.0, "overtime": false}],
    "weeks": null,
    "to": "your-email@example.com",
    "subject": "Test Email",
    "body": "Testing timecard email system"
  }'
```

Should receive Excel file at `your-email@example.com` ✅
