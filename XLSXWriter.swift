import Foundation

import Foundation

// Minimal XLSX generator without third-party dependencies.
// Produces a single-sheet workbook with inline strings and numeric cells (hours).
// Files are stored (no compression) in a ZIP container as required by XLSX.

struct XLSXWriter {
    // Public API: build an .xlsx Data from a 2D array of cell strings.
    // Numeric-looking values are written as numbers; others as inline strings.
    static func makeWorkbook(sheetName: String = "Entries", rows: [[String]]) throws -> Data {
        // Build XML parts
        let contentTypes = Self.contentTypesXML()
        let relsRels = Self.rootRelsXML()
        let workbook = Self.workbookXML()
        let workbookRels = Self.workbookRelsXML()
        let styles = Self.stylesXML()
        let sheet = Self.sheetXML(rows: rows)

        // Package into ZIP (.xlsx)
        let entries: [ZipEntry] = [
            ZipEntry(path: "[Content_Types].xml", data: contentTypes),
            ZipEntry(path: "_rels/.rels", data: relsRels),
            ZipEntry(path: "xl/workbook.xml", data: workbook),
            ZipEntry(path: "xl/_rels/workbook.xml.rels", data: workbookRels),
            ZipEntry(path: "xl/styles.xml", data: styles),
            ZipEntry(path: "xl/worksheets/sheet1.xml", data: sheet)
        ]
        return try ZipWriter.write(entries: entries)
    }
}

// MARK: - XML Builders
private extension XLSXWriter {
    static func contentTypesXML() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
        return Data(xml.utf8)
    }

    static func rootRelsXML() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        return Data(xml.utf8)
    }

    static func workbookXML() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Entries" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
        return Data(xml.utf8)
    }

    static func workbookRelsXML() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
        return Data(xml.utf8)
    }

    static func stylesXML() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"/>
        """
        return Data(xml.utf8)
    }

    static func sheetXML(rows: [[String]]) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">\n"
        xml += "  <sheetData>\n"
        for (rIndex, row) in rows.enumerated() {
            let r = rIndex + 1
            xml += "    <row r=\"\(r)\">\n"
            for (cIndex, value) in row.enumerated() {
                let cellRef = "\(columnName(for: cIndex))\(r)"
                if let num = Double(value) { // numeric cell
                    xml += "      <c r=\"\(cellRef)\"><v>\(trimTrailingZeros(num))</v></c>\n"
                } else {
                    xml += "      <c r=\"\(cellRef)\" t=\"inlineStr\"><is><t>\(escapeXML(value))</t></is></c>\n"
                }
            }
            xml += "    </row>\n"
        }
        xml += "  </sheetData>\n"
        xml += "</worksheet>\n"
        return Data(xml.utf8)
    }

    static func columnName(for index: Int) -> String {
        var i = index
        var name = ""
        repeat {
            let rem = i % 26
            name = String(UnicodeScalar(65 + rem)!) + name
            i = (i / 26) - 1
        } while i >= 0
        return name
    }

    static func escapeXML(_ s: String) -> String {
        var v = s.replacingOccurrences(of: "&", with: "&amp;")
        v = v.replacingOccurrences(of: "<", with: "&lt;")
        v = v.replacingOccurrences(of: ">", with: "&gt;")
        v = v.replacingOccurrences(of: "\"", with: "&quot;")
        v = v.replacingOccurrences(of: "'", with: "&apos;")
        return v
    }

    static func trimTrailingZeros(_ d: Double) -> String {
        var s = String(format: "%g", d)
        // %g already removes trailing zeros; ensure dot handling
        if s.contains(".") {
            while s.last == "0" { s.removeLast() }
            if s.last == "." { s.removeLast() }
        }
        return s
    }
}

// MARK: - ZIP Writer (stored, no compression)
private struct ZipEntry {
    let path: String
    let data: Data
}

private struct ZipWriter {
    static func write(entries: [ZipEntry]) throws -> Data {
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

            // Local file header
            data.append(uint32LE(0x04034b50)) // signature
            data.append(uint16LE(20)) // version needed to extract
            data.append(uint16LE(0)) // general purpose bit flag
            data.append(uint16LE(0)) // compression method (0 = stored)
            data.append(uint16LE(UInt16(dosTime)))
            data.append(uint16LE(UInt16(dosDate)))
            data.append(uint32LE(crc))
            data.append(uint32LE(UInt32(entry.data.count))) // compressed size
            data.append(uint32LE(UInt32(entry.data.count))) // uncompressed size
            data.append(uint16LE(UInt16(nameData.count))) // file name length
            data.append(uint16LE(0)) // extra field length
            data.append(nameData)
            // file data
            data.append(entry.data)

            // Central directory header for this entry (we'll build later)
            var cd = Data()
            cd.append(uint32LE(0x02014b50)) // central file header signature
            cd.append(uint16LE(20)) // version made by
            cd.append(uint16LE(20)) // version needed to extract
            cd.append(uint16LE(0)) // general purpose bit flag
            cd.append(uint16LE(0)) // compression method
            cd.append(uint16LE(UInt16(dosTime)))
            cd.append(uint16LE(UInt16(dosDate)))
            cd.append(uint32LE(crc))
            cd.append(uint32LE(UInt32(entry.data.count)))
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

    private static func uint16LE(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian, { Data($0) }) }
    private static func uint32LE(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian, { Data($0) }) }

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

// MARK: - CRC32
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
