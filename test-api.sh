#!/bin/bash

# Test script for Go API endpoints
# Usage: ./test-api.sh [base_url]
# Example: ./test-api.sh https://timecard-api.onrender.com

BASE_URL="${1:-https://timecard-api.onrender.com}"

echo "🧪 Testing Go Timecard API"
echo "Base URL: $BASE_URL"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Health Check
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1️⃣  Testing Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

response=$(curl -s -w "\n%{http_code}" "$BASE_URL/health")
body=$(echo "$response" | head -n -1)
status=$(echo "$response" | tail -n 1)

if [ "$status" -eq 200 ]; then
    echo -e "${GREEN}✅ PASS${NC} - Status: $status"
    echo "Response: $body"
else
    echo -e "${RED}❌ FAIL${NC} - Status: $status"
    echo "Response: $body"
fi

echo ""

# Test 2: Generate Timecard
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2️⃣  Testing Generate Timecard"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create test request JSON
cat > /tmp/test_timecard_request.json << 'EOF'
{
  "employee_name": "Test Employee",
  "pay_period_num": 1,
  "year": 2025,
  "week_start_date": "2025-01-06T00:00:00Z",
  "week_number_label": "Week 1",
  "jobs": [
    {
      "job_code": "JOB001",
      "job_name": "Construction Project A"
    },
    {
      "job_code": "JOB002",
      "job_name": "Maintenance Work"
    }
  ],
  "entries": [
    {
      "date": "2025-01-06T00:00:00Z",
      "job_code": "JOB001",
      "hours": 8.0,
      "overtime": false
    },
    {
      "date": "2025-01-07T00:00:00Z",
      "job_code": "JOB001",
      "hours": 8.5,
      "overtime": false
    },
    {
      "date": "2025-01-07T00:00:00Z",
      "job_code": "JOB002",
      "hours": 2.0,
      "overtime": true
    },
    {
      "date": "2025-01-08T00:00:00Z",
      "job_code": "JOB001",
      "hours": 9.0,
      "overtime": false
    },
    {
      "date": "2025-01-09T00:00:00Z",
      "job_code": "JOB002",
      "hours": 8.0,
      "overtime": false
    },
    {
      "date": "2025-01-10T00:00:00Z",
      "job_code": "JOB001",
      "hours": 7.5,
      "overtime": false
    }
  ]
}
EOF

echo "Request JSON:"
cat /tmp/test_timecard_request.json | jq '.' 2>/dev/null || cat /tmp/test_timecard_request.json
echo ""

# Make request with timeout for cold start
echo -e "${YELLOW}⏳ Sending request (may take 30-60s on first call)...${NC}"

status=$(curl -s -o /tmp/test_timecard.xlsx -w "%{http_code}" \
  -X POST "$BASE_URL/api/generate-timecard" \
  -H "Content-Type: application/json" \
  -d @/tmp/test_timecard_request.json \
  --max-time 120)

if [ "$status" -eq 200 ]; then
    size=$(wc -c < /tmp/test_timecard.xlsx)
    echo -e "${GREEN}✅ PASS${NC} - Status: $status"
    echo "Excel file generated: $size bytes"
    echo "Saved to: /tmp/test_timecard.xlsx"
    
    # Try to open file if on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo ""
        echo "Opening file..."
        open /tmp/test_timecard.xlsx 2>/dev/null || echo "Could not open file automatically"
    fi
else
    echo -e "${RED}❌ FAIL${NC} - Status: $status"
    echo "Response:"
    cat /tmp/test_timecard.xlsx
fi

echo ""

# Test 3: Email Timecard (Optional - requires SMTP config)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3️⃣  Testing Email Timecard"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

read -p "Do you want to test email sending? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter recipient email: " recipient_email
    
    if [ -z "$recipient_email" ]; then
        echo -e "${YELLOW}⚠️  SKIPPED - No email provided${NC}"
    else
        # Create email request JSON
        cat > /tmp/test_email_request.json << EOF
{
  "employee_name": "Test Employee",
  "pay_period_num": 1,
  "year": 2025,
  "week_start_date": "2025-01-06T00:00:00Z",
  "week_number_label": "Week 1",
  "jobs": [
    {
      "job_code": "JOB001",
      "job_name": "Test Job"
    }
  ],
  "entries": [
    {
      "date": "2025-01-06T00:00:00Z",
      "job_code": "JOB001",
      "hours": 8.0,
      "overtime": false
    }
  ],
  "to": "$recipient_email",
  "subject": "Test Timecard - Week 1",
  "body": "This is a test timecard email from the API test script."
}
EOF
        
        echo "Sending email to: $recipient_email"
        echo ""
        
        response=$(curl -s -w "\n%{http_code}" \
          -X POST "$BASE_URL/api/email-timecard" \
          -H "Content-Type: application/json" \
          -d @/tmp/test_email_request.json \
          --max-time 120)
        
        body=$(echo "$response" | head -n -1)
        status=$(echo "$response" | tail -n 1)
        
        if [ "$status" -eq 200 ]; then
            echo -e "${GREEN}✅ PASS${NC} - Status: $status"
            echo "Response: $body"
            echo ""
            echo "📧 Check your inbox at $recipient_email"
        else
            echo -e "${RED}❌ FAIL${NC} - Status: $status"
            echo "Response: $body"
            
            if [[ "$body" == *"SMTP"* ]]; then
                echo ""
                echo -e "${YELLOW}💡 Tip: Make sure SMTP environment variables are set:${NC}"
                echo "   - SMTP_HOST"
                echo "   - SMTP_PORT"
                echo "   - SMTP_USERNAME"
                echo "   - SMTP_PASSWORD"
            fi
        fi
    fi
else
    echo -e "${YELLOW}⚠️  SKIPPED - Email test skipped${NC}"
fi

echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Base URL: $BASE_URL"
echo ""
echo "Generated files:"
echo "  • Excel: /tmp/test_timecard.xlsx"
echo "  • Request: /tmp/test_timecard_request.json"
echo ""
echo -e "${GREEN}✅ Testing complete!${NC}"
echo ""

# Cleanup prompt
read -p "Delete temporary files? (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f /tmp/test_timecard_request.json /tmp/test_email_request.json
    echo "Temporary files deleted (Excel file kept)"
else
    echo "Temporary files kept in /tmp/"
fi
