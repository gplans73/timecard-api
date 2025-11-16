FROM golang:1.21-bullseye

# Install LibreOffice and dependencies
RUN apt-get update && apt-get install -y \
    libreoffice \
    libreoffice-calc \
    libreoffice-writer \
    libreoffice-core \
    fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Go module files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code and template
COPY *.go ./
COPY template.xlsx ./

# Build the Go app
RUN go build -o main .

EXPOSE 8080

CMD ["./main"]
