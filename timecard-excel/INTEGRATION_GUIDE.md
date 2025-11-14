# Swift Timecard + Go Excel Server Integration

This guide helps you integrate your Swift timecard app with your Go server to generate Excel files using your exact company template.

## Current Setup

✅ **Swift App**: Your timecard data entry and management app  
✅ **Go Server**: Excel generation API deployed on Render  
❌ **Missing**: Template file and proper integration

## Step 1: Fix Your Go Server

### 1.1 Add Your Template File

1. **Get your company's Excel template** (the exact format your employer expects)
2. **Save it as `template.xlsx`** in your Go project root directory
3. **Ensure the template has**:
   - Employee name in cell **M2**
   - Date cells in column **B** (rows 5-11 for regular time)
   - Date cells in column **B** (rows 16-22 for overtime)
   - Hour entry columns (let us know which columns these are)
   - Project/job name columns (let us know which columns these are)

### 1.2 Deploy to Render

```bash
# In your Go project directory:
git add template.xlsx
git commit -m "Add Excel template file"
git push origin main
```

Then redeploy in your Render dashboard.

### 1.3 Test Your Server

```bash
curl https://your-server.onrender.com/health
```

Should return a 200 OK status.

## Step 2: Configure Your Swift App

### 2.1 Update Server URL

1. Open your Swift timecard app
2. Go to **Settings** → **Excel Export**
3. Enter your Render server URL: `https://your-server-name.onrender.com`
4. Tap **"Test Connection"** - should show "Connected ✅"

### 2.2 Configure Email Settings

1. Go to **Settings** → **Email**
2. Add your manager/HR email addresses
3. Customize the subject and body templates

### 2.3 Set Up Gmail SMTP (in Render)

In your Render dashboard, set these environment variables:

```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-16-char-app-password
FROM_EMAIL=your-email@gmail.com
FROM_NAME=Timecard System
```

**Important**: Use a Gmail App Password, not your regular password!

## Step 3: Export Your Timecard

### From the Swift App:

1. **Enter your timecard data** for the week
2. **Tap "Export Excel"** button
3. **Choose**:
   - **"Download Excel File"** → Saves to your device
   - **"Email Excel File"** → Emails using your template

### What Happens:

1. ✅ Swift app sends your data to Go server
2. ✅ Go server fills your `template.xlsx` with your data
3. ✅ Returns properly formatted Excel file
4. ✅ Optionally emails it to your manager/HR

## Step 4: Template Customization

We need to know your template structure to map the data correctly:

### Current Mappings (based on your template):
- **M2**: Employee name ✅  
- **B4**: "Sun Dat" header ✅  
- **B5-B11**: Week dates (Sun-Sat) ✅  
- **B16-B22**: OT section dates ✅  

### Need to Know:
1. **Which column(s)** should get the **HOURS** data?
2. **Which column(s)** should get the **PROJECT** names?  
3. **Which rows/columns** are for **Regular vs OT** hours?
4. **Any other specific formatting** requirements?

## Testing

Once everything is set up:

```bash
# Test the API directly:
curl -X POST https://your-server.onrender.com/excel \
  -H "Content-Type: application/json" \
  -d '{
    "employeeName": "Your Name",
    "weekNumber": 1,
    "rows": [
      {
        "date": "2024-11-04",
        "project": "Test Project", 
        "hours": 8.0,
        "type": "Regular",
        "notes": "Testing integration"
      }
    ],
    "totalOC": 40.0,
    "totalOT": 0.0,
    "sendEmail": false
  }' \
  --output test-timecard.xlsx
```

## Troubleshooting

### "pattern template.xlsx: no matching files found"
- ❌ Your `template.xlsx` file is missing from the Go project
- ✅ Add the file and redeploy

### "Server is not responding"  
- ❌ Wrong server URL or server is down
- ✅ Check Render deployment logs

### "Export failed: Network error"
- ❌ Network connectivity issue
- ✅ Check your internet connection and server URL

### Email not sending
- ❌ SMTP settings incorrect
- ✅ Use Gmail App Password, not regular password

## What You Get

✅ **Perfect template matching** - Uses your exact company Excel format  
✅ **Automated email delivery** - Sends to your manager/HR automatically  
✅ **Native Swift integration** - Works seamlessly with your timecard app  
✅ **Cloud-hosted reliability** - Render handles the server infrastructure  

Your timecards will look exactly like your company expects them! 🎯