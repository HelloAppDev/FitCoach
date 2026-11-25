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
        static let apiKey = "coach.apiKey"
    }

    static let defaultBaseURL = "http://127.0.0.1:11434/v1"
    static let model = "gemma3:4b"

    var baseURLString: String {
        didSet { Self.defaults.set(baseURLString, forKey: Keys.baseURL) }
    }
    var apiKey: String {
        didSet { Self.defaults.set(apiKey, forKey: Keys.apiKey) }
    }

    private init() {
        baseURLString = Self.defaults.string(forKey: Keys.baseURL) ?? Self.defaultBaseURL
        apiKey = Self.defaults.string(forKey: Keys.apiKey) ?? ""
    }

    var config: LLMConfig {
        LLMConfig(baseURLString: baseURLString, model: Self.model, apiKey: apiKey)
    }
}
