import Foundation
import Observation
import os
import Defaults

// MARK: - Persistence

extension Defaults.Keys {
    /// Selected UI language. `.system` (default) follows the OS.
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)
}

extension AppLanguage: Defaults.Serializable {}

// MARK: - Nonisolated snapshot

/// Thread-safe snapshot of the active language so strings can be resolved from
/// ANY context — including nonisolated `LocalizedError` descriptions and
/// background tasks — without hopping to the main actor. Updated by
/// `Localization` whenever the selection changes.
private let activeLanguageBox = OSAllocatedUnfairLock<ResolvedLanguage>(initialState: .english)

// MARK: - Manager

/// Observable holder of the current UI language.
///
/// SwiftUI live-switching: the root scenes read `language` and key their content
/// on it (`.id(localization.language)`), so changing the selection rebuilds the
/// UI and every `L(...)` call re-resolves against the new language.
@MainActor
@Observable
final class Localization {
    static let shared = Localization()

    /// The user's selection. Persisted and mirrored into the nonisolated snapshot.
    var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            Defaults[.appLanguage] = language
            // Capture before the lock: the withLock closure is Sendable and
            // cannot read main-actor state under NonisolatedNonsendingByDefault.
            let resolved = language.resolved
            activeLanguageBox.withLock { $0 = resolved }
        }
    }

    private init() {
        let saved = Defaults[.appLanguage]
        self.language = saved
        activeLanguageBox.withLock { $0 = saved.resolved }
    }
}

// MARK: - Lookup

/// Localized string for `key`. Nonisolated: safe from views, managers, error
/// types, and background tasks alike. Falls back to English, then to the raw
/// key (so a missing translation is visible rather than blank).
func L(_ key: String) -> String {
    let lang = activeLanguageBox.withLock { $0 }
    return LocalizationTables.lookup(key, lang)
}

/// Localized format string filled with `args` (uses positional `%@`/`%d` specifiers).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
