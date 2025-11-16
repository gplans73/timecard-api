FROM golang:1.21-bullseye

# Install LibreOffice Calc (for spreadsheet conversion) and core dependencies
RUN apt-get update && apt-get install -y \
    libreoffice-calc \
    libreoffice-core \
    fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Go module files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source code and template
COPY *.go ./
COPY template.xlsx ./

# Build the Go app
RUN go build -o main .

EXPOSE 8080

CMD ["./main"]
