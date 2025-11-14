# syntax=docker/dockerfile:1

FROM golang:1.21 AS build
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o server main.go

FROM gcr.io/distroless/base-debian12
WORKDIR /
COPY --from=build /app/server /server
COPY --from=build /app/template.xlsx /template.xlsx
ENV PORT=8080
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/server"]
