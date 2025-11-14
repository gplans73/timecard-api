# Template Excel File

This directory should contain a file named `template.xlsx` that serves as your timecard template.

Since I cannot create binary Excel files directly, you need to:

1. Create an Excel file with your desired timecard format
2. Name it `template.xlsx` 
3. Place it in the root of your repository
4. Ensure it has sheets named "Week 1" and "Week 2"
5. Make sure the following cells exist:
   - M2: Employee name
   - B4: Week start date
   - B5-B11: Main dates (Sun-Sat)
   - B16-B22: OT dates (Sun-Sat)

The template should match the layout your code expects with cells for:
- Employee name at M2
- Date ranges starting at B5 and B16
- Proper sheet names ("Week 1", "Week 2")