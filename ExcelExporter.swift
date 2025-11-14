import Foundation

// ExcelExporter bridges to SwiftXLSX when present, else falls back to the local XLSXWriter.
// To enable SwiftXLSX, add the package via Xcode (File > Add Packages...) and ensure the module
// can be imported as `SwiftXLSX`. If the module name differs, update the `canImport` below.

enum ExcelExporter {
    static func makeWorkbookData(sheetName: String = "Entries", rows: [[String]]) throws -> Data {
        #if canImport(SwiftXLSX)
        return try makeWithSwiftXLSX(sheetName: sheetName, rows: rows)
        #else
        return try XLSXWriter.makeWorkbook(sheetName: sheetName, rows: rows)
        #endif
    }
}

#if canImport(SwiftXLSX)
import SwiftXLSX

private extension ExcelExporter {
    static func makeWithSwiftXLSX(sheetName: String, rows: [[String]]) throws -> Data {
        // NOTE: Adjust API calls below to match the exact SwiftXLSX API.
        // The structure below assumes a Workbook -> Worksheet -> Cells style API.

        // Create workbook and sheet
        let workbook = XLSXWorkbook()
        let sheet = workbook.addWorksheet(named: sheetName)

        // Populate rows and cells
        for (rIndex, row) in rows.enumerated() {
            for (cIndex, value) in row.enumerated() {
                let rowNumber = rIndex + 1
                let colNumber = cIndex + 1
                if let number = Double(value) {
                    sheet.write(number: number, row: rowNumber, column: colNumber)
                } else {
                    sheet.write(string: value, row: rowNumber, column: colNumber)
                }
            }
        }

        // Serialize to Data
        return try workbook.data()
    }
}
#endif
