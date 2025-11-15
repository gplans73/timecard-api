#!/usr/bin/env bash
# Build script for Render.com - Builds Go app
# LibreOffice should be installed via render.yaml apt-packages

set -e  # Exit on error

echo "🔨 Building Go application..."
go mod download
go mod tidy
go build -o main .

echo "✅ Build complete!"

# Verify LibreOffice is available
if command -v soffice &> /dev/null; then
    echo "✅ LibreOffice found: $(soffice --version)"
else
    echo "⚠️  LibreOffice not found - PDF generation will fail!"
    exit 1
fi

