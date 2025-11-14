# Timecard API - Email Configuration

## SMTP Setup for Email Functionality

To enable the email functionality in your Go API, you need to configure SMTP settings as environment variables in Render.

### Required Environment Variables

Add these environment variables in your Render dashboard:

1. **SMTP_HOST** - Your SMTP server hostname
   - Example: `smtp.gmail.com`, `smtp.office365.com`, `smtp.sendgrid.net`

2. **SMTP_PORT** - SMTP port number
   - Common ports:
     - `587` (TLS/STARTTLS - recommended)
     - `465` (SSL)
     - `25` (Unencrypted - not recommended)

3. **SMTP_USER** - Your SMTP username
   - Usually your email address

4. **SMTP_PASS** - Your SMTP password
   - For Gmail: Use an "App Password" (not your regular Gmail password)
   - For Office 365/Outlook: Use your email password
   - For SendGrid: Use your API key

5. **SMTP_FROM** (Optional) - Sender email address
   - If not set, will use SMTP_USER as the sender

### Example Configurations

#### Gmail (Recommended for Testing)
```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
SMTP_FROM=your-email@gmail.com
```

**Gmail Setup:**
1. Enable 2-factor authentication on your Google account
2. Go to: https://myaccount.google.com/apppasswords
3. Create an "App Password" for "Mail"
4. Use that 16-character password as SMTP_PASS

#### Office 365 / Outlook
```
SMTP_HOST=smtp.office365.com
SMTP_PORT=587
SMTP_USER=your-email@outlook.com
SMTP_PASS=your-password
SMTP_FROM=your-email@outlook.com
```

#### SendGrid (Recommended for Production)
```
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASS=your-sendgrid-api-key
SMTP_FROM=noreply@yourdomain.com
```

**SendGrid Setup:**
1. Sign up at https://sendgrid.com (free tier available)
2. Create an API key
3. Use "apikey" as the username
4. Use your API key as the password

### Setting Environment Variables in Render

1. Go to your Render dashboard
2. Select your `timecard-api` service
3. Click on "Environment" in the left sidebar
4. Click "Add Environment Variable"
5. Add each of the SMTP variables listed above
6. Click "Save Changes"
7. Render will automatically redeploy with the new configuration

### Testing Email Functionality

Once configured, test the email endpoint:

```bash
curl -X POST https://timecard-api.onrender.com/api/email-timecard \
  -H "Content-Type: application/json" \
  -d '{
    "employee_name": "Test User",
    "pay_period_num": 1,
    "year": 2025,
    "week_start_date": "2025-01-06T00:00:00Z",
    "week_number_label": "Week 1",
    "jobs": [
      {"job_code": "TEST", "job_name": "Test Job"}
    ],
    "entries": [
      {
        "date": "2025-01-06T00:00:00Z",
        "job_code": "TEST",
        "hours": 8.0,
        "overtime": false
      }
    ],
    "weeks": null,
    "to": "recipient@example.com",
    "subject": "Test Timecard",
    "body": "This is a test email."
  }'
```

### Troubleshooting

**Email not sending?**
1. Check Render logs for error messages
2. Verify all environment variables are set correctly
3. For Gmail, ensure you're using an App Password, not your regular password
4. Check that your SMTP provider allows connections from Render's IP addresses

**"SMTP not configured" error?**
- Make sure all required environment variables are set in Render
- Redeploy the service after adding environment variables

**Authentication failed?**
- Double-check your username and password
- For Gmail, regenerate your App Password
- Check if your email provider requires additional security settings

### Security Notes

- Never commit SMTP credentials to your Git repository
- Use environment variables for all sensitive configuration
- For production, consider using a dedicated email service like SendGrid or AWS SES
- Regularly rotate your SMTP passwords/API keys

## iOS App Configuration

In your iOS app, toggle "Go API" in the email method picker to use the API for sending emails. The app will:
1. Generate the Excel file via the API
2. Send the email directly through the API (no Mail.app needed)
3. Show a success message when complete

This is especially useful for:
- Devices without Mail.app configured
- Automated email sending
- Consistent email formatting
- Centralized email logs
