# TestGoAPI - Testing Framework for Timecard API

## 📝 Overview

This testing framework provides a comprehensive way to test your Go-based Timecard API integration from Swift.

## 🏗️ Architecture

The testing framework is split into **modular files** to avoid compilation errors when dependencies are missing:

### Core Files (Required)

- **`TestGoAPI.swift`** - Main test runner with health check and timecard generation tests
- **`TimecardAPIService.swift`** - Defines API models (`GoTimecardRequest`, `GoEmailTimecardRequest`)

### Optional Extensions

- **`TestGoAPI+FormulaFixer.swift`** - Optional extension for Excel formula testing
  - Only include if you want to test ExcelFormulaFixer functionality
  - Requires `ExcelFormulaFixer.swift` to be in the same target

- **`ExcelFormulaFixer.swift`** - Excel formula fixing utility
  - Only needed if using the formula fixer extension

## 🚀 Quick Start

### Basic Usage (No Formula Testing)

1. Add these files to your target:
   - `TestGoAPI.swift`
   - `TimecardAPIService.swift`

2. Run the tests:
   ```swift
   await TestGoAPI.runTests()
   ```

### With Formula Testing

1. Add all files to your target:
   - `TestGoAPI.swift`
   - `TimecardAPIService.swift`
   - `TestGoAPI+FormulaFixer.swift` ✨
   - `ExcelFormulaFixer.swift` ✨

2. In `TestGoAPI.swift`, uncomment:
   ```swift
   await testExcelFormulaFixer()
   ```

3. Run the tests:
   ```swift
   await TestGoAPI.runTests()
   ```

## 🎯 Benefits of This Approach

✅ **No Compilation Errors** - Missing files don't break the build  
✅ **Modular** - Only include what you need  
✅ **Apple-Style** - Uses extensions for optional functionality  
✅ **Clear Dependencies** - Documentation shows what's required  

## 🔧 Troubleshooting

### "Cannot find 'GoTimecardRequest' in scope"
→ Add `TimecardAPIService.swift` to your target

### "Cannot find 'ExcelFormulaFixer' in scope"
→ Either:
  - Remove `TestGoAPI+FormulaFixer.swift` from your target, OR
  - Add `ExcelFormulaFixer.swift` to your target

### "Cannot find 'testExcelFormulaFixer' in scope"
→ Add `TestGoAPI+FormulaFixer.swift` to your target

## 📱 Platform Support

- iOS 13.0+
- macOS 10.15+
- Requires `Compression` framework for formula testing

## 🧪 Test Cases

1. **Health Check** - Tests API availability
2. **Generate Timecard** - Tests Excel file generation
3. **Formula Fixer** *(optional)* - Tests formula recalculation fix
4. **Email Timecard** *(optional)* - Tests email functionality

---

*This modular approach follows Apple's design principles for framework organization.*
