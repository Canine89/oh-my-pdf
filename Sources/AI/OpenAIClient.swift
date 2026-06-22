import Foundation

enum OpenAIClientError: LocalizedError {
    case missingAPIKey
    case badResponse
    case api(String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "OpenAI API 키가 저장되어 있지 않습니다."
        case .badResponse: return "OpenAI 응답을 읽을 수 없습니다."
        case .api(let message): return message
        case .invalidJSON: return "GPT 응답 JSON 파싱에 실패했습니다."
        }
    }
}

final class OpenAIClient {
    func correct(text: String, options: CorrectionOptions) async throws -> CorrectionResult {
        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload(text: text, options: options))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIClientError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "OpenAI API 오류: \(http.statusCode)"
            throw OpenAIClientError.api(message)
        }

        let content = try extractOutputText(from: data)
        guard let jsonData = content.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(GPTCorrectionPayload.self, from: jsonData) else {
            throw OpenAIClientError.invalidJSON
        }

        return CorrectionResult(original: text,
                                corrected: decoded.correctedText,
                                corrections: decoded.corrections,
                                useGPT: true,
                                gptModel: options.gptModel)
    }

    private func payload(text: String, options: CorrectionOptions) -> [String: Any] {
        let prompt = """
        당신은 한국어 출판 원고 교정자입니다. 맞춤법, 띄어쓰기, 조사, 번역투, 문체 오류만 최소 수정하세요.
        의미를 바꾸거나 원문에 없는 단어를 추가하지 마세요. 코드 문단, 고유명사, 브랜드명은 임의로 바꾸지 마세요.
        수정할 내용이 없어도 설명하지 말고 JSON만 반환하세요.
        JSON 형식:
        {"corrected_text":"교정된 전체 텍스트","corrections":[{"original":"원문에 실제 존재하는 구문","corrected":"수정 구문","type":"spelling","explanation":"교정 이유"}]}

        옵션:
        correction_strength=\(options.correctionStrength.rawValue)
        check_passive_voice=\(options.checkPassiveVoice)
        tone=\(options.tone)

        원문:
        \(text)
        """

        return [
            "model": options.gptModel,
            "input": prompt,
            "temperature": 0.1
        ]
    }

    private func extractOutputText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIClientError.badResponse
        }
        if let outputText = object["output_text"] as? String {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let output = object["output"] as? [[String: Any]] else {
            throw OpenAIClientError.badResponse
        }
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let text = part["text"] as? String {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        throw OpenAIClientError.badResponse
    }
}

private struct GPTCorrectionPayload: Codable {
    let correctedText: String
    let corrections: [TextCorrection]

    enum CodingKeys: String, CodingKey {
        case correctedText = "corrected_text"
        case corrections
    }
}
