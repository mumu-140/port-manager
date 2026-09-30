import Foundation

/// Central translation registry.
///
/// Entries live in per-domain files (`Strings/*Strings.swift`) as
/// `[key: (en:, zh:)]` maps, keeping English and Simplified Chinese adjacent so
/// the two never drift. Keys are dot-namespaced by domain
/// (`common.*`, `settings.*`, `ports.*`, `tunnel.*`, `k8s.*`, `notification.*`,
/// `error.*`, `menubar.*`).
enum LocalizationTables {
    static let all: [String: (en: String, zh: String)] = {
        var merged: [String: (en: String, zh: String)] = [:]
        let groups: [[String: (en: String, zh: String)]] = [
            CommonStrings.entries,
            SettingsStrings.entries,
            PortStrings.entries,
            TunnelStrings.entries,
            KubernetesStrings.entries,
            NotificationStrings.entries,
            ErrorStrings.entries,
            MenuBarStrings.entries,
            OnboardingStrings.entries,
            SponsorStrings.entries,
            ManagedServiceStrings.entries,
        ]
        for group in groups {
            merged.merge(group) { current, _ in current }
        }
        return merged
    }()

    static func lookup(_ key: String, _ lang: ResolvedLanguage) -> String {
        guard let pair = all[key] else {
            #if DEBUG
            print("⚠️ [i18n] missing key: \(key)")
            #endif
            return key
        }
        switch lang {
        case .english: return pair.en
        case .simplifiedChinese: return pair.zh
        }
    }
}
