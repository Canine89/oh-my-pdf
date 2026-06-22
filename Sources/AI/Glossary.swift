import Foundation

enum GlossaryError: LocalizedError {
    case missingColumns

    var errorDescription: String? {
        switch self {
        case .missingColumns:
            return "CSV에 before, after 열이 필요합니다."
        }
    }
}

enum Glossary {
    static func loadCSV(from url: URL) throws -> [GlossaryRule] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSV(text)
        guard let header = rows.first else { return [] }
        let normalized = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let beforeIndex = normalized.firstIndex(of: "before"),
              let afterIndex = normalized.firstIndex(of: "after") else {
            throw GlossaryError.missingColumns
        }
        return rows.dropFirst().compactMap { row in
            guard row.indices.contains(beforeIndex), row.indices.contains(afterIndex) else { return nil }
            let before = row[beforeIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let after = row[afterIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !before.isEmpty, before != after else { return nil }
            return GlossaryRule(original: before, corrected: after)
        }
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        if next == "," {
                            row.append(field)
                            field = ""
                        } else if next == "\n" {
                            row.append(field)
                            rows.append(row)
                            row = []
                            field = ""
                        } else if next != "\r" {
                            field.append(next)
                        }
                    }
                } else {
                    inQuotes.toggle()
                }
            } else if character == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if character == "\n" && !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
