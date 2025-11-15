# Alternative: Remove PDF Feature (Simplest Fix)

If you don't absolutely need PDF generation, you can remove the LibreOffice dependency entirely and simplify your deployment.

## Option: Disable PDF Endpoint

### 1. Comment out PDF generation in main.go

Find this line:
```go
http.HandleFunc("/api/generate-pdf", corsMiddleware(generatePDFHandler))
```

Comment it out:
```go
// http.HandleFunc("/api/generate-pdf", corsMiddleware(generatePDFHandler))
```

### 2. Update render-build.sh

Replace with simple build:
```bash
#!/usr/bin/env bash
set -e
echo "🔨 Building Go application..."
go mod download
go mod tidy
go build -o main .
echo "✅ Build complete!"
```

### 3. Deploy

```bash
git add main.go render-build.sh
git commit -m "Temporarily disable PDF feature"
git push
```

### 4. In Render.com:

**Build Command:**
```bash
./render-build.sh
```

**Start Command:**
```bash
./main
```

## What Still Works

✅ Excel generation (`.xlsx`)  
✅ Email with Excel attachment  
✅ Health check  
✅ All Swift app features (except PDF preview)

## What Doesn't Work

❌ PDF generation endpoint  
❌ PDF preview in Swift app (if you added this)

## Re-enable Later

When you switch to Docker or find another solution, just:

1. Uncomment the PDF endpoint
2. Deploy with Docker
3. Everything works again

## Benefits

✅ Deploys in <1 minute  
✅ Works on Render free tier  
✅ No dependencies  
✅ Small deployment (~50MB)  
✅ Fast startup

## When to Use This

- ✅ You mainly need Excel files
- ✅ PDF is "nice to have" but not critical
- ✅ Want to deploy quickly
- ✅ Can add PDF later

## When NOT to Use This

- ❌ PDFs are a core feature
- ❌ Users depend on PDF format
- ❌ You've already built PDF features in Swift app

---

**Recommendation:** Use Docker deployment instead (see DEPLOYMENT_FIX.md) unless PDFs are truly optional.
