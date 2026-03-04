import Foundation

/// Manages app localization with runtime language switching.
/// Uses Bundle.module lproj resources for SPM-based localization.
@Observable
package class LocalizationService {
    package static let shared = LocalizationService()

    package var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "appLanguage")
            loadBundle()
        }
    }

    private var localizedBundle: Bundle

    private init() {
        self.language = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        self.localizedBundle = Bundle.module
        loadBundle()
    }

    private func loadBundle() {
        if let path = Bundle.module.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            localizedBundle = bundle
        } else {
            localizedBundle = Bundle.module
        }
    }

    /// Returns a localized string for the given key.
    package func localized(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// Available languages
    package var availableLanguages: [(code: String, name: String)] {
        [
            ("en", "English"),
            ("tr", "Türkçe"),
        ]
    }
}

/// Convenience function for localization
package func L(_ key: String) -> String {
    LocalizationService.shared.localized(key)
}
