# Build stage
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git gcc musl-dev

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN go build -o main .

# Runtime stage
FROM alpine:latest

# Install LibreOffice and dependencies for PDF conversion
RUN apk add --no-cache \
    libreoffice \
    ttf-dejavu \
    ttf-liberation \
    ca-certificates \
    && rm -rf /var/cache/apk/*

WORKDIR /root/

# Copy the binary from builder
COPY --from=builder /app/main .

# Copy the Excel template (if you have one)
# Use wildcard to avoid failure if template doesn't exist
COPY template.xlsx* ./

# Expose port
EXPOSE 8080

# Run the application
CMD ["./main"]
