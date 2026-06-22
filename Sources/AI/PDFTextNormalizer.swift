import Foundation

enum PDFTextNormalizer {
    static func normalizePageText(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var paragraphs: [String] = []
        var current = ""

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                appendCurrent(&current, to: &paragraphs)
                continue
            }
            if current.isEmpty {
                current = line
            } else if shouldJoin(previous: current, next: line) {
                current += joiner(previous: current, next: line) + line
            } else {
                appendCurrent(&current, to: &paragraphs)
                current = line
            }
        }

        appendCurrent(&current, to: &paragraphs)
        return paragraphs.joined(separator: "\n")
    }

    private static func appendCurrent(_ current: inout String, to paragraphs: inout [String]) {
        let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { paragraphs.append(value) }
        current = ""
    }

    private static func shouldJoin(previous: String, next: String) -> Bool {
        guard let last = previous.last, let first = next.first else { return false }
        if ".!?。？！:：;；".contains(last) { return false }
        if "•-*·".contains(first) { return false }
        if next.range(of: #"^\d+[\).\s]"#, options: .regularExpression) != nil { return false }
        return true
    }

    private static func joiner(previous: String, next: String) -> String {
        guard let last = previous.last, let first = next.first else { return " " }
        if isKorean(last) && isKorean(first) { return " " }
        if last == "-" { return "" }
        return " "
    }

    private static func isKorean(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0xAC00...0xD7A3).contains(Int(scalar.value))
            || (0x3130...0x318F).contains(Int(scalar.value))
            || (0x1100...0x11FF).contains(Int(scalar.value))
    }
}
