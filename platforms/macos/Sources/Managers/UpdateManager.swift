import Foundation
import Sparkle
import AppKit
import Observation
import Combine

/**
 * UpdateManager handles automatic updates using the Sparkle framework.
 *
 * Key features:
 * - Demand-driven initialization (does not preload on launch)
 * - Only initializes when running from .app bundle (not during development)
 * - Activates app before showing update UI (important for menu bar apps)
 * - Tracks update availability and last check date
 *
 * This class uses the @Observable macro for SwiftUI reactivity and is
 * marked with @MainActor to ensure all UI updates happen on the main thread.
 */
@Observable
@MainActor
final class UpdateManager {
    // MARK: - Public Properties

    /// Whether the independently configured updater is ready.
    var canCheckForUpdates = UpdateManager.isRunningFromBundle && UpdateManager.isUpdaterConfigured

    /// Timestamp of the last update check
    var lastUpdateCheckDate: Date?

    // MARK: - Private Properties

    /// Sparkle updater controller instance
    private var updaterController: SPUStandardUpdaterController?

    /// Tracks whether Sparkle has been initialized
    private var isInitialized = false

    /// Check if running from a proper app bundle (not swift run)
    private static var isRunningFromBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// Require this fork's own feed URL and EdDSA key before starting Sparkle.
    /// This prevents any accidental fallback to an upstream update channel.
    private static var isUpdaterConfigured: Bool {
        guard
            let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            !feedURL.isEmpty,
            let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !publicKey.isEmpty
        else {
            return false
        }
        return true
    }

    // MARK: - Computed Properties

    /**
     * Whether to automatically check for updates on launch.
     * Setting this value will trigger Sparkle initialization if needed.
     */
    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set {
            ensureInitialized()
            updaterController?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /**
     * Whether to automatically download updates in the background.
     * Setting this value will trigger Sparkle initialization if needed.
     */
    var automaticallyDownloadsUpdates: Bool {
        get { updaterController?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            ensureInitialized()
            updaterController?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    // MARK: - Initialization

    /// Initializes the update manager in a cold state.
    /// Sparkle is initialized only when an update API is actually used.
    init() {}

    // MARK: - Private Methods

    /**
     * Ensures Sparkle is initialized before use.
     * This is called automatically when needed and is safe to call multiple times.
     * Skips initialization when not running from an .app bundle (development mode).
     */
    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true

        guard Self.isRunningFromBundle, Self.isUpdaterConfigured else {
            canCheckForUpdates = false
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        lastUpdateCheckDate = controller.updater.lastUpdateCheckDate

        // Observe Sparkle properties and update our @Observable properties
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)

        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] value in
                self?.lastUpdateCheckDate = value
            }
            .store(in: &cancellables)
    }

    /// Storage for Combine cancellables.
    /// Note: These subscriptions live for the app's lifetime alongside the UpdateManager,
    /// so cleanup in deinit is not necessary. The subscriptions are intentionally retained.
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // MARK: - Public Methods

    /**
     * Manually checks for updates.
     * Activates the app and brings the update window to the front.
     * This is important for menu bar apps that don't normally have visible windows.
     */
    func checkForUpdates() {
        ensureInitialized()
        guard let controller = updaterController else { return }
        // Activate app to ensure Sparkle window appears in front
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
