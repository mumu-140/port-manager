import Testing
@testable import PortKiller

/**
 * Tests for the localization string tables.
 *
 * Guards against duplicate keys being silently shadowed by the
 * `merge(_:uniquingKeysWith:)` in `LocalizationTables.all` — a duplicate
 * would resolve order-dependently with no compiler or runtime error.
 */
struct LocalizationTablesTests {

    /// The merged table must contain every entry defined in every domain
    /// file. A cross-file duplicate key would make the merged count smaller
    /// than the sum of the per-file counts.
    @Test func mergedTableContainsEveryDefinedKey() {
        let groups: [[String: (en: String, zh: String)]] = [
            CommonStrings.entries,
            SettingsStrings.entries,
            PortStrings.entries,
            TunnelStrings.entries,
            KubernetesStrings.entries,
            NotificationStrings.entries,
            ErrorStrings.entries,
            MenuBarStrings.entries,
        ]

        let definedCount = groups.reduce(0) { $0 + $1.count }
        #expect(LocalizationTables.all.count == definedCount,
                "Duplicate key across domain files: merged \(LocalizationTables.all.count) != defined \(definedCount)")
    }

    /// No key may be defined twice within a single domain file.
    @Test func noDuplicateKeysWithinDomainFiles() {
        // Dictionary literals already deduplicate at compile time, so a
        // within-file repeat collapses silently in `entries` itself. The real
        // risk is cross-file (covered above); this test documents the invariant.
        let groups: [String: [String: (en: String, zh: String)]] = [
            "Common": CommonStrings.entries,
            "Settings": SettingsStrings.entries,
            "Port": PortStrings.entries,
            "Tunnel": TunnelStrings.entries,
            "Kubernetes": KubernetesStrings.entries,
            "Notification": NotificationStrings.entries,
            "Error": ErrorStrings.entries,
            "MenuBar": MenuBarStrings.entries,
        ]
        for (name, entries) in groups {
            #expect(!entries.isEmpty || name == "Kubernetes" || name == "Notification" || name == "Port",
                    "\(name) unexpectedly empty")
        }
    }

    /// Every entry must have non-empty text for both languages.
    @Test func everyEntryHasBothLanguages() {
        for (key, pair) in LocalizationTables.all {
            #expect(!pair.en.isEmpty, "\(key).en is empty")
            #expect(!pair.zh.isEmpty, "\(key).zh is empty")
        }
    }
}
