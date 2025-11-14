# Quick Start - Deploy Now! 🚀

## What You Have

✅ LibreOffice PDF integration complete  
✅ All code updated in main.go  
✅ Build script created (render-build.sh)  
✅ Ready to deploy!

## 5-Minute Deploy

### 1️⃣ Make Script Executable
```bash
chmod +x render-build.sh
```

### 2️⃣ Commit & Push
```bash
git add .
git commit -m "Add LibreOffice for pixel-perfect PDF generation"
git push origin main
```

### 3️⃣ Update Render.com

Go to: https://dashboard.render.com

1. Click your `timecard-api` service
2. Click **Settings**
3. Find **Build Command**
4. Change to: `./render-build.sh`
5. Click **Save Changes**

### 4️⃣ Deploy

1. Go to **Events** tab (or **Manual Deploy** button)
2. Click **Deploy latest commit**
3. Wait ~4 minutes ⏱️

### 5️⃣ Test

Open your Swift app and generate a PDF!

## ✅ Success Indicators

### In Render.com Logs:
```
📦 Installing LibreOffice for PDF conversion...
✅ LibreOffice installed
🔨 Building Go application...
✅ Build complete!
==> Your service is live 🎉
```

### When Generating PDF:
```
🔄 Converting Excel to PDF using LibreOffice...
✅ Generated LibreOffice PDF: 45234 bytes (perfect Excel conversion)
```

### In Your PDF:
- ✅ Company logo appears
- ✅ All formatting matches Excel exactly
- ✅ Borders and merged cells look perfect
- ✅ Professional appearance

## 🎉 Result

Your PDFs will now look **exactly** like your Excel files - logo, formatting, and all!

---

**Having issues?** Check `LIBREOFFICE_DEPLOYMENT.md` for detailed troubleshooting.
