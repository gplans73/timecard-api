# 🚀 Docker Deployment Checklist

## ✅ Files Ready for Deployment

You now have these Docker deployment files:

- ✅ `Dockerfile` - Multi-stage build with LibreOffice
- ✅ `.dockerignore` - Optimizes Docker builds  
- ✅ `render.yaml` - Render.com configuration
- ✅ `render-build.sh` - Updated (no longer needed for Docker but kept for reference)

## 📝 Deployment Steps

### Step 1: Make Sure template.xlsx is in Your Repo

```bash
# Verify template exists
ls -la template.xlsx

# If missing, add it:
git add template.xlsx
```

### Step 2: Commit and Push Docker Files

```bash
# Make build script executable (good practice)
chmod +x render-build.sh

# Add all new Docker files
git add Dockerfile .dockerignore render.yaml render-build.sh

# Commit with descriptive message
git commit -m "Add Docker deployment with LibreOffice support"

# Push to GitHub
git push origin main
```

### Step 3: Configure Render.com

#### Option A: New Service (Recommended)

1. Go to [Render Dashboard](https://dashboard.render.com/)
2. Click **"New +"** → **"Web Service"**
3. Connect to your GitHub repository
4. Render will **automatically detect** the `Dockerfile`
5. Configuration should auto-populate:
   - **Name:** `timecard-api`
   - **Runtime:** Docker
   - **Plan:** Free (or upgrade to Starter)
6. Click **"Create Web Service"**

#### Option B: Update Existing Service

1. Go to your existing `timecard-api` service
2. Go to **Settings**
3. Under **Build & Deploy**, change:
   - **Runtime:** Docker
   - **Dockerfile Path:** `./Dockerfile`
   - **Docker Context:** `.`
4. Click **"Save Changes"**
5. Go to **Manual Deploy** → **"Deploy latest commit"**

### Step 4: Add Environment Variables (Optional)

If you want email functionality:

1. In Render Dashboard → Your Service → **Environment**
2. Add these variables:
   ```
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=587
   SMTP_USER=your-email@gmail.com
   SMTP_PASS=your-app-password
   SMTP_FROM=your-email@gmail.com (optional)
   ```
3. Click **"Save Changes"**

### Step 5: Deploy & Monitor

1. Render will start building your Docker image
2. Watch the build logs for:
   ```
   ✅ Building Go application...
   ✅ Installing LibreOffice...
   ✅ Image built successfully
   ```
3. Build time: **5-10 minutes** (first time)
4. Once deployed, test the health endpoint:
   ```bash
   curl https://your-service.onrender.com/health
   ```

## 🧪 Testing Your Deployment

### Test Health Check

```bash
curl https://your-timecard-api.onrender.com/health
# Expected: OK
```

### Test Excel Generation

```bash
curl -X POST https://your-timecard-api.onrender.com/api/generate-timecard \
  -H "Content-Type: application/json" \
  -d '{
    "employee_name": "Test User",
    "pay_period_num": 1,
    "year": 2025,
    "week_start_date": "2025-11-10T00:00:00Z",
    "week_number_label": "Week 1",
    "jobs": [{"job_code": "12345", "job_name": "201"}],
    "weeks": [{
      "week_number": 1,
      "week_start_date": "2025-11-10T00:00:00Z",
      "week_label": "Week 1",
      "entries": [{
        "date": "2025-11-10T00:00:00Z",
        "job_code": "12345",
        "hours": 8.0,
        "overtime": false,
        "is_night_shift": false
      }]
    }]
  }' \
  --output test-timecard.xlsx

# Verify the file
open test-timecard.xlsx
```

### Test PDF Generation

```bash
curl -X POST https://your-timecard-api.onrender.com/api/generate-pdf \
  -H "Content-Type: application/json" \
  -d '{
    "employee_name": "Test User",
    "pay_period_num": 1,
    "year": 2025,
    "week_start_date": "2025-11-10T00:00:00Z",
    "week_number_label": "Week 1",
    "jobs": [{"job_code": "12345", "job_name": "201"}],
    "weeks": [{
      "week_number": 1,
      "week_start_date": "2025-11-10T00:00:00Z",
      "week_label": "Week 1",
      "entries": [{
        "date": "2025-11-10T00:00:00Z",
        "job_code": "12345",
        "hours": 8.0,
        "overtime": false,
        "is_night_shift": false
      }]
    }]
  }' \
  --output test-timecard.pdf

# Verify the PDF (should look exactly like Excel)
open test-timecard.pdf
```

## 📊 What to Expect

### Build Process
```
==> Downloading cache...
==> Building Docker image...
    → Step 1: Building Go application...
    → Step 2: Installing LibreOffice...
    → Step 3: Creating runtime image...
==> Image built: 215MB
==> Deploying...
==> Your service is live! 🎉
```

### Build Times
- **First deploy:** 8-10 minutes
- **Subsequent deploys:** 3-5 minutes (Docker layer caching)

### Runtime Performance
- **Startup time:** 2-3 seconds
- **Excel generation:** <1 second
- **PDF generation:** 2-3 seconds (LibreOffice conversion)
- **Memory usage:** ~150MB

### Docker Image Size
- **Final image:** ~215MB
  - Go binary: ~15MB
  - LibreOffice: ~180MB
  - Base OS: ~20MB

## 🔍 Troubleshooting

### ❌ "Cannot find template.xlsx"

**Problem:** Template file not in Docker image

**Fix:**
```bash
# Make sure template.xlsx exists
ls -la template.xlsx

# Add to git
git add template.xlsx
git commit -m "Add template file"
git push
```

### ❌ "soffice: command not found"

**Problem:** LibreOffice not installed in Docker image

**Fix:** Check Dockerfile has these lines:
```dockerfile
RUN apt-get update && \
    apt-get install -y \
    libreoffice-calc \
    libreoffice-core \
```

### ❌ Build fails with "go.mod not found"

**Problem:** Missing Go modules

**Fix:**
```bash
# Ensure go.mod and go.sum exist
ls -la go.mod go.sum

# If missing, create them:
go mod init github.com/yourusername/timecard-api
go mod tidy
git add go.mod go.sum
git commit -m "Add Go modules"
git push
```

### ❌ "Port already in use"

**Problem:** Multiple instances or wrong port

**Fix:** Render sets PORT automatically. Make sure your code uses `os.Getenv("PORT")`:
```go
port := os.Getenv("PORT")
if port == "" {
    port = "8080"
}
```

### 🐛 Check Logs

In Render Dashboard:
1. Go to your service
2. Click **"Logs"** tab
3. Look for errors
4. Check for:
   ```
   ✅ LibreOffice found: LibreOffice 7.x.x.x
   🔄 Converting Excel to PDF using LibreOffice...
   ✅ Generated LibreOffice PDF: XXXXX bytes
   ```

## 🎯 Success Indicators

You'll know it's working when you see:

1. ✅ **Build logs show:**
   ```
   Successfully built Docker image
   Starting deployment...
   Service is live
   ```

2. ✅ **Health check returns:**
   ```
   OK
   ```

3. ✅ **PDF generation produces:**
   - Pixel-perfect Excel replica
   - Logo preserved
   - All formatting intact
   - Professional appearance

4. ✅ **Your Swift app can:**
   - Generate Excel files
   - Generate PDF files
   - Email timecards
   - Download files

## 📱 Update Your Swift App

Once deployed, update your API base URL:

```swift
// In your Swift app's NetworkManager or config
let baseURL = "https://your-timecard-api.onrender.com"

// Example endpoints:
// - https://your-timecard-api.onrender.com/health
// - https://your-timecard-api.onrender.com/api/generate-timecard
// - https://your-timecard-api.onrender.com/api/generate-pdf
// - https://your-timecard-api.onrender.com/api/email-timecard
```

## 🚀 Next Steps After Deployment

1. ✅ Test all three endpoints (Excel, PDF, Email)
2. ✅ Verify PDFs look perfect
3. ✅ Update Swift app with new URL
4. ✅ Test from iPhone/iPad
5. ✅ Celebrate! 🎉

## 💰 Cost

**Render Free Tier:**
- ✅ Docker support included
- ✅ 750 hours/month (plenty for development)
- ✅ Sleeps after 15 min inactivity
- ✅ Wakes up on request (3-5 second delay)

**If you need 24/7 uptime:** Upgrade to Starter ($7/month)

## 🔄 Rollback Plan

If something goes wrong:

```bash
# Revert to previous commit
git revert HEAD
git push origin main

# Or restore old version manually in Render Dashboard
# Settings → Manual Deploy → Select previous deploy
```

---

**Status:** Ready to deploy! 🐳  
**Next:** Follow Step 1 above, then commit and push!

**Questions?** Check the logs or test locally first:
```bash
# Test Docker build locally
docker build -t timecard-api .

# Run locally
docker run -p 8080:8080 timecard-api

# Test endpoints
curl http://localhost:8080/health
```
