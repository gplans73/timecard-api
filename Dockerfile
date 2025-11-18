# Use an image that supports LibreOffice
FROM golang:1.21-alpine

# Install LibreOffice and required dependencies
RUN apk add --no-cache \
    libreoffice \
    openjdk11-jre \
    ttf-dejavu \
    fontconfig

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN go build -o server .

# Expose port
EXPOSE 8080

# Run the application
CMD ["./server"]
