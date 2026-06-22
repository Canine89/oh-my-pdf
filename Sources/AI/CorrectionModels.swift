import Foundation

enum CorrectionStrength: String, CaseIterable {
    case ultraMinimal = "ultra_minimal"
    case minimal
    case conservative
    case balanced
    case aggressive
    case veryAggressive = "very_aggressive"

    var threshold: Double {
        switch self {
        case .ultraMinimal: return 0.98
        case .minimal: return 0.90
        case .conservative: return 0.75
        case .balanced: return 0.65
        case .aggressive: return 0.45
        case .veryAggressive: return 0.25
        }
    }

    var label: String {
        switch self {
        case .ultraMinimal: return "극소"
        case .minimal: return "최소"
        case .conservative: return "보수"
        case .balanced: return "균형"
        case .aggressive: return "적극"
        case .veryAggressive: return "매우 적극"
        }
    }
}

struct CorrectionOptions {
    var useGPT: Bool
    var gptModel: String = "gpt-4.1-mini"
    var correctionStrength: CorrectionStrength
    var usePublisherRules: Bool
    var joinAuxiliaryVerbs: Bool
    var checkPassiveVoice: Bool = false
    var tone: String = ""
}

struct TextCorrection: Codable, Equatable {
    var original: String
    var corrected: String
    var type: String
    var explanation: String
}

struct CorrectionResult: Codable {
    var original: String
    var corrected: String
    var corrections: [TextCorrection]
    var useGPT: Bool
    var gptModel: String
}

struct PageCorrectionResult {
    var pageIndex: Int
    var originalText: String
    var normalizedText: String
    var correctedText: String
    var corrections: [TextCorrection]

    var hasErrors: Bool {
        !corrections.isEmpty
    }
}

struct GlossaryRule: Codable, Equatable {
    var original: String
    var corrected: String
}
