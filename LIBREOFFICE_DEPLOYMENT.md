# LibreOffice PDF Generation - Deployment Guide

## What Changed

✅ **Removed:** gofpdf library (basic PDF generation)  
✅ **Added:** LibreOffice integration (pixel-perfect Excel → PDF conversion)

Your PDFs will now look **exactly** like your Excel files:
- Company logo preserved
- All formatting, borders, and colors
- Merged cells
- Proper layout
- Summary totals
- "Office Use Only" section

## Deployment Steps

### 1. Make the build script executable (local)

```bash
chmod +x render-build.sh
```

### 2. Commit and push all changes

```bash
git add main.go render-build.sh
git commit -m "Switch to LibreOffice for pixel-perfect PDF generation"
git push origin main
```

### 3. Update Render.com Build Settings

Go to your Render.com dashboard → `timecard-api` service → Settings:

**Build Command:** Change to:
```bash
./render-build.sh
```

Or if that doesn't work, use:
```bash
bash render-build.sh
```

**Start Command:** Keep as:
```bash
./main
```

### 4. Deploy

Click **Manual Deploy** → **Deploy latest commit**

The build will:
1. Install LibreOffice (~150MB, takes ~2-3 minutes)
2. Download Go modules
3. Build your app

## What to Expect

### Build Time
- First deploy: ~3-5 minutes (installing LibreOffice)
- Subsequent deploys: ~2-3 minutes (LibreOffice cached)

### Runtime
- PDF generation: ~2-3 seconds per timecard
- Still fast enough for real-time use

### Logs
You'll see:
```
📦 Installing LibreOffice for PDF conversion...
✅ LibreOffice installed
🔨 Building Go application...
✅ Build complete!
```

Then when generating PDFs:
```
🔄 Converting Excel to PDF using LibreOffice...
✅ Generated LibreOffice PDF: 45234 bytes (perfect Excel conversion)
```

## Testing

After deployment:

1. Generate a PDF from your Swift app
2. Open the PDF - it should look **exactly** like your Excel file
3. Check for:
   - ✅ Company logo
   - ✅ Proper borders and formatting
   - ✅ Merged cells intact
   - ✅ Column widths correct
   - ✅ Summary section on the right
   - ✅ All styling preserved

## Troubleshooting

### Build fails with "soffice: command not found"

The build script didn't run. Make sure:
- Build Command is set to `./render-build.sh`
- The script is executable: `chmod +x render-build.sh`

### "Permission denied" error

Run locally:
```bash
chmod +x render-build.sh
git add render-build.sh
git commit -m "Make build script executable"
git push
```

### LibreOffice install fails

Check Render.com logs. If using a restricted plan, you may need:
```bash
# In render-build.sh, add before apt-get install:
export DEBIAN_FRONTEND=noninteractive
```

### PDF still looks wrong

Check logs for LibreOffice errors:
```
❌ LibreOffice conversion failed: [error message]
```

Most common fixes:
- Ensure `template.xlsx` is in the deployed files
- Check Excel file isn't corrupted
- Verify LibreOffice installed correctly

## Benefits

### Before (gofpdf)
❌ Basic table layout
❌ No logo
❌ No formatting
❌ No merged cells
❌ Tiny text

### After (LibreOffice)
✅ Perfect Excel replica
✅ Logo preserved
✅ All formatting
✅ Merged cells
✅ Professional appearance

## Performance Impact

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Deployment size | ~50MB | ~200MB | +150MB |
| First build time | ~1 min | ~4 min | +3 min |
| PDF generation | <1 sec | 2-3 sec | +2 sec |
| PDF quality | ⭐ | ⭐⭐⭐⭐⭐ | Much better |

## Cost Impact

Render.com free tier:
- ✅ Should still work (200MB well within limits)
- ✅ Build time acceptable
- ✅ Runtime fast enough

If you upgrade to paid plan, everything will be faster.

## Rollback Plan

If you need to revert:

```bash
git revert HEAD
git push
```

Then update Render Build Command back to:
```bash
go mod download && go mod tidy && go build -o main .
```

---

**Status:** Ready to deploy! 🚀
**Next:** Commit, push, update Render.com build settings, and deploy.
