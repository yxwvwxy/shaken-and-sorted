import Foundation

enum APIKeyStore {
    private static let key = "openai_api_key"

    static var openAIKey: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var hasOpenAIKey: Bool {
        !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
