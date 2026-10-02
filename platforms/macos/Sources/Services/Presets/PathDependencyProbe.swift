import Foundation

/// Result of a read-only dependency probe.
enum DependencyProbeState: Equatable {
    /// Binary found at this path.
    case available(path: String)
    /// Binary not found (covers the CommandLineTools python3 stub case with
    /// tailored copy keyed by DependencyRequirement.stubCopyKey).
    case notInstalled
}

/// Read-only binary discovery, generalized from the cloudflared probe
/// (CloudflaredService.cloudflaredPath): known paths first, then a PATH walk,
/// then per-requirement fallback dirs. Results are cached; `recheck()`
/// invalidates. Strictly fileExists + PATH walking — never executes the
/// binary for detection, never writes anything, never hits the network.
///
/// Runs on demand (preset picker / preset form), never at app launch.
struct PathDependencyProbe {
    /// Injectable existence check (temp-dir tests swap this).
    private let fileExists: (String) -> Bool
    /// Injectable executable check (tests mark files executable or not).
    private let isExecutableFile: (String) -> Bool
    /// Injectable PATH entries (tests pass temp dirs).
    private let pathEntries: () -> [String]

    private var cache: [String: DependencyProbeState] = [:]

    init(
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isExecutableFile: @escaping (String) -> Bool = {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: $0, isDirectory: &isDir), !isDir.boolValue else { return false }
            return FileManager.default.isExecutableFile(atPath: $0)
        },
        pathEntries: @escaping () -> [String] = {
            let raw = ProcessInfo.processInfo.environment["PATH"] ?? ""
            return raw.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        }
    ) {
        self.fileExists = fileExists
        self.isExecutableFile = isExecutableFile
        self.pathEntries = pathEntries
    }

    /// Cached probe.
    mutating func state(for requirement: DependencyRequirement) -> DependencyProbeState {
        if let cached = cache[requirement.binaryName] {
            return cached
        }
        let fresh = freshState(for: requirement)
        cache[requirement.binaryName] = fresh
        return fresh
    }

    /// Drops the cache; next probe runs again (cloudflared recheck affordance).
    mutating func recheck() {
        cache.removeAll()
    }

    /// Convenience: resolved path when available.
    mutating func resolvedPath(for requirement: DependencyRequirement) -> String? {
        if case .available(let path) = state(for: requirement) {
            return path
        }
        return nil
    }

    // MARK: - Probe rules

    private func freshState(for requirement: DependencyRequirement) -> DependencyProbeState {
        // 1. Known absolute paths (first hit wins; homebrew before /usr).
        for path in requirement.knownPaths {
            guard fileExists(path), isExecutableFile(path) else { continue }
            if requirement.binaryName == "python3", path == "/usr/bin/python3", isCommandLineToolsStub(path) {
                continue
            }
            return .available(path: path)
        }

        // 2. PATH walk (which-equivalent, no subprocess).
        for dir in pathEntries() {
            let candidate = dir + "/" + requirement.binaryName
            if fileExists(candidate), isExecutableFile(candidate) {
                return .available(path: candidate)
            }
        }

        // 3. Per-requirement fallback dirs (~ expansion for pip layouts).
        for dir in requirement.fallbackPaths {
            let expanded = (dir as NSString).expandingTildeInPath
            let candidate = expanded + "/" + requirement.binaryName
            if fileExists(candidate), isExecutableFile(candidate) {
                return .available(path: candidate)
            }
        }

        return .notInstalled
    }

    /// The /usr/bin/python3 CommandLineTools stub is a tiny shim that pops the
    /// CLT installer on first run — it must never be reported as available and
    /// never be executed. Stub detection is size-based and read-only: the real
    /// interpreter is megabytes, the stub is a few kilobytes.
    private func isCommandLineToolsStub(_ path: String) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return size < 1_000_000
    }
}
