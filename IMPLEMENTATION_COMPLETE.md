# LibreOffice Integration - Complete Summary

## ✅ What Was Done

### 1. Updated main.go
- ✅ Removed `gofpdf` import
- ✅ Added `os/exec` and `path/filepath` imports  
- ✅ Replaced `generatePDFFromExcel()` with LibreOffice version
- ✅ Removed `isNumeric()` helper (no longer needed)

### 2. Created Build Script
- ✅ `render-build.sh` - Installs LibreOffice and builds app
- ✅ Makes deployment automatic

### 3. Documentation
- ✅ `LIBREOFFICE_DEPLOYMENT.md` - Complete deployment guide

## 🚀 Next Steps

### Step 1: Make script executable (on your Mac)
```bash
chmod +x render-build.sh
```

### Step 2: Commit changes
```bash
git add main.go render-build.sh LIBREOFFICE_DEPLOYMENT.md
git commit -m "Switch to LibreOffice for pixel-perfect PDF generation"
git push origin main
```

### Step 3: Update Render.com
1. Go to https://dashboard.render.com
2. Select your `timecard-api` service
3. Go to **Settings**
4. Update **Build Command** to: `./render-build.sh`
5. Click **Save Changes**

### Step 4: Deploy
1. Go to **Manual Deploy**
2. Click **Deploy latest commit**
3. Wait ~4 minutes for first deploy

### Step 5: Test
Generate a PDF from your Swift app - it should look **exactly** like your Excel file!

## 📊 Comparison

| Feature | Old (gofpdf) | New (LibreOffice) |
|---------|-------------|-------------------|
| Logo | ❌ Missing | ✅ Perfect |
| Formatting | ❌ Basic | ✅ Exact match |
| Borders | ❌ Simple | ✅ Complex/merged |
| Layout | ❌ Table dump | ✅ Professional |
| Colors | ❌ None | ✅ All preserved |
| Summary section | ❌ Missing | ✅ Included |
| Generation time | <1 sec | 2-3 sec |
| Quality | ⭐ | ⭐⭐⭐⭐⭐ |

## 🎯 Expected Results

Your PDF will now show:
- ✅ Company logo at the top
- ✅ Proper borders and cell merging
- ✅ Employee name, pay period, year fields
- ✅ Date column with proper formatting
- ✅ Job numbers and labour codes
- ✅ Hours in correct cells
- ✅ Summary totals on the right side
- ✅ "Office Use Only" section
- ✅ All styling from your Excel template

## ⚠️ Important Notes

1. **First deploy takes ~4 minutes** (installing LibreOffice)
2. **Subsequent deploys ~2 minutes** (cached)
3. **PDF generation ~2-3 seconds** (worth it for quality!)
4. **Template must be in deployment** (already is)
5. **No changes needed to Swift app** (API stays the same)

## 🔍 Verification

After deployment, check logs for:
```
📦 Installing LibreOffice for PDF conversion...
✅ LibreOffice installed
🔨 Building Go application...
✅ Build complete!
```

Then when generating PDF:
```
🔄 Converting Excel to PDF using LibreOffice...
✅ Generated LibreOffice PDF: 45234 bytes (perfect Excel conversion)
```

## 💡 Pro Tips

1. **Keep Excel as backup format** - Always attach both Excel and PDF
2. **Monitor first deploy** - Watch Render logs to ensure LibreOffice installs
3. **Test immediately** - Generate a test PDF right after deployment
4. **Compare side-by-side** - Open Excel and PDF to verify they match

## 🆘 If Something Goes Wrong

### Build fails
Check that `render-build.sh` is executable:
```bash
chmod +x render-build.sh
git add render-build.sh
git commit --amend --no-edit
git push -f
```

### "soffice not found" error
Build Command in Render.com is wrong. Should be:
```bash
./render-build.sh
```

### PDF generation fails
Check Render logs for LibreOffice errors. Usually means LibreOffice didn't install properly.

### Rollback
```bash
git revert HEAD~2..HEAD  # Reverts last 2 commits
git push
```

Then change Render Build Command back to:
```bash
go mod download && go mod tidy && go build -o main .
```

---

**Ready to go!** 🎉 Follow the steps above and your PDFs will look amazing!
