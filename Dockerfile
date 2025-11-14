# Multi-stage build for Go app with LibreOffice
FROM golang:1.23-bookworm AS builder

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

# Final stage - smaller image with LibreOffice
FROM debian:bookworm-slim

# Install LibreOffice (headless version for PDF conversion)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libreoffice-calc \
    libreoffice-writer \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy built binary from builder
COPY --from=builder /app/main .

# Copy template file
COPY --from=builder /app/template.xlsx .

# Expose port (Render uses PORT env variable)
EXPOSE 8080

# Run the application
CMD ["./main"]
