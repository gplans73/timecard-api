# Build stage
FROM golang:1.21-alpine

# Install git and other dependencies
RUN apk add --no-cache \
    git \
    ca-certificates \
    libreoffice \
    openjdk11-jre \
    ttf-dejavu \
    fontconfig

# Set working directory
WORKDIR /app

# Configure Go to use proxy and avoid git cloning
ENV GOPROXY=https://proxy.golang.org,direct
ENV GOPRIVATE=""
ENV GOSUMDB=sum.golang.org

# Copy go.mod
COPY go.mod ./

# Clear any cached modules and download fresh
RUN rm -rf /go/pkg/mod/cache/vcs/* && \
    go mod download -x && \
    go mod tidy

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
