FROM golang:1.21-alpine

RUN apk add --no-cache \
    git \
    ca-certificates \
    libreoffice \
    openjdk11-jre \
    ttf-dejavu \
    fontconfig

WORKDIR /app

ENV GOPROXY=https://proxy.golang.org,direct
ENV GOPRIVATE=""
ENV GOSUMDB=sum.golang.org

COPY go.mod go.sum ./
RUN go mod download

# Copy only what runtime/build needs
COPY main.go render.yaml template.xlsx expense_mileage_template.xlsx ./

# Verify BOTH templates exist
RUN ls -lah /app && \
    ls -lah /app/template.xlsx /app/expense_mileage_template.xlsx && \
    sha256sum /app/template.xlsx /app/expense_mileage_template.xlsx && \
    test -f /app/template.xlsx && \
    test -f /app/expense_mileage_template.xlsx

RUN go build -o server .

EXPOSE 10000
CMD ["./server"]
