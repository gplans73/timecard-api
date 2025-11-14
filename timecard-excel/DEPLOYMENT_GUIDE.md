# Timecard Excel API - Render Deployment

## Current Issue & Fix

Your deployment failed because:
1. ❌ main.go had shell script syntax (`cat > main.go << 'EOF'`)  
2. ❌ Missing go.mod file
3. ❌ Missing template.xlsx file

## Step-by-Step Fix:

### 1. Create Your Excel Template
1. Open Excel and create a timecard template
2. Create two sheets: "Week 1" and "Week 2" 
3. Save as `template.xlsx` in your repository root
4. Make sure cell M2 is where employee name goes
5. Make sure B5-B11 are for main dates (Sun-Sat)
6. Make sure B16-B22 are for OT dates (Sun-Sat)

### 2. Push Fixed Files to GitHub
```bash
git add .
git commit -m "Fix deployment files - clean main.go, add go.mod"
git push origin main
```

### 3. Configure Render Environment Variables
In your Render dashboard, set these environment variables:

**Required for Email:**
- `SMTP_HOST` = `smtp.gmail.com`
- `SMTP_PORT` = `587`  
- `SMTP_USER` = your Gmail address
- `SMTP_PASSWORD` = your Gmail App Password (not regular password!)
- `FROM_EMAIL` = your Gmail address  
- `FROM_NAME` = `Timecard System`

### 4. Redeploy in Render
1. Go to your service in Render dashboard
2. Click "Manual Deploy" → "Deploy latest commit"
3. Watch the build logs

## Gmail App Password Setup:
1. Enable 2-factor authentication on Gmail
2. Go to Google Account settings  
3. Generate an "App Password" for "Mail"
4. Use that 16-character password as `SMTP_PASSWORD`

## Testing Your API:
Once deployed, test with:
```bash
curl -X POST https://your-service.onrender.com/excel \
  -H "Content-Type: application/json" \
  -d '{
    "employeeName": "Test User",
    "weekNumber": 1, 
    "rows": [
      {"date": "2024-11-04", "project": "Test", "hours": 8, "type": "Regular", "notes": "Testing"}
    ],
    "sendEmail": false
  }' --output test.xlsx
```