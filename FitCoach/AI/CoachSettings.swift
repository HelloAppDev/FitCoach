import Foundation
import Observation

struct LLMConfig: Sendable {
    let baseURLString: String
    let model: String
    let apiKey: String
}

@MainActor
@Observable
final class CoachSettings {
    static let shared = CoachSettings()

    private static let defaults = UserDefaults.standard
    private enum Keys {
        static let baseURL = "coach.baseURL"
        static let model = "coach.model"
        static let apiKey = "coach.apiKey"
    }

    static let defaultBaseURL = "http://127.0.0.1:11434/v1"
    static let defaultModel = "gemma3:4b"

    var baseURLString: String {
        didSet { Self.defaults.set(baseURLString, forKey: Keys.baseURL) }
    }
    var model: String {
        didSet { Self.defaults.set(model, forKey: Keys.model) }
    }
    var apiKey: String {
        didSet { Self.defaults.set(apiKey, forKey: Keys.apiKey) }
    }

    private init() {
        baseURLString = Self.defaults.string(forKey: Keys.baseURL) ?? Self.defaultBaseURL
        model = Self.defaults.string(forKey: Keys.model) ?? Self.defaultModel
        apiKey = Self.defaults.string(forKey: Keys.apiKey) ?? ""
    }

    var config: LLMConfig {
        LLMConfig(baseURLString: baseURLString, model: model, apiKey: apiKey)
    }
}
