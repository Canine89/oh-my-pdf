import Foundation

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    private init() {}

    private enum Keys {
        static let correctionStrength = "correctionStrength"
        static let useGPT = "useGPT"
        static let joinAuxiliaryVerbs = "joinAuxiliaryVerbs"
        static let usePublisherRules = "usePublisherRules"
    }

    var useGPT: Bool {
        get { defaults.object(forKey: Keys.useGPT) == nil ? true : defaults.bool(forKey: Keys.useGPT) }
        set { defaults.set(newValue, forKey: Keys.useGPT) }
    }

    var usePublisherRules: Bool {
        get { defaults.object(forKey: Keys.usePublisherRules) == nil ? true : defaults.bool(forKey: Keys.usePublisherRules) }
        set { defaults.set(newValue, forKey: Keys.usePublisherRules) }
    }

    var joinAuxiliaryVerbs: Bool {
        get { defaults.object(forKey: Keys.joinAuxiliaryVerbs) == nil ? true : defaults.bool(forKey: Keys.joinAuxiliaryVerbs) }
        set { defaults.set(newValue, forKey: Keys.joinAuxiliaryVerbs) }
    }

    var correctionStrength: CorrectionStrength {
        get { CorrectionStrength(rawValue: defaults.string(forKey: Keys.correctionStrength) ?? "") ?? .balanced }
        set { defaults.set(newValue.rawValue, forKey: Keys.correctionStrength) }
    }
}
