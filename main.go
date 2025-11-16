package main

import (
    "bytes"
    "encoding/base64"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "net/smtp"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "time"

    "github.com/xuri/excelize/v2"
)

/* =========================
   Models (match your Swift)
   ========================= */

type TimecardRequest struct {
    EmployeeName    string     `json:"employee_name"`
    PayPeriodNum    int        `json:"pay_period_num"`
    Year            int        `json:"year"`
    WeekStartDate   string     `json:"week_start_date"`
    WeekNumberLabel string     `json:"week_number_label"`
    Jobs            []Job      `json:"jobs"`
    Entries         []Entry    `json:"entries"`
    Weeks           []WeekData `json:"weeks,omitempty"`
}

type Job struct {
    JobCode string `json:"job_code"`
    JobName string `json:"job_name"`
}

type Entry struct {
    Date         string  `json:"date"`
    JobCode      string  `json:"job_code"`
    Hours        float64 `json:"hours"`
    Overtime     bool    `json:"overtime"`
    IsNightShift bool    `json:"is_night_shift"`
    // ... UnmarshalJSON as before ...
}

func (e *Entry) UnmarshalJSON(data []byte) error {
    type rawEntry struct {
        Date              string  `json:"date"`
        JobCode           string  `json:"job_code"`
        Code              string  `json:"code"`
        Hours             float64 `json:"hours"`
        Overtime          *bool   `json:"overtime"`
        IsOvertimeCamel   *bool   `json:"isOvertime"`
        NightShift        *bool   `json:"night_shift"`
        IsNightShiftSnake *bool   `json:"is_night_shift"`
        IsNightShiftCamel *bool   `json:"isNightShift"`
    }
    var aux rawEntry
    if err := json.Unmarshal(data, &aux); err != nil {
        return err
    }

    e.Date = aux.Date
    if aux.JobCode != "" {
        e.JobCode = aux.JobCode
    } else {
        e.JobCode = aux.Code
    }
    e.Hours = aux.Hours

    if aux.Overtime != nil {
        e.Overtime = *aux.Overtime
    } else if aux.IsOvertimeCamel != nil {
        e.Overtime = *aux.IsOvertimeCamel
    }

    if aux.NightShift != nil {
        e.IsNightShift = *aux.NightShift
    } else if aux.IsNightShiftSnake != nil {
        e.IsNightShift = *aux.IsNightShiftSnake
    } else if aux.IsNightShiftCamel != nil {
        e.IsNightShift = *aux.IsNightShiftCamel
    }

    log.Printf("  Unmarshaled entry: JobCode=%s, Hours=%.2f, OT=%v, Night=%v",
        e.JobCode, e.Hours, e.Overtime, e.IsNightShift)
    return nil
}

type WeekData struct {
    WeekNumber    int     `json:"week_number"`
    WeekStartDate string  `json:"week_start_date"`
    WeekLabel     string  `json:"week_label"`
    Entries       []Entry `json:"entries"`
}

type EmailTimecardRequest struct {
    TimecardRequest
    To      string  `json:"to"`
    CC      *string `json:"cc"`
    Subject string  `json:"subject"`
    Body    string  `json:"body"`
}

type HealthResponse struct {
    Status               string `json:"status"`
    LibreOfficeAvailable bool   `json:"libreoffice_available"`
}

/* ===============
   Server bootstrap
   =============== */

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    // ==== SMTP Diagnostics ====
    smtpHost := os.Getenv("SMTP_HOST")
    smtpPort := os.Getenv("SMTP_PORT")
    smtpUser := os.Getenv("SMTP_USER")
    smtpPass := os.Getenv("SMTP_PASS")
    smtpFrom := os.Getenv("SMTP_FROM")

    log.Println("========== SMTP Environment Variables ==========")
    log.Printf("SMTP_HOST: %q", smtpHost)
    log.Printf("SMTP_PORT: %q", smtpPort)
    log.Printf("SMTP_USER: %q", smtpUser)
    log.Printf("SMTP_PASS length: %d", len(smtpPass))
    log.Printf("SMTP_FROM: %q", smtpFrom)
    log.Println("===============================================")

    http.HandleFunc("/health", healthHandler)
    http.HandleFunc("/api/generate-timecard", corsMiddleware(generateTimecardHandler))
    http.HandleFunc("/api/generate-timecard-pdf", corsMiddleware(generatePDFHandler))
    http.HandleFunc("/api/generate-pdf", corsMiddleware(generatePDFHandler))
    http.HandleFunc("/api/email-timecard", corsMiddleware(emailTimecardHandler))

    log.Printf("🚀 Server starting on :%s", port)
    log.Printf("📋 Available endpoints:")
    log.Printf("  GET  /health - Health check")
    log.Printf("  POST /api/generate-timecard - Generate Excel")
    log.Printf("  POST /api/generate-timecard-pdf - Generate PDF")
    log.Printf("  POST /api/email-timecard - Email timecard")
    
    if err := http.ListenAndServe(":"+port, nil); err != nil {
        log.Fatal(err)
    }
}

// ... Health handler, CORS middleware, Excel/PDF/email handlers as above ...

/* ==========
   Email utils
   ========== */

func sendEmail(to string, cc *string, subject string, body string, attachment []byte, employeeName string) error {
    smtpHost := os.Getenv("SMTP_HOST")
    smtpPort := os.Getenv("SMTP_PORT")
    smtpUser := os.Getenv("SMTP_USER")
    smtpPass := os.Getenv("SMTP_PASS")
    fromEmail := os.Getenv("SMTP_FROM")

    // Debug: log exactly what's being used
    log.Println("Sending email with SMTP configuration:")
    log.Printf("  SMTP_HOST: %q", smtpHost)
    log.Printf("  SMTP_PORT: %q", smtpPort)
    log.Printf("  SMTP_USER: %q", smtpUser)
    log.Printf("  SMTP_PASS length: %d", len(smtpPass))
    log.Printf("  SMTP_FROM: %q", fromEmail)

    // Clear error if any are missing
    missing := []string{}
    if smtpHost == "" { missing = append(missing, "SMTP_HOST") }
    if smtpPort == "" { missing = append(missing, "SMTP_PORT") }
    if smtpUser == "" { missing = append(missing, "SMTP_USER") }
    if smtpPass == "" { missing = append(missing, "SMTP_PASS") }
    if len(missing) > 0 {
        log.Printf("❌ Missing SMTP environment variables: %v", missing)
        return fmt.Errorf("SMTP not configured: missing %v", missing)
    }
    if fromEmail == "" {
        fromEmail = smtpUser
    }

    recipients := strings.Split(to, ",")
    for i := range recipients {
        recipients[i] = strings.TrimSpace(recipients[i])
    }

    var ccRecipients []string
    if cc != nil && *cc != "" {
        ccRecipients = strings.Split(*cc, ",")
        for i := range ccRecipients {
            ccRecipients[i] = strings.TrimSpace(ccRecipients[i])
        }
    }

    all := append([]string{}, recipients...)
    all = append(all, ccRecipients...)

    fileName := fmt.Sprintf("timecard_%s_%s.xlsx",
        strings.ReplaceAll(employeeName, " ", "_"),
        time.Now().Format("2006-01-02"))

    msg := buildEmailMessage(fromEmail, recipients, ccRecipients, subject, body, attachment, fileName)
    auth := smtp.PlainAuth("", smtpUser, smtpPass, smtpHost)
    addr := fmt.Sprintf("%s:%s", smtpHost, smtpPort)
    return smtp.SendMail(addr, auth, fromEmail, all, []byte(msg))
}

// ... buildEmailMessage remains unchanged ...
