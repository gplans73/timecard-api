# Build stage
FROM golang:1.21-alpine

# Install LibreOffice and dependencies for potential PDF conversion
RUN apk add --no-cache \
    libreoffice \
    openjdk11-jre \
    ttf-dejavu \
    fontconfig

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies and tidy up
RUN go mod download && go mod tidy

# Copy source code
COPY . .

# Verify template exists
RUN ls -lah /app && \
    ls -lah /app/template.xlsx && \
    sha256sum /app/template.xlsx && \
    test -f /app/template.xlsx

# Build the application
RUN go build -o server .

# Expose port
EXPOSE 10000

# Run the server
CMD ["./server"]
