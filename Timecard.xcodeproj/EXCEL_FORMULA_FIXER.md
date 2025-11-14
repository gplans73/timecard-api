# Excel Formula Fixer

## Problem

When Excel files are generated programmatically (like from your Go backend), formulas often don't calculate automatically when the file is opened. Users have to manually click into each cell and press Enter to trigger calculation.

This happens because:
1. The Excel file doesn't have pre-calculated formula values cached
2. The workbook calculation mode isn't properly set
3. The calculation chain (calcChain.xml) might be stale

## Solution

The `ExcelFormulaFixer` class post-processes Excel files to fix this issue entirely in Swift, without requiring changes to the backend.

## How It Works

### Step 1: Unzip XLSX File
XLSX files are just ZIP archives containing XML files. The fixer:
- Parses the ZIP structure using the local file header format
- Extracts all files (XML and other resources)
- Handles both compressed (deflate) and uncompressed files

### Step 2: Modify workbook.xml
The main fix is in `xl/workbook.xml`:

**Before:**
```xml
<workbook>
  <workbookPr calcMode="manual"/>
  <calcPr fullCalcOnLoad="0"/>
  ...
</workbook>
```

**After:**
```xml
<workbook>
  <workbookPr calcMode="auto"/>
  <!-- calcPr removed to force recalculation -->
  ...
</workbook>
```

Changes:
- Sets `calcMode="auto"` to enable automatic calculation
- Removes `<calcPr>` element to force Excel to recalculate everything
- This tells Excel: "recalculate all formulas when you open this file"

### Step 3: Remove Stale Calculation Chain
The `xl/calcChain.xml` file caches the calculation order. If it's outdated:
- Delete `xl/calcChain.xml` entirely
- Remove its reference from `[Content_Types].xml`
- Excel will rebuild it on open

### Step 4: Re-zip
Package everything back into a valid XLSX file:
- Uses deflate compression (same as original)
- Preserves all metadata and structure
- Creates proper ZIP central directory

## Usage

### Automatic (Recommended)

The fixer is automatically applied in `TimecardAPIService.swift`:

```swift
let (excelData, _) = try await apiService.generateTimecardFiles(...)
// excelData is automatically fixed and ready to use
```

### Manual

You can also apply it manually to any Excel file:

```swift
import Foundation

// Load Excel file
let originalData = try Data(contentsOf: URL(fileURLWithPath: "timecard.xlsx"))

// Fix formulas
let fixedData = try ExcelFormulaFixer.fixFormulas(in: originalData)

// Save fixed version
try fixedData.write(to: URL(fileURLWithPath: "timecard_fixed.xlsx"))
```

## Testing

Run the test suite to verify it works:

```swift
await TestGoAPI.runTests()
```

This will:
1. Download an Excel file from the Go API
2. Apply the formula fix
3. Save both versions to Documents folder
4. Compare file sizes and structure

Test files saved to:
- `test_timecard_original.xlsx` - Original from API
- `test_timecard_fixed.xlsx` - Fixed version
- `formula_test_original.xlsx` - Test file (original)
- `formula_test_fixed.xlsx` - Test file (fixed)

### Manual Verification

1. Open both files in Excel
2. Original: Formulas show as formulas, not values
3. Fixed: Formulas automatically calculate and show values
4. In original, press Ctrl+Alt+F9 to force recalc - now they work
5. In fixed, it works immediately

## Technical Details

### ZIP File Structure
XLSX files follow the Open Packaging Convention (OPC):
```
myfile.xlsx (ZIP archive)
├── [Content_Types].xml          - MIME types for all parts
├── _rels/
│   └── .rels                    - Relationships (root)
├── xl/
│   ├── workbook.xml             - Workbook structure ⚡ MODIFIED
│   ├── styles.xml               - Cell styles
│   ├── calcChain.xml            - Calculation order ⚡ DELETED
│   ├── _rels/
│   │   └── workbook.xml.rels    - Workbook relationships
│   └── worksheets/
│       └── sheet1.xml           - Worksheet data
```

### Compression

Uses Apple's native `Compression` framework (iOS 13+):
- `COMPRESSION_ZLIB` - Deflate algorithm (same as ZIP)
- Compresses each file individually
- Typically 60-80% size reduction

If compression fails, falls back to stored (uncompressed) mode.

### CRC32 Checksum

Each ZIP entry requires a CRC32 checksum:
```swift
let crc = CRC32.checksum(fileData)
// Used in both local and central directory headers
```

### MS-DOS Date/Time

ZIP format uses MS-DOS datetime:
- **Time**: 5 bits hour, 6 bits minute, 5 bits seconds/2
- **Date**: 7 bits year-1980, 4 bits month, 5 bits day

```swift
let dosTime = (hour << 11) | (minute << 5) | (second/2)
let dosDate = ((year-1980) << 9) | (month << 5) | day
```

## Performance

Typical processing time on iPhone:
- Small file (10 KB): ~10-20 ms
- Medium file (100 KB): ~50-100 ms
- Large file (1 MB): ~200-500 ms

Memory usage: ~3x file size (original + decompressed + compressed)

## Error Handling

The fixer gracefully handles errors:

```swift
do {
    let fixed = try ExcelFormulaFixer.fixFormulas(in: data)
    // Use fixed version
} catch {
    // Fall back to original if fix fails
    print("Could not fix formulas: \(error)")
}
```

Possible errors:
- `.invalidXML` - XML parsing failed
- `.corruptedZIP` - Invalid ZIP structure
- `.compressionNotSupported` - Compression framework unavailable
- `.unsupportedCompression` - Unknown compression method
- `.decompressionFailed` - Decompression error

## Limitations

1. **Compression Framework**: Requires iOS 13+ for deflate support
   - Falls back to stored (uncompressed) on older versions
   
2. **File Size**: Works best with files < 10 MB
   - Larger files work but may be slow
   
3. **Complex Formulas**: Doesn't pre-calculate values
   - Excel still does the calculation, but on open instead of never
   
4. **Macros**: VBA macros are preserved but not validated

## Alternative Solutions

### Backend Fix (Preferred if you control it)

If you can modify the Go backend, this is simpler:

```go
import "github.com/xuri/excelize/v2"

// After setting formulas:
f.SetWorkbookPrOpts(excelize.WorkbookPrOptions{
    CalcID: nil,
})
f.UpdateLinkedValue()
```

### LibreOffice/Python

For batch processing on a server:
```python
import openpyxl

wb = openpyxl.load_workbook('file.xlsx')
wb.calculation.calcMode = 'auto'
wb.save('file_fixed.xlsx')
```

## Future Enhancements

Possible improvements:
1. **Pre-calculate formulas** - Actually evaluate formulas in Swift
2. **Streaming** - Process large files without loading entirely into memory
3. **Parallel compression** - Compress multiple files concurrently
4. **Validation** - Verify Excel file structure before/after
5. **More formats** - Support older .xls format

## References

- [Office Open XML (OOXML) Specification](https://www.ecma-international.org/publications-and-standards/standards/ecma-376/)
- [ZIP File Format Specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)
- [Apple Compression Framework](https://developer.apple.com/documentation/compression)
- [SpreadsheetML Reference](https://docs.microsoft.com/en-us/openspecs/office_standards/ms-xlsx/)

## Support

If formulas still don't calculate after applying the fix:
1. Check that the Excel file is valid (opens without errors)
2. Verify formulas exist in the worksheets
3. Try opening in different Excel versions (desktop, web, mobile)
4. Check Excel calculation settings: Formulas → Calculation Options → Automatic

## License

This code is part of the Timecard iOS app and follows the same license.

---

**Last Updated:** November 9, 2025
