#!/usr/bin/env bash
# Build script for Render.com - Installs LibreOffice and builds Go app

set -e  # Exit on error

echo "📦 Installing LibreOffice for PDF conversion..."
apt-get update
apt-get install -y libreoffice-calc --no-install-recommends

echo "✅ LibreOffice installed"

echo "🔨 Building Go application..."
go mod download
go mod tidy
go build -o main .

echo "✅ Build complete!"
