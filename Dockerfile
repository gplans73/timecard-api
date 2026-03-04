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

# Keep dependency bootstrap resilient even if go.sum is missing/stale.
COPY go.mod ./
RUN go mod download

COPY . .
RUN go mod tidy && go mod download

# Fail build early if either template file is missing from the image.
RUN ls -lah /app && \
    ls -lah /app/template.xlsx && \
    ls -lah /app/expense_mileage_template.xlsx && \
    sha256sum /app/template.xlsx /app/expense_mileage_template.xlsx && \
    test -f /app/template.xlsx && \
    test -f /app/expense_mileage_template.xlsx

RUN go build -o server .

EXPOSE 10000

CMD ["./server"]
