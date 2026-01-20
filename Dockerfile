# Build stage
FROM golang:1.21-alpine

# Install git and other dependencies
RUN apk add --no-cache \
    git \
    libreoffice \
    openjdk11-jre \
    ttf-dejavu \
    fontconfig

# Set working directory
WORKDIR /app

# Use Go module proxy to avoid git authentication issues
ENV GOPROXY=https://proxy.golang.org,direct

# Copy only go.mod (not go.sum - let it regenerate)
COPY go.mod ./

# Generate fresh go.sum and download all dependencies
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
