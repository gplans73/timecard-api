# Template Cell Analysis

Based on your Excel template screenshot, I can see:

Row 4: "Sun Dat" in B4 - This should get the Sunday date
Row 5-11: Days of week with dates in column B (B5=Sun, B6=Mon, etc.)
Row 16-22: OT section dates 
Column M2: Employee name ✅ (this is working)

The issue is that your template structure is different from what the code expects.

Could you help me understand:
1. In your template, which column should get the HOURS data? (looks like it might be a column further right)
2. Which column should get the PROJECT names?
3. Are there specific cells for different types of hours (Regular vs OT)?

This will help me fix the cell mappings in your API.