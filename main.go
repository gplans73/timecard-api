#!/bin/bash

echo "=== Timecard API main.go Verification Script ==="
echo ""

# Check if main.go exists
if [ ! -f "main.go" ]; then
    echo "❌ ERROR: main.go not found in current directory!"
    echo "Please run this script from your timecard-api directory"
    exit 1
fi

# Check line count
LINE_COUNT=$(wc -l < main.go)
echo "📊 Line count: $LINE_COUNT"

if [ "$LINE_COUNT" -eq 724 ]; then
    echo "✅ Correct line count (724)"
else
    echo "❌ WRONG line count! Should be 724, got $LINE_COUNT"
    echo "   You have the WRONG file!"
fi

# Check for template.xlsx loading
if grep -q "excelize.OpenFile.*template.xlsx" main.go; then
    echo "✅ Uses template.xlsx"
else
    echo "❌ Does NOT use template.xlsx"
    echo "   You have the WRONG file!"
fi

# Check line 186
echo ""
echo "🔍 Checking line 186..."
LINE_186=$(sed -n '186p' main.go)
echo "   Line 186: $LINE_186"

if echo "$LINE_186" | grep -q "bytes"; then
    echo "❌ Line 186 contains 'bytes' - this is WRONG!"
    echo "   You have the OLD BROKEN file!"
else
    echo "✅ Line 186 looks correct"
fi

# Check for standalone bytes import
if head -20 main.go | grep -E '^\s+"bytes"$' > /dev/null; then
    echo "❌ Found standalone 'bytes' import - this is WRONG!"
    echo "   You have the OLD BROKEN file!"
else
    echo "✅ No standalone 'bytes' import"
fi

echo ""
echo "=== Summary ==="
if [ "$LINE_COUNT" -eq 724 ] && grep -q "excelize.OpenFile.*template.xlsx" main.go && ! echo "$LINE_186" | grep -q "bytes"; then
    echo "🎉 You have the CORRECT file!"
    echo "   Safe to commit and push"
else
    echo "❌ You have the WRONG file!"
    echo "   DO NOT commit and push yet!"
    echo ""
    echo "Fix: Download the correct file from Claude's output"
    echo "     It should be 724 lines and load template.xlsx"
fi
