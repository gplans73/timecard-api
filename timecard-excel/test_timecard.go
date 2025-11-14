package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

type TestRow struct {
	Date    string  `json:"date"`
	Project string  `json:"project"`
	Hours   float64 `json:"hours"`
	Type    string  `json:"type"`
	Notes   string  `json:"notes"`
}

type TestRequest struct {
	EmployeeName string    `json:"employeeName"`
	WeekNumber   int       `json:"weekNumber"`
	Rows         []TestRow `json:"rows"`
	SendEmail    bool      `json:"sendEmail"`
	EmailTo      []string  `json:"emailTo,omitempty"`
}

func main() {
	// Test data for a typical work week
	testData := TestRequest{
		EmployeeName: "Test Employee",
		WeekNumber:   1,
		SendEmail:    false, // Set to true if you want to test email
		Rows: []TestRow{
			{Date: "2024-01-07", Project: "Project Alpha", Hours: 0, Type: "Regular", Notes: "Sunday - no work"},
			{Date: "2024-01-08", Project: "Project Alpha", Hours: 8, Type: "Regular", Notes: "Monday regular hours"},
			{Date: "2024-01-09", Project: "Project Beta", Hours: 8, Type: "Regular", Notes: "Tuesday regular hours"},
			{Date: "2024-01-10", Project: "Project Beta", Hours: 8, Type: "Regular", Notes: "Wednesday regular hours"},
			{Date: "2024-01-11", Project: "Project Alpha", Hours: 8, Type: "Regular", Notes: "Thursday regular hours"},
			{Date: "2024-01-12", Project: "Project Alpha", Hours: 8, Type: "Regular", Notes: "Friday regular hours"},
			{Date: "2024-01-13", Project: "Project Gamma", Hours: 4, Type: "Overtime", Notes: "Saturday overtime"},
		},
	}

	// Convert to JSON
	jsonData, err := json.Marshal(testData)
	if err != nil {
		fmt.Printf("Error marshaling JSON: %v\n", err)
		return
	}

	fmt.Println("Testing timecard service...")
	fmt.Printf("JSON payload: %s\n\n", string(jsonData))

	// Make the request
	resp, err := http.Post("http://localhost:8080/excel", "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		fmt.Printf("Error making request: %v\n", err)
		fmt.Println("Make sure the server is running with: go run main.go")
		return
	}
	defer resp.Body.Close()

	fmt.Printf("Response Status: %s\n", resp.Status)
	fmt.Println("Response Headers:")
	for key, values := range resp.Header {
		for _, value := range values {
			fmt.Printf("  %s: %s\n", key, value)
		}
	}

	if resp.StatusCode == http.StatusOK {
		// Save the Excel file
		filename := fmt.Sprintf("test_timecard_%s.xlsx", time.Now().Format("20060102_150405"))
		file, err := os.Create(filename)
		if err != nil {
			fmt.Printf("Error creating file: %v\n", err)
			return
		}
		defer file.Close()

		_, err = io.Copy(file, resp.Body)
		if err != nil {
			fmt.Printf("Error saving file: %v\n", err)
			return
		}

		fmt.Printf("\n✅ Success! Excel file saved as: %s\n", filename)
		
		// Check email status if email was requested
		if emailStatus := resp.Header.Get("X-Email-Status"); emailStatus != "" {
			fmt.Printf("📧 Email Status: %s\n", emailStatus)
			if emailError := resp.Header.Get("X-Email-Error"); emailError != "" {
				fmt.Printf("📧 Email Error: %s\n", emailError)
			}
		}
	} else {
		// Read error response
		body, _ := io.ReadAll(resp.Body)
		fmt.Printf("❌ Error: %s\n", string(body))
	}
}