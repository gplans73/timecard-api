FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go files
COPY go.mod ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/

# Copy the binary and template
COPY --from=builder /app/main .
COPY --from=builder /app/template.xlsx .

EXPOSE 8080
CMD ["./main"]