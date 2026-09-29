import Foundation

/// User-selectable UI language.
///
/// `.system` follows the OS preferred languages; the others force a specific
/// language regardless of the system setting. Persisted via `Defaults`
/// (see `Localization.swift`). Phase 1 ships English + Simplified Chinese.
enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    /// Concrete language to use for lookups, resolving `.system` against the OS.
    var resolved: ResolvedLanguage {
        switch self {
        case .english: return .english
        case .simplifiedChinese: return .simplifiedChinese
        case .system: return AppLanguage.systemPreferred
        }
    }

    /// Best match among the OS preferred languages. Any Chinese variant maps to
    /// Simplified (the only Chinese shipped in phase 1); everything else → English.
    static var systemPreferred: ResolvedLanguage {
        for code in Locale.preferredLanguages {
            let lower = code.lowercased()
            if lower.hasPrefix("zh") { return .simplifiedChinese }
            if lower.hasPrefix("en") { return .english }
        }
        return .english
    }
}

/// A concrete language actually present in the translation tables (never `.system`).
enum ResolvedLanguage: String, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}
