import Foundation

// MARK: - App Information

/**
 * AppInfo provides application metadata and external links for the independently
 * maintained mumu-140/port-manager fork.
 *
 * The PortKiller product name is retained for compatibility with existing app
 * bundles, preferences, launch items, and cross-platform package names.
 */
enum AppInfo {
    static let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
    }()

    static let build: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }()

    static let versionString: String = {
        "v\(version) (\(build))"
    }()

    static let maintainer = "mumu-140"

    static let githubRepo = "https://github.com/mumu-140/port-manager"
    static let githubReleases = "\(githubRepo)/releases"
    static let githubIssues = "\(githubRepo)/issues"
    static let supportURL = "\(githubRepo)#support-the-project"

    /// Historical source of this fork. Attribution only; not a runtime dependency.
    static let upstreamRepo = "https://github.com/productdevbook/port-killer"
}

// MARK: - Application Constants

enum AppConstants {
    static let defaultRefreshInterval: Int = 5
    static let killGracePeriod: Duration = .milliseconds(500)
    static let maxCommandLength: Int = 200
    static let sponsorCacheExpiry: TimeInterval = 86400
}

// MARK: - UI Constants

enum UIConstants {
    enum MenuBar {
        static let width: CGFloat = 340
        static let maxHeight: CGFloat = 400
        static let rowHeight: CGFloat = 44
    }

    enum MainWindow {
        static let minWidth: CGFloat = 800
        static let minHeight: CGFloat = 500
    }
}
