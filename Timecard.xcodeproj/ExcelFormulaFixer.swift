import Foundation
#if canImport(Compression)
import Compression
#endif

/// Post-processes Excel (.xlsx) files to force formula recalculation
/// Fixes the issue where formulas don't calculate until you manually edit cells
struct ExcelFormulaFixer {
    
    // MARK: - Public API
    
    /// Process an Excel file to force formula recalculation on open
    /// - Parameter xlsxData: The original Excel file data
    /// - Returns: Modified Excel file data with formula calculation enabled
    /// - Throws: ExcelFixerError if processing fails
    static func fixFormulas(in xlsxData: Data) throws -> Data {
        print("🔧 Starting Excel formula fix...")
        
        // Step 1: Unzip the XLSX file
        let entries = try unzipXLSX(xlsxData)
        print("   ✓ Extracted \(entries.count) files from XLSX")
        
        // Step 2: Modify workbook.xml to enable auto-calculation
        var modifiedEntries = entries
        if let workbookIndex = modifiedEntries.firstIndex(where: { $0.path == "xl/workbook.xml" }) {
            let modifiedWorkbook = try modifyWorkbook(modifiedEntries[workbookIndex].data)
            modifiedEntries[workbookIndex] = XLSXEntry(
                path: "xl/workbook.xml",
                data: modifiedWorkbook
            )
            print("   ✓ Modified workbook.xml for auto-calculation")
        } else {
            print("   ⚠️ workbook.xml not found")
        }
        
        // Step 3: Remove calc chain if it exists (forces full recalc)
        modifiedEntries.removeAll { $0.path == "xl/calcChain.xml" }
        
        // Step 4: Update [Content_Types].xml to remove calcChain reference
        if let contentTypesIndex = modifiedEntries.firstIndex(where: { $0.path == "[Content_Types].xml" }) {
            let modifiedContentTypes = try removeCalcChainFromContentTypes(modifiedEntries[contentTypesIndex].data)
            modifiedEntries[contentTypesIndex] = XLSXEntry(
                path: "[Content_Types].xml",
                data: modifiedContentTypes
            )
            print("   ✓ Removed calcChain references")
        }
        
        // Step 5: Re-zip into XLSX
        let fixedXLSX = try zipXLSX(modifiedEntries)
        print("   ✓ Created fixed XLSX (\(fixedXLSX.count) bytes)")
        print("✅ Excel formula fix complete!")
        
        return fixedXLSX
    }
    
    // MARK: - XML Modification
    
    /// Modify workbook.xml to enable auto-calculation
    private static func modifyWorkbook(_ data: Data) throws -> Data {
        guard var xml = String(data: data, encoding: .utf8) else {
            throw ExcelFixerError.invalidXML("workbook.xml")
        }
        
        // Remove any existing calcPr element (calculation properties)
        // This forces Excel to use default auto-calculation
        if let calcPrRange = xml.range(of: #"<calcPr[^>]*/?>"#, options: .regularExpression) {
            xml.removeSubrange(calcPrRange)
        }
        
        // Ensure workbookPr exists and doesn't have calcMode set
        // If workbookPr exists, make sure it doesn't specify calcMode="manual"
        xml = xml.replacingOccurrences(
            of: #"calcMode="[^"]*""#,
            with: "",
            options: .regularExpression
        )
        
        // Alternative: Explicitly set calcMode="auto" in workbookPr
        if xml.contains("<workbookPr") {
            xml = xml.replacingOccurrences(
                of: "<workbookPr",
                with: "<workbookPr calcMode=\"auto\""
            )
        }
        
        return Data(xml.utf8)
    }
    
    /// Remove calcChain reference from [Content_Types].xml
    private static func removeCalcChainFromContentTypes(_ data: Data) throws -> Data {
        guard var xml = String(data: data, encoding: .utf8) else {
            throw ExcelFixerError.invalidXML("[Content_Types].xml")
        }
        
        // Remove the Override entry for calcChain.xml
        if let calcChainRange = xml.range(
            of: #"<Override[^>]*calcChain\.xml[^>]*/>"#,
            options: .regularExpression
        ) {
            xml.removeSubrange(calcChainRange)
        }
        
        return Data(xml.utf8)
    }
    
    // MARK: - ZIP Handling
    
    /// Unzip XLSX file into individual entries
    private static func unzipXLSX(_ data: Data) throws -> [XLSXEntry] {
        var entries: [XLSXEntry] = []
        var offset = 0
        
        while offset < data.count - 30 { // Minimum header size
            // Check for local file header signature (0x04034b50)
            let signature = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
            
            if signature != 0x04034b50 {
                // Might be central directory or end record - stop parsing
                break
            }
            
            // Parse local file header
            offset += 4 // Skip signature
            offset += 2 // Version needed
            let flags = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }
            offset += 2
            let compression = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }
            offset += 2
            offset += 4 // Time/Date
            offset += 4 // CRC32
            let compressedSize = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
            offset += 4
            let uncompressedSize = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
            offset += 4
            let filenameLength = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }
            offset += 2
            let extraLength = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }
            offset += 2
            
            // Read filename
            let filenameData = data.subdata(in: offset..<offset + Int(filenameLength))
            guard let filename = String(data: filenameData, encoding: .utf8) else {
                throw ExcelFixerError.corruptedZIP
            }
            offset += Int(filenameLength)
            
            // Skip extra field
            offset += Int(extraLength)
            
            // Read file data
            let fileData = data.subdata(in: offset..<offset + Int(compressedSize))
            offset += Int(compressedSize)
            
            // Decompress if needed
            let finalData: Data
            if compression == 8 { // Deflate
                #if canImport(Compression)
                finalData = try decompress(fileData, expectedSize: Int(uncompressedSize))
                #else
                throw ExcelFixerError.compressionNotSupported
                #endif
            } else if compression == 0 { // Stored (no compression)
                finalData = fileData
            } else {
                throw ExcelFixerError.unsupportedCompression(compression)
            }
            
            entries.append(XLSXEntry(path: filename, data: finalData))
        }
        
        if entries.isEmpty {
            throw ExcelFixerError.corruptedZIP
        }
        
        return entries
    }
    
    /// Zip entries back into XLSX format
    private static func zipXLSX(_ entries: [XLSXEntry]) throws -> Data {
        var data = Data()
        var centralDirectory = Data()
        var localHeaderOffsets: [Int] = []
        let now = Date()
        let (dosTime, dosDate) = msDosTimeDate(from: now)
        
        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let localHeaderOffset = data.count
            localHeaderOffsets.append(localHeaderOffset)
            
            // Compress the data
            #if canImport(Compression)
            let compressedData = try compress(entry.data)
            let compression: UInt16 = 8 // Deflate
            #else
            let compressedData = entry.data
            let compression: UInt16 = 0 // Stored
            #endif
            
            // Local file header
            data.append(uint32LE(0x04034b50)) // signature
            data.append(uint16LE(20)) // version needed to extract
            data.append(uint16LE(0)) // general purpose bit flag
            data.append(uint16LE(compression)) // compression method
            data.append(uint16LE(UInt16(dosTime)))
            data.append(uint16LE(UInt16(dosDate)))
            data.append(uint32LE(crc))
            data.append(uint32LE(UInt32(compressedData.count))) // compressed size
            data.append(uint32LE(UInt32(entry.data.count))) // uncompressed size
            data.append(uint16LE(UInt16(nameData.count))) // file name length
            data.append(uint16LE(0)) // extra field length
            data.append(nameData)
            data.append(compressedData)
            
            // Central directory header
            var cd = Data()
            cd.append(uint32LE(0x02014b50)) // central file header signature
            cd.append(uint16LE(20)) // version made by
            cd.append(uint16LE(20)) // version needed to extract
            cd.append(uint16LE(0)) // general purpose bit flag
            cd.append(uint16LE(compression)) // compression method
            cd.append(uint16LE(UInt16(dosTime)))
            cd.append(uint16LE(UInt16(dosDate)))
            cd.append(uint32LE(crc))
            cd.append(uint32LE(UInt32(compressedData.count)))
            cd.append(uint32LE(UInt32(entry.data.count)))
            cd.append(uint16LE(UInt16(nameData.count))) // file name length
            cd.append(uint16LE(0)) // extra length
            cd.append(uint16LE(0)) // file comment length
            cd.append(uint16LE(0)) // disk number start
            cd.append(uint16LE(0)) // internal file attributes
            cd.append(uint32LE(0)) // external file attributes
            cd.append(uint32LE(UInt32(localHeaderOffset))) // relative offset of local header
            cd.append(nameData)
            centralDirectory.append(cd)
        }
        
        let centralDirectoryOffset = data.count
        data.append(centralDirectory)
        let centralDirectorySize = data.count - centralDirectoryOffset
        
        // End of central directory record
        data.append(uint32LE(0x06054b50)) // signature
        data.append(uint16LE(0)) // number of this disk
        data.append(uint16LE(0)) // number of the disk with the start of the central directory
        data.append(uint16LE(UInt16(entries.count))) // total entries on this disk
        data.append(uint16LE(UInt16(entries.count))) // total entries
        data.append(uint32LE(UInt32(centralDirectorySize))) // size of central directory
        data.append(uint32LE(UInt32(centralDirectoryOffset))) // offset of start of central directory
        data.append(uint16LE(0)) // .ZIP file comment length
        
        return data
    }
    
    // MARK: - Compression (iOS 13+)
    
    #if canImport(Compression)
    /// Decompress deflate data
    private static func decompress(_ data: Data, expectedSize: Int) throws -> Data {
        let bufferSize = max(expectedSize, 8192)
        var decompressed = Data(count: bufferSize)
        
        let size = data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Int in
            decompressed.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) -> Int in
                let inputBuffer = input.bindMemory(to: UInt8.self)
                let outputBuffer = output.bindMemory(to: UInt8.self)
                
                return compression_decode_buffer(
                    outputBuffer.baseAddress!,
                    outputBuffer.count,
                    inputBuffer.baseAddress!,
                    inputBuffer.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        
        if size == 0 {
            throw ExcelFixerError.decompressionFailed
        }
        
        decompressed.count = size
        return decompressed
    }
    
    /// Compress data using deflate
    private static func compress(_ data: Data) throws -> Data {
        let bufferSize = data.count
        var compressed = Data(count: bufferSize)
        
        let size = data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Int in
            compressed.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) -> Int in
                let inputBuffer = input.bindMemory(to: UInt8.self)
                let outputBuffer = output.bindMemory(to: UInt8.self)
                
                return compression_encode_buffer(
                    outputBuffer.baseAddress!,
                    outputBuffer.count,
                    inputBuffer.baseAddress!,
                    inputBuffer.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        
        if size == 0 {
            // Compression failed, return uncompressed
            return data
        }
        
        compressed.count = size
        return compressed
    }
    #endif
    
    // MARK: - Helpers
    
    private static func uint16LE(_ v: UInt16) -> Data {
        withUnsafeBytes(of: v.littleEndian) { Data($0) }
    }
    
    private static func uint32LE(_ v: UInt32) -> Data {
        withUnsafeBytes(of: v.littleEndian) { Data($0) }
    }
    
    private static func msDosTimeDate(from date: Date) -> (UInt16, UInt16) {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = UInt16(max(1980, (comps.year ?? 1980)))
        let month = UInt16(comps.month ?? 1)
        let day = UInt16(comps.day ?? 1)
        let hour = UInt16(comps.hour ?? 0)
        let minute = UInt16(comps.minute ?? 0)
        let second = UInt16(comps.second ?? 0) / 2
        let dosTime = (hour << 11) | (minute << 5) | second
        let dosDate = ((year - 1980) << 9) | (month << 5) | day
        return (dosTime, dosDate)
    }
}

// MARK: - Supporting Types

private struct XLSXEntry {
    let path: String
    let data: Data
}

// MARK: - Debugging Extensions

extension ExcelFormulaFixer {
    /// Analyzes an Excel file and returns diagnostic information
    /// Useful for debugging formula calculation issues
    static func diagnose(_ xlsxData: Data) -> ExcelDiagnostics {
        do {
            let entries = try unzipXLSX(xlsxData)
            
            var diagnostics = ExcelDiagnostics(
                fileSize: xlsxData.count,
                entryCount: entries.count,
                hasWorkbook: entries.contains(where: { $0.path == "xl/workbook.xml" }),
                hasCalcChain: entries.contains(where: { $0.path == "xl/calcChain.xml" }),
                worksheetCount: entries.filter { $0.path.hasPrefix("xl/worksheets/sheet") }.count
            )
            
            // Analyze workbook.xml
            if let workbook = entries.first(where: { $0.path == "xl/workbook.xml" }),
               let xml = String(data: workbook.data, encoding: .utf8) {
                diagnostics.calcMode = extractCalcMode(from: xml)
                diagnostics.hasCalcPr = xml.contains("<calcPr")
            }
            
            return diagnostics
            
        } catch {
            return ExcelDiagnostics(
                fileSize: xlsxData.count,
                entryCount: 0,
                hasWorkbook: false,
                hasCalcChain: false,
                worksheetCount: 0,
                error: error.localizedDescription
            )
        }
    }
    
    private static func extractCalcMode(from xml: String) -> String? {
        if let range = xml.range(of: #"calcMode="([^"]*)""#, options: .regularExpression) {
            let match = String(xml[range])
            let parts = match.split(separator: "\"")
            return parts.count > 1 ? String(parts[1]) : nil
        }
        return nil
    }
}

struct ExcelDiagnostics {
    let fileSize: Int
    let entryCount: Int
    let hasWorkbook: Bool
    let hasCalcChain: Bool
    let worksheetCount: Int
    var calcMode: String?
    var hasCalcPr: Bool = false
    var error: String?
    
    var needsFormulaFix: Bool {
        // Needs fix if calcMode is manual, or if calcPr exists, or if calcChain exists
        return calcMode == "manual" || hasCalcPr || hasCalcChain
    }
    
    var description: String {
        var lines = [
            "📊 Excel File Diagnostics",
            "  Size: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))",
            "  Entries: \(entryCount)",
            "  Worksheets: \(worksheetCount)"
        ]
        
        if let mode = calcMode {
            lines.append("  Calc Mode: \(mode)")
        }
        
        if hasCalcPr {
            lines.append("  ⚠️ Has calcPr (may prevent auto-calc)")
        }
        
        if hasCalcChain {
            lines.append("  ⚠️ Has calcChain (may be stale)")
        }
        
        if needsFormulaFix {
            lines.append("  🔧 Needs formula fix: YES")
        } else {
            lines.append("  ✅ Needs formula fix: NO")
        }
        
        if let error = error {
            lines.append("  ❌ Error: \(error)")
        }
        
        return lines.joined(separator: "\n")
    }
}

enum ExcelFixerError: Error, LocalizedError {
    case invalidXML(String)
    case corruptedZIP
    case compressionNotSupported
    case unsupportedCompression(UInt16)
    case decompressionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidXML(let file):
            return "Invalid XML in \(file)"
        case .corruptedZIP:
            return "Corrupted ZIP/XLSX file"
        case .compressionNotSupported:
            return "Compression not supported on this platform"
        case .unsupportedCompression(let method):
            return "Unsupported compression method: \(method)"
        case .decompressionFailed:
            return "Failed to decompress file"
        }
    }
}

// MARK: - CRC32 (same as XLSXWriter)

private struct CRC32 {
    private static var table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if (c & 1) != 0 { c = 0xEDB88320 ^ (c >> 1) } else { c = c >> 1 }
            }
            return c
        }
    }()
    
    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for byte in buf { c = CRC32.table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFFFFFF
    }
}
