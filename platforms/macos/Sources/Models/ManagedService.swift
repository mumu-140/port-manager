/**
 * ManagedService.swift
 * PortKiller
 *
 * Persisted configuration and in-memory runtime state for user-defined local
 * services managed by Port Manager.
 *
 * The persisted profile contains user-authored configuration only. Runtime
 * state (PIDs, logs, tunnel URLs, process handles) is deliberately never
 * persisted so a relaunch can never silently re-attach to an existing
 * listener (design notes, section 6.5).
 */

import Foundation
import Defaults

// MARK: - Persisted configuration

/// A saved local service profile.
struct ManagedServiceConfig: Identifiable, Codable, Equatable, Hashable, Sendable, Defaults.Serializable {
    /// Stable identifier for the life of the profile.
    let id: UUID

    /// Human-readable name, unique case-insensitively among managed services.
    var name: String

    /// TCP port the service is expected to listen on.
    var port: Int

    /// Host used for the Open URL and for display only.
    var host: String

    /// Directory the start command runs in.
    var workingDirectory: String

    /// Foreground shell command launched for the service's lifetime.
    var startCommand: String

    init(
        id: UUID = UUID(),
        name: String = "",
        port: Int = 3000,
        host: String = "localhost",
        workingDirectory: String = "",
        startCommand: String = ""
    ) {
        self.id = id
        self.name = name
        self.port = port
        self.host = host
        self.workingDirectory = workingDirectory
        self.startCommand = startCommand
    }

    /// Host normalized for browser opening.
    ///
    /// Wildcard bind addresses normalize to localhost; everything else is
    /// passed through unchanged (design notes, section 5.3).
    var normalizedHost: String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "0.0.0.0", "*", "::", "[::]":
            return "localhost"
        default:
            return trimmed.isEmpty ? "localhost" : trimmed
        }
    }

    /// Browser URL built from the normalized host and configured port.
    var openURL: URL? {
        let normalized = normalizedHost
        let hostComponent: String
        if normalized.contains(":"), !normalized.hasPrefix("[") {
            hostComponent = "[\(normalized)]"
        } else {
            hostComponent = normalized
        }
        return URL(string: "http://\(hostComponent):\(port)")
    }
}

// MARK: - Status

/// Semantic lifecycle states shared by both platforms.
enum ManagedServiceStatus: String, Codable, Sendable, CaseIterable {
    case stopped
    case starting
    case running
    case stopping
    case conflict
    case failed

    /// Localization key for the human-readable status label.
    var localizationKey: String { "service.status.\(rawValue)" }
}

// MARK: - Output

/// One bounded, memory-only line of captured service output.
struct ManagedServiceLogEntry: Identifiable, Sendable, Equatable {
    /// Which output stream produced the line.
    enum Stream: Sendable, Equatable {
        case standardOutput
        case standardError
    }

    let id: UUID
    let timestamp: Date
    let stream: Stream
    let text: String

    init(id: UUID = UUID(), timestamp: Date = Date(), stream: Stream, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.stream = stream
        self.text = text
    }
}

// MARK: - Conflict details

/// A process currently holding a service's configured port.
struct ManagedServiceOccupant: Identifiable, Sendable, Equatable {
    let pid: Int
    let processName: String
    let command: String
    let user: String
    let address: String

    var id: Int { pid }
}

/// Structured result of a preflight conflict detection.
struct ManagedServiceConflict: Identifiable, Sendable, Equatable {
    let id: UUID
    let serviceID: UUID
    let port: Int
    let occupants: [ManagedServiceOccupant]

    init(id: UUID = UUID(), serviceID: UUID, port: Int, occupants: [ManagedServiceOccupant]) {
        self.id = id
        self.serviceID = serviceID
        self.port = port
        self.occupants = occupants
    }
}

// MARK: - Runtime state

/// Observable in-memory runtime for one managed service profile.
@Observable
@MainActor
final class ManagedServiceState: Identifiable {
    /// Maximum number of retained output lines per service.
    static let maxOutputLines = 200

    /// Readiness poll interval used by the start algorithm.
    static let readinessPollInterval: Duration = .milliseconds(250)

    /// Maximum readiness wait used by the start algorithm.
    static let readinessTimeout: Duration = .seconds(20)

    /// Stable identity, mirroring the configuration identifier.
    ///
    /// Stored as a non-isolated constant so `Identifiable` can be satisfied
    /// from non-isolated contexts while the rest of the state stays main-actor
    /// isolated.
    nonisolated let id: UUID

    /// Persisted configuration. Mutating it is only allowed while stopped.
    var config: ManagedServiceConfig

    /// Current lifecycle state.
    var status: ManagedServiceStatus = .stopped

    /// Root process identifier while this session owns the service.
    var rootPID: Int?

    /// Listener process identifiers observed on the configured port.
    var listenerPIDs: [Int] = []

    /// When the current run reached running.
    var startedAt: Date?

    /// Exit code of the last terminated owned process, when known.
    var lastExitCode: Int32?

    /// Most recent structured failure, if any.
    var lastError: String?

    /// Bounded, memory-only captured output.
    var recentOutput: [ManagedServiceLogEntry] = []

    /// Conflict details while the status is conflict.
    var conflict: ManagedServiceConflict?

    var name: String { config.name }
    var port: Int { config.port }
    var host: String { config.host }

    init(config: ManagedServiceConfig) {
        self.id = config.id
        self.config = config
    }

    /// Whether a lifecycle mutation is currently in flight.
    var isTransitioning: Bool {
        status == .starting || status == .stopping
    }

    /// Whether this session currently owns a running runtime.
    var isOwned: Bool {
        status == .running && rootPID != nil
    }

    /// Appends captured output, trimming to the bounded window.
    func appendOutput(_ text: String, stream: ManagedServiceLogEntry.Stream) {
        let trimmed = text.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }
        for line in trimmed.split(separator: "\n", omittingEmptySubsequences: true) {
            recentOutput.append(
                ManagedServiceLogEntry(stream: stream, text: String(line))
            )
        }
        if recentOutput.count > Self.maxOutputLines {
            recentOutput.removeFirst(recentOutput.count - Self.maxOutputLines)
        }
    }

    /// Clears ownership and transient runtime fields.
    func clearRuntime() {
        rootPID = nil
        listenerPIDs = []
        startedAt = nil
        lastExitCode = nil
        conflict = nil
    }
}
