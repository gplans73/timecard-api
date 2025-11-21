{
  "employee_name": "Jane Smith",
  "pay_period_num": 2,
  "year": 2025,
  "include_pdf": true,
  "to": "employee@example.com",
  "cc": "manager@example.com,hr@example.com",
  "subject": "Timecard for Pay Period 2 - January 2025",
  "body": "Hello,\n\nPlease find attached your timecard for Pay Period 2.\n\nRegular Hours: 80.0\nOvertime Hours: 4.0\n\nIf you have any questions, please contact HR.\n\nBest regards,\nPayroll Team",
  "jobs": [
    {
      "job_code": "ADMIN",
      "job_name": "Administrative Tasks"
    },
    {
      "job_code": "CLIENT-A",
      "job_name": "Client A Project"
    },
    {
      "job_code": "CLIENT-B",
      "job_name": "Client B Maintenance"
    }
  ],
  "weeks": [
    {
      "week_start_date": "2025-01-20T00:00:00Z",
      "week_label": "Week 1",
      "entries": [
        {
          "date": "2025-01-20T00:00:00Z",
          "job_code": "CLIENT-A",
          "hours": 8.0,
          "overtime": false
        },
        {
          "date": "2025-01-21T00:00:00Z",
          "job_code": "CLIENT-A",
          "hours": 8.0,
          "overtime": false
        },
        {
          "date": "2025-01-22T00:00:00Z",
          "job_code": "CLIENT-B",
          "hours": 8.0,
          "overtime": false
        },
        {
          "date": "2025-01-23T00:00:00Z",
          "job_code": "CLIENT-B",
          "hours": 8.0,
          "overtime": false
        },
        {
          "date": "2025-01-24T00:00:00Z",
          "job_code": "ADMIN",
          "hours": 8.0,
          "overtime": false
        },
        {
          "date": "2025-01-24T00:00:00Z",
          "job_code": "CLIENT-A",
          "hours": 2.0,
          "overtime": true
        }
      ]
    },
    {
      "week_start_date": "2025-01-27T00:00:00Z",
      "week_label": "Week 2",
      "entries": [
        {
          "date": "2025-01-27T00:00:00Z",
          "job_code": "CLIENT-A",
          "hours": 8.0,
          "overtime": false
        },
        {
          "date": "2025-01-28T00:00:00Z",
          "job_code": "CLIENT-A",
          "hours": 8.0,
          "overtime": false
        },
        {
          "date": "2025-01-29T00:00:00Z",
          "job_code": "CLIENT-B",
          "hours": 8.0,
          "overtime": false
        },
        {
          "date": "2025-01-30T00:00:00Z",
          "job_code": "CLIENT-B",
          "hours": 8.0,
          "overtime": false
        },
        {
          "date": "2025-01-31T00:00:00Z",
          "job_code": "ADMIN",
          "hours": 6.0,
          "overtime": false
        },
        {
          "date": "2025-01-31T00:00:00Z",
          "job_code": "CLIENT-A",
          "hours": 2.0,
          "overtime": false
        },
        {
          "date": "2025-01-31T00:00:00Z",
          "job_code": "CLIENT-A",
          "hours": 2.0,
          "overtime": true
        }
      ]
    }
  ]
}
