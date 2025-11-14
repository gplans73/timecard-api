#!/bin/bash
# Test Night Shift API Endpoint
# This script sends a test request to your Go API to verify night shift handling

echo "🌙 Testing Night Shift Hours API"
echo ""

# Test with night shift entry
curl -X POST https://timecard-api.onrender.com/api/generate-timecard \
  -H "Content-Type: application/json" \
  -d '{
    "employee_name": "Test Employee",
    "pay_period_num": 1,
    "year": 2025,
    "week_start_date": "2025-11-10T00:00:00Z",
    "week_number_label": "Week 1",
    "jobs": [
      {
        "job_code": "12215",
        "job_name": "Job 201"
      },
      {
        "job_code": "92408",
        "job_name": "Job 223"
      }
    ],
    "entries": [
      {
        "date": "2025-11-09T00:00:00Z",
        "job_code": "12215",
        "hours": 1.0,
        "overtime": false,
        "night_shift": false
      },
      {
        "date": "2025-11-10T00:00:00Z",
        "job_code": "12215",
        "hours": 0.5,
        "overtime": false,
        "night_shift": false
      },
      {
        "date": "2025-11-10T00:00:00Z",
        "job_code": "92408",
        "hours": 0.5,
        "overtime": false,
        "night_shift": true
      }
    ]
  }' \
  --output test_night_shift.xlsx

echo ""
echo "✅ Response saved to test_night_shift.xlsx"
echo ""
echo "📊 Expected Excel output:"
echo "   Row 12 (TOTAL REGULAR):"
echo "      Job 12215: 1.5 hours"
echo "      Job 92408: 0.0 hours"
echo "   Row 13 (TOTAL NIGHT):"
echo "      Job 12215: 0.0 hours"
echo "      Job 92408: 0.5 hours ⭐️ VERIFY THIS!"
echo "   Row 14 (Overtime):"
echo "      All jobs: 0.0 hours"
echo ""
echo "Open test_night_shift.xlsx to verify the output"
