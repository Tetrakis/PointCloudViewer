import Foundation

enum ImportError: LocalizedError {
    case emptyFile
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:         return "The file is empty."
        case .unreadable(let s): return "Cannot read file: \(s)"
        }
    }
}

struct CSVImporter {

    /// Loads a CSV or TSV file from disk.  Runs on a background thread.
    static func load(url: URL) throws -> PointCloudData {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.unreadable("Security-scoped access denied.")
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let content = (try? String(contentsOf: url, encoding: .utf8)) ??
                            (try? String(contentsOf: url, encoding: .isoLatin1))
        else { throw ImportError.unreadable(url.lastPathComponent) }

        // Detect delimiter
        let firstLine = content.prefix(while: { $0 != "\n" && $0 != "\r" })
        let delimiter: Character = firstLine.contains("\t") ? "\t" : ","

        var lines = content.components(separatedBy: .newlines)
        lines.removeAll { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw ImportError.emptyFile }

        // Parse header
        let rawHeader = lines.removeFirst()
        let headers = split(line: rawHeader, delimiter: delimiter)

        // Determine column count from header
        let colCount = headers.count

        // Parse rows
        var rows: [PointRow] = []
        rows.reserveCapacity(lines.count)
        for (i, line) in lines.enumerated() {
            var vals = split(line: line, delimiter: delimiter)
            // Pad or trim to header length
            while vals.count < colCount { vals.append("") }
            if vals.count > colCount { vals = Array(vals.prefix(colCount)) }
            rows.append(PointRow(id: i, rawValues: vals))
        }

        return PointCloudData(headers: headers, rows: rows)
    }

    // Handles quoted fields correctly
    private static func split(line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == delimiter && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }
}
