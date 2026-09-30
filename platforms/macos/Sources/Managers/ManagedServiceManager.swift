/**
 * ManagedServiceManager.swift
 * PortKiller
 *
 * Owns managed service profiles, their in-memory runtime state and the
 * lifecycle state machine described in the design notes (section 7).
 *
 * The manager is deliberately UI-free: views observe it, but every
 * transition also happens through the app-level wrappers when the UI is
 * closed, and all state is main-actor isolated.
 */

import Foundation

// MARK: - Tunnel coordination

/// Coarse resource a managed service can attach to (Quick Tunnel today).
@MainActor
protocol ManagedServiceTunnelCoordinating: AnyObject {
    /// Stops any tunnel that was serving the given local port.
    func stopTunnel(for port: Int)
}

// MARK: - Manager

/// Manages saved local services and their owned runtimes.
@Observable
@MainActor
final class ManagedServiceManager {
    /// All known services, in user-defined order.
    private(set) var services: [ManagedServiceState] = []

    /// Currently selected service profile, if any.
    var selectedServiceID: UUID?

    private let storage: ManagedServiceStorageProtocol
    private let scanner: PortScannerProtocol
    private let processes: ManagedServiceProcessControlling
    private let directoryValidator: WorkingDirectoryValidating

    private let readinessTimeout: Duration
    private let readinessPollInterval: Duration
    private let stopTimeout: Duration
    private let stopPollInterval: Duration

    /// Optional tunnel owner; weak to avoid a retain cycle with AppState.
    weak var tunnelCoordinator: (any ManagedServiceTunnelCoordinating)?

    @ObservationIgnored private var exitTasks: [UUID: Task<Void, Never>] = [:]

    init(
        storage: ManagedServiceStorageProtocol = DefaultsManagedServiceStorage(),
        scanner: PortScannerProtocol,
        processes: ManagedServiceProcessControlling = ManagedServiceProcessController(),
        directoryValidator: WorkingDirectoryValidating = FileSystemWorkingDirectoryValidator(),
        readinessTimeout: Duration = .seconds(20),
        readinessPollInterval: Duration = .milliseconds(250),
        stopTimeout: Duration = .seconds(5),
        stopPollInterval: Duration = .milliseconds(200)
    ) {
        self.storage = storage
        self.scanner = scanner
        self.processes = processes
        self.directoryValidator = directoryValidator
        self.readinessTimeout = readinessTimeout
        self.readinessPollInterval = readinessPollInterval
        self.stopTimeout = stopTimeout
        self.stopPollInterval = stopPollInterval
    }

    // MARK: - Profiles

    /// Persisted configurations, in display order.
    var configs: [ManagedServiceConfig] { services.map(\.config) }

    /// Number of services this session currently owns and runs.
    var runningCount: Int { services.filter { $0.status == .running }.count }

    /// Look up a service by identifier.
    func service(id: UUID) -> ManagedServiceState? {
        services.first { $0.id == id }
    }

    /// Loads persisted profiles; runtime state always starts empty.
    func load() {
        services = storage.load().map { ManagedServiceState(config: $0) }
        if let selected = selectedServiceID, services.contains(where: { $0.id == selected }) {
            return
        }
        selectedServiceID = services.first?.id
    }

    /// Adds a validated profile. Returns the validation failure, if any.
    @discardableResult
    func add(_ config: ManagedServiceConfig) -> ManagedServiceValidationError? {
        if let error = ManagedServiceValidator.validate(
            config,
            existing: configs,
            directoryValidator: directoryValidator
        ) {
            return error
        }
        let state = ManagedServiceState(config: config)
        services.append(state)
        selectedServiceID = state.id
        persist()
        return nil
    }

    /// Updates a profile that is not currently owned by a live runtime.
    @discardableResult
    func update(_ config: ManagedServiceConfig) -> ManagedServiceValidationError? {
        guard let state = service(id: config.id) else { return nil }
        guard state.status == .stopped || state.status == .failed || state.status == .conflict else {
            return .serviceRunning
        }
        if let error = ManagedServiceValidator.validate(
            config,
            existing: configs,
            directoryValidator: directoryValidator
        ) {
            return error
        }
        state.config = config
        state.status = .stopped
        state.lastError = nil
        state.clearRuntime()
        persist()
        return nil
    }

    /// Stops the service if owned, then removes the profile.
    ///
    /// A conflict-only service is removed without killing anything: the
    /// occupying process was never ours (design notes, section 13).
    func remove(id: UUID) async {
        guard service(id: id) != nil else { return }
        await stop(id: id)
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        services.remove(at: index)
        exitTasks[id]?.cancel()
        exitTasks[id] = nil
        persist()
        if selectedServiceID == id {
            selectedServiceID = services.first?.id
        }
    }

    // MARK: - Lifecycle

    /// Starts a service following the design notes' start algorithm.
    func start(id: UUID) async {
        guard let state = service(id: id) else { return }
        guard state.status == .stopped || state.status == .failed || state.status == .conflict else {
            return
        }

        if let error = ManagedServiceValidator.validate(
            state.config,
            existing: configs,
            directoryValidator: directoryValidator
        ) {
            state.status = .failed
            state.lastError = error.localizedDescription
            return
        }

        state.status = .starting
        state.lastError = nil
        state.conflict = nil
        state.recentOutput.removeAll()
        state.listenerPIDs = []

        // Preflight: never kill implicitly.
        let occupants = await listeners(for: state.port)
        guard state.status == .starting else { return }
        if !occupants.isEmpty {
            state.status = .conflict
            state.conflict = makeConflict(for: state, listeners: occupants)
            return
        }

        let command = ManagedServiceCommandRenderer.render(state.config.startCommand, port: state.port)
        let directory = state.config.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)

        let result = await processes.launch(
            serviceID: state.id,
            command: command,
            workingDirectory: directory,
            onOutput: { [weak state] entry in
                Task { @MainActor in
                    state?.appendOutput(entry.text, stream: entry.stream)
                }
            }
        )
        guard state.status == .starting else { return }

        switch result {
        case .failed(let message):
            state.status = .failed
            state.lastError = message
            state.clearRuntime()
            return
        case .launched(let handle):
            state.rootPID = handle.rootPID
        }

        let deadline = ContinuousClock.now + readinessTimeout
        while ContinuousClock.now < deadline {
            let stillRunning = await processes.isRunning(state.id)
            guard state.status == .starting else { return }

            if !stillRunning {
                let code = await processes.waitForExit(state.id)
                guard state.status == .starting else { return }
                state.clearRuntime()
                state.status = .failed
                state.lastExitCode = code
                state.lastError = L("service.error.exitedBeforeReady", state.port)
                return
            }

            let currentListeners = await listeners(for: state.port)
            guard state.status == .starting else { return }
            if !currentListeners.isEmpty {
                state.status = .running
                state.startedAt = Date()
                state.listenerPIDs = uniqueOccupants(from: currentListeners).map(\.pid)
                startExitWatcher(for: state)
                return
            }

            try? await Task.sleep(for: readinessPollInterval)
        }

        guard state.status == .starting else { return }
        _ = await processes.terminate(state.id)
        state.status = .failed
        let timeoutSeconds = Int(readinessTimeout.components.seconds)
        state.lastError = L("service.error.startupTimeout", state.port, timeoutSeconds)
        state.clearRuntime()
    }

    /// Stops an owned service without ever killing by port.
    func stop(id: UUID) async {
        guard let state = service(id: id), state.status == .running || state.status == .starting else {
            return
        }
        state.status = .stopping
        exitTasks[id]?.cancel()
        exitTasks[id] = nil
        tunnelCoordinator?.stopTunnel(for: state.port)

        let exitCode = await processes.terminate(id)
        guard state.status == .stopping else { return }
        state.lastExitCode = exitCode

        let freed = await waitForPortToFree(state.port)
        guard state.status == .stopping else { return }

        if freed {
            state.status = .stopped
            state.lastError = nil
            state.clearRuntime()
            return
        }

        let remaining = await listeners(for: state.port)
        guard state.status == .stopping else { return }
        if remaining.isEmpty {
            state.status = .stopped
            state.lastError = nil
            state.clearRuntime()
        } else {
            state.status = .conflict
            state.conflict = makeConflict(for: state, listeners: remaining)
            state.lastError = L("service.error.portStillOccupied", state.port)
            state.rootPID = nil
            state.listenerPIDs = uniqueOccupants(from: remaining).map(\.pid)
        }
    }

    /// Restarts a running service: stop, require stopped, then start.
    func restart(id: UUID) async {
        guard let state = service(id: id), state.status == .running else { return }
        await stop(id: id)
        guard state.status == .stopped else { return }
        await start(id: id)
    }

    /// Explicitly terminates the occupants of a conflicting port, then starts.
    func resolveConflictAndStart(id: UUID) async {
        guard let state = service(id: id),
              state.status == .conflict,
              let conflict = state.conflict else { return }

        state.status = .starting
        state.lastError = nil

        for occupant in conflict.occupants {
            _ = await scanner.killProcessGracefully(pid: occupant.pid)
        }

        var remaining = await listeners(for: state.port)
        if !remaining.isEmpty {
            for listener in remaining {
                _ = await scanner.killProcess(pid: listener.pid, force: true)
            }
            try? await Task.sleep(for: .milliseconds(300))
            remaining = await listeners(for: state.port)
        }

        guard remaining.isEmpty else {
            state.status = .conflict
            state.conflict = makeConflict(for: state, listeners: remaining)
            state.lastError = L("service.error.conflictStillOccupied", state.port)
            return
        }

        state.conflict = nil
        state.status = .stopped
        await start(id: id)
    }

    /// Clears a detected conflict without killing anything (user cancelled).
    func dismissConflict(id: UUID) {
        guard let state = service(id: id), state.status == .conflict else { return }
        state.status = .stopped
        state.conflict = nil
    }

    /// Clears captured output for a service.
    func clearOutput(id: UUID) {
        service(id: id)?.recentOutput.removeAll()
    }

    /// Terminates every runtime this session owns (app termination).
    func stopAll() async {
        for state in services {
            exitTasks[state.id]?.cancel()
            exitTasks[state.id] = nil
        }
        await processes.terminateAll()
        for state in services {
            state.status = .stopped
            state.lastError = nil
            state.clearRuntime()
        }
        persist()
    }

    // MARK: - Reconciliation

    /// Reconciles transient state with the latest scan.
    ///
    /// This is what makes a relaunch safe: a persisted profile that finds its
    /// port occupied becomes a conflict, never a silently owned runtime.
    func reconcile(with ports: [PortInfo]) {
        for state in services {
            switch state.status {
            case .starting, .stopping:
                continue

            case .running:
                let current = ports.filter { $0.port == state.port }
                let pids = uniqueOccupants(from: current).map(\.pid)
                if state.listenerPIDs != pids {
                    state.listenerPIDs = pids
                }

            case .stopped, .failed, .conflict:
                let occupants = uniqueOccupants(from: ports.filter { $0.port == state.port })
                if occupants.isEmpty {
                    if state.status == .conflict {
                        state.status = .stopped
                        state.conflict = nil
                        state.lastError = nil
                    }
                } else {
                    if state.conflict?.occupants != occupants {
                        state.conflict = ManagedServiceConflict(
                            serviceID: state.id,
                            port: state.port,
                            occupants: occupants
                        )
                    }
                    if state.status != .conflict {
                        state.status = .conflict
                        state.rootPID = nil
                        state.listenerPIDs = occupants.map(\.pid)
                        state.lastError = nil
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func persist() {
        storage.save(configs)
    }

    private func listeners(for port: Int) async -> [PortInfo] {
        await scanner.scanPorts().filter { $0.port == port }
    }

    private func uniqueOccupants(from listeners: [PortInfo]) -> [ManagedServiceOccupant] {
        var seen = Set<Int>()
        var occupants: [ManagedServiceOccupant] = []
        for listener in listeners where !seen.contains(listener.pid) {
            seen.insert(listener.pid)
            occupants.append(
                ManagedServiceOccupant(
                    pid: listener.pid,
                    processName: listener.processName,
                    command: listener.command,
                    user: listener.user,
                    address: listener.address
                )
            )
        }
        return occupants
    }

    private func makeConflict(for state: ManagedServiceState, listeners: [PortInfo]) -> ManagedServiceConflict {
        ManagedServiceConflict(
            serviceID: state.id,
            port: state.port,
            occupants: uniqueOccupants(from: listeners)
        )
    }

    private func waitForPortToFree(_ port: Int) async -> Bool {
        let deadline = ContinuousClock.now + stopTimeout
        while ContinuousClock.now < deadline {
            if await listeners(for: port).isEmpty { return true }
            try? await Task.sleep(for: stopPollInterval)
        }
        return await listeners(for: port).isEmpty
    }

    private func startExitWatcher(for state: ManagedServiceState) {
        exitTasks[state.id]?.cancel()
        exitTasks[state.id] = Task { [weak self] in
            guard let self else { return }
            let code = await self.processes.waitForExit(state.id)
            guard !Task.isCancelled else { return }
            self.handleUnexpectedExit(serviceID: state.id, exitCode: code)
        }
    }

    private func handleUnexpectedExit(serviceID: UUID, exitCode: Int32?) {
        exitTasks[serviceID] = nil
        guard let state = service(id: serviceID), state.status == .running else { return }
        state.clearRuntime()
        state.status = .failed
        state.lastExitCode = exitCode
        state.lastError = L("service.error.exitedUnexpectedly", Int(exitCode ?? -1))
    }
}
