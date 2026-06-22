import Foundation

final class CorrectionEngine {
    private let client: OpenAIClient

    init(client: OpenAIClient = OpenAIClient()) {
        self.client = client
    }

    func correct(text: String, options: CorrectionOptions, glossary: [GlossaryRule]) async throws -> CorrectionResult {
        let original = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CorrectionResult(original: original, corrected: original, corrections: [], useGPT: options.useGPT, gptModel: options.gptModel)
        }
        guard !Self.isLikelyCode(text) else {
            return CorrectionResult(original: original, corrected: original, corrections: [], useGPT: false, gptModel: options.gptModel)
        }

        let publisher = options.usePublisherRules ? applyGlossary(to: text, rules: glossary) : (text, [])
        var corrected = publisher.0
        var corrections = publisher.1

        if options.useGPT {
            let gpt = try await client.correct(text: corrected, options: options)
            if validate(gpt: gpt, source: corrected, threshold: options.correctionStrength.threshold) {
                corrected = gpt.corrected
                corrections.append(contentsOf: gpt.corrections)
            }
        }

        if options.joinAuxiliaryVerbs {
            let aux = applyAuxiliaryVerbRules(to: corrected)
            corrected = aux.0
            corrections.append(contentsOf: aux.1)
        }

        corrections = mergeAndFilter(corrections, original: original, finalText: corrected)
        return CorrectionResult(original: original, corrected: corrected, corrections: corrections, useGPT: options.useGPT, gptModel: options.gptModel)
    }

    private func applyGlossary(to text: String, rules: [GlossaryRule]) -> (String, [TextCorrection]) {
        var result = text
        var corrections: [TextCorrection] = []

        for rule in rules where !rule.original.isEmpty {
            let before = result
            result = replaceWithBoundaryAwareness(result, original: rule.original, corrected: rule.corrected)
            if before != result {
                corrections.append(TextCorrection(original: rule.original,
                                                  corrected: rule.corrected,
                                                  type: "publisher_rule",
                                                  explanation: "CSV 용어집 치환"))
            }
        }
        return (result, corrections)
    }

    private func replaceWithBoundaryAwareness(_ text: String, original: String, corrected: String) -> String {
        guard original.contains(" ") || corrected.contains(" ") else {
            return text.replacingOccurrences(of: original, with: corrected)
        }
        let escaped = NSRegularExpression.escapedPattern(for: original)
        let pattern = #"(?<![A-Za-z0-9가-힣])"# + escaped + #"(?![A-Za-z0-9가-힣])"#
        return text.replacingOccurrences(of: pattern, with: corrected, options: .regularExpression)
    }

    private func validate(gpt: CorrectionResult, source: String, threshold: Double) -> Bool {
        let trimmed = gpt.corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("수정할 내용이 없습니다") else { return false }
        guard !trimmed.contains("맞춤법이 올바릅니다") else { return false }
        guard StringSimilarity.ratio(source, gpt.corrected) >= threshold else { return false }
        return gpt.corrections.allSatisfy { correction in
            source.contains(correction.original)
                && !correction.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && correction.original != correction.corrected
                && !isDangerousWhitespaceOnlyChange(correction)
        }
    }

    private func isDangerousWhitespaceOnlyChange(_ correction: TextCorrection) -> Bool {
        let originalCompact = correction.original.replacingOccurrences(of: " ", with: "")
        let correctedCompact = correction.corrected.replacingOccurrences(of: " ", with: "")
        return originalCompact == correctedCompact
            && correction.original.count > 3
            && correction.corrected.count < correction.original.count - 2
    }

    private func applyAuxiliaryVerbRules(to text: String) -> (String, [TextCorrection]) {
        let rules = [
            GlossaryRule(original: "되어 보", corrected: "되어보"),
            GlossaryRule(original: "해 보", corrected: "해보"),
            GlossaryRule(original: "읽어 보", corrected: "읽어보"),
            GlossaryRule(original: "살펴 보", corrected: "살펴보")
        ]
        return applyGlossary(to: text, rules: rules)
    }

    private func mergeAndFilter(_ corrections: [TextCorrection], original: String, finalText: String) -> [TextCorrection] {
        var seen = Set<String>()
        return corrections.filter { correction in
            guard correction.original != correction.corrected else { return false }
            guard original.contains(correction.original) || finalText.contains(correction.corrected) else { return false }
            let key = "\(correction.original)\u{1F}\(correction.corrected)\u{1F}\(correction.type)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    static func isLikelyCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^(def|class|import|return|const|let|var|SELECT|UPDATE|INSERT|DELETE)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        let koreanCount = trimmed.unicodeScalars.filter { (0xAC00...0xD7A3).contains(Int($0.value)) }.count
        let codeMarks = trimmed.filter { "{};=<>".contains($0) }.count
        return koreanCount == 0 && codeMarks >= 3
    }
}
