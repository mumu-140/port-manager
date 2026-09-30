/**
 * ManagedServiceRuntimeLog.swift
 * PortKiller
 *
 * File-backed runtime output for managed services.
 *
 * Managed foreground services are allowed to outlive Port Manager (design
 * notes, section 6.5). A parent-owned `Pipe` cannot support that guarantee:
 * once the app exits the read end closes, and the child dies with SIGPIPE the
 * next time it writes to stdout or stderr. Runtime output is therefore
 * redirected to temporary files that no app process has to keep open, and the
 * running app tails them to build its bounded in-memory log.
 *
 * Logs are runtime artifacts, never profile data. They live under the system
 * temporary directory, are truncated for every launch, and are removed on
 * explicit cleanup and on the next app startup. Files are created with
 * owner-only permissions because child output can contain anything the child
 * chooses to print.
 */

import Foundation

/// Owns the on-disk locations and lifecycle of managed-service output logs.
enum ManagedServiceRuntimeLogStore {
    /// Directory name under the system temporary directory.
    static let directoryName = "PortManagerManagedServices"

    /// File name used for both streams; the stream is implied by the file.
    static let stdoutFileName = "stdout.log"
    static let stderrFileName = "stderr.log"

    /// Root directory holding every service's runtime logs.
    static func rootDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Per-service runtime log directory.
    static func directory(for serviceID: UUID, fileManager: FileManager = .default) -> URL {
        rootDirectory(fileManager: fileManager)
            .appendingPathComponent(serviceID.uuidString, isDirectory: true)
    }

    /// Path of the captured standard-output file.
    static func stdoutURL(for serviceID: UUID, fileManager: FileManager = .default) -> URL {
        directory(for: serviceID, fileManager: fileManager)
            .appendingPathComponent(stdoutFileName)
    }

    /// Path of the captured standard-error file.
    static func stderrURL(for serviceID: UUID, fileManager: FileManager = .default) -> URL {
        directory(for: serviceID, fileManager: fileManager)
            .appendingPathComponent(stderrFileName)
    }

    /// Creates (or truncates) the per-service log directory and returns it.
    ///
    /// Existing logs for the same profile are removed first so a relaunch can
    /// never append to a previous run's output.
    @discardableResult
    static func prepare(for serviceID: UUID, fileManager: FileManager = .default) throws -> URL {
        let directory = directory(for: serviceID, fileManager: fileManager)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        for url in [stdoutURL(for: serviceID, fileManager: fileManager),
                    stderrURL(for: serviceID, fileManager: fileManager)] {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            let created = fileManager.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
            guard created else { throw CocoaError(.fileWriteUnknown) }
        }

        return directory
    }

    /// Removes the runtime logs of one service.
    ///
    /// Used on explicit cleanup (profile removal). A still-running child that
    /// already holds the file descriptor keeps writing to the unlinked inode;
    /// this only discards the on-disk copy.
    static func removeLogs(for serviceID: UUID, fileManager: FileManager = .default) {
        let root = rootDirectory(fileManager: fileManager)
        removeSafely(directory(for: serviceID, fileManager: fileManager), within: root, fileManager: fileManager)
    }

    /// Removes every runtime log directory.
    ///
    /// Called on startup so output from crashed or quit sessions cannot
    /// accumulate across runs.
    static func removeAll(fileManager: FileManager = .default) {
        let root = rootDirectory(fileManager: fileManager)
        removeSafely(root, within: root, fileManager: fileManager)
    }

    /// Removes a scoped log root.
    ///
    /// Exists so cleanup can be exercised against a test-owned temporary
    /// directory instead of the shared store root.
    static func removeContents(of url: URL, fileManager: FileManager = .default) {
        removeSafely(url, within: url, fileManager: fileManager)
    }

    /// Deletes a path only when it lies inside `root`.
    ///
    /// Guards against a swapped symlink or a caller-supplied path escaping the
    /// temporary store and removing unrelated files.
    private static func removeSafely(_ url: URL, within root: URL, fileManager: FileManager) {
        let rootPath = root.standardizedFileURL.path
        let target = url.standardizedFileURL
        guard target.path == rootPath || target.path.hasPrefix(rootPath + "/") else { return }
        guard fileManager.fileExists(atPath: target.path) else { return }
        try? fileManager.removeItem(at: target)
    }
}
