/**
 * ManagedServiceProcessController.swift
 * PortKiller
 *
 * Actor-based launcher and terminator for managed service runtimes.
 *
 * A managed service is long-lived, so it cannot use the run-to-completion
 * ProcessExecutor. This actor preserves the same safety invariants instead:
 * output pipes are always drained asynchronously, no thread is ever blocked
 * on waitUntilExit, and termination always acts on the tracked process tree
 * rather than on whatever currently holds the port.
 */

import Foundation
import Darwin

// MARK: - Handles and results

/// Handle identifying a launched managed service runtime.
struct ManagedServiceRuntimeHandle: Sendable, Equatable {
    let serviceID: UUID
    let rootPID: Int
}

/// Outcome of a launch attempt.
enum ManagedServiceLaunchResult: Sendable, Equatable {
    case launched(ManagedServiceRuntimeHandle)
    case failed(String)
}

// MARK: - Protocol

/// Launches, observes and terminates managed service process trees.
protocol ManagedServiceProcessControlling: Sendable {
    /// Launches a rendered command in the given working directory.
    func launch(
        serviceID: UUID,
        command: String,
        workingDirectory: String,
        onOutput: @escaping @Sendable (ManagedServiceLogEntry) -> Void
    ) async -> ManagedServiceLaunchResult

    /// Whether the tracked root process is still alive.
    func isRunning(_ serviceID: UUID) async -> Bool

    /// Root PID of the tracked runtime, if any.
    func rootPID(_ serviceID: UUID) async -> Int?

    /// Suspends until the tracked root process exits, returning its code.
    func waitForExit(_ serviceID: UUID) async -> Int32?

    /// Terminates the owned process tree, returning the exit code if known.
    func terminate(_ serviceID: UUID) async -> Int32?

    /// PIDs currently owned by this service's runtime (root and descendants).
    ///
    /// Returns an empty set when no live runtime is tracked. Reconciliation
    /// uses this to distinguish an owned listener from an unrelated process
    /// that merely occupies the configured port (design notes, section 6.4).
    func ownedPIDs(_ serviceID: UUID) async -> Set<Int>
}

// MARK: - Process tree

/// Pure process tree helpers shared by the controller and its tests.
enum ManagedServiceProcessTree {
    /// Parses ps -axo pid=,ppid= output into a child to parent map.
    static func parentMap(fromPSOutput output: String) -> [Int: Int] {
        var map: [Int: Int] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, let pid = Int(parts[0]), let ppid = Int(parts[1]) else { continue }
            map[pid] = ppid
        }
        return map
    }

    /// Returns every descendant PID of the root, nearest-first.
    static func descendants(of rootPID: Int, inPSOutput output: String) -> [Int] {
        let parents = parentMap(fromPSOutput: output)
        var childrenByParent: [Int: [Int]] = [:]
        for (pid, parent) in parents {
            childrenByParent[parent, default: []].append(pid)
        }
        var result: [Int] = []
        var queue = childrenByParent[rootPID] ?? []
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard !result.contains(next) else { continue }
            result.append(next)
            queue.append(contentsOf: childrenByParent[next] ?? [])
        }
        return result
    }
}

// MARK: - Controller

/// Owns the actual child processes for managed services.
actor ManagedServiceProcessController: ManagedServiceProcessControlling {
    private struct Runtime {
        let process: Process
        let rootPID: Int
        var exitCode: Int32?
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        let stdoutTail: Task<Void, Never>
        let stderrTail: Task<Void, Never>
    }

    private var runtimes: [UUID: Runtime] = [:]
    private var exitContinuations: [UUID: [CheckedContinuation<Int32?, Never>]] = [:]

    // MARK: Launch

    func launch(
        serviceID: UUID,
        command: String,
        workingDirectory: String,
        onOutput: @escaping @Sendable (ManagedServiceLogEntry) -> Void
    ) async -> ManagedServiceLaunchResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        var environment = ProcessInfo.processInfo.environment
        environment["PORT_MANAGER_SERVICE_ID"] = serviceID.uuidString
        process.environment = environment

        // Runtime output goes to files, never to a parent-owned pipe: a
        // managed child is allowed to outlive Port Manager, and a pipe write
        // after the app exits would kill it with SIGPIPE (design notes, 6.5).
        do {
            try ManagedServiceRuntimeLogStore.prepare(for: serviceID)
        } catch {
            return .failed(L("service.error.launchFailed", error.localizedDescription))
        }

        let stdoutURL = ManagedServiceRuntimeLogStore.stdoutURL(for: serviceID)
        let stderrURL = ManagedServiceRuntimeLogStore.stderrURL(for: serviceID)
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        do {
            stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            stderrHandle = try FileHandle(forWritingTo: stderrURL)
        } catch {
            ManagedServiceRuntimeLogStore.removeLogs(for: serviceID)
            return .failed(L("service.error.launchFailed", error.localizedDescription))
        }

        // Detach stdin as well: nothing about the child should depend on the
        // app's terminal or pipe lifetime.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { await self?.handleExit(serviceID: serviceID, code: code) }
        }

        do {
            try process.run()
        } catch {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            process.terminationHandler = nil
            ManagedServiceRuntimeLogStore.removeLogs(for: serviceID)
            return .failed(L("service.error.launchFailed", error.localizedDescription))
        }

        let rootPID = Int(process.processIdentifier)
        runtimes[serviceID] = Runtime(
            process: process,
            rootPID: rootPID,
            exitCode: nil,
            stdoutHandle: stdoutHandle,
            stderrHandle: stderrHandle,
            stdoutTail: makeTailTask(url: stdoutURL, stream: .standardOutput, onOutput: onOutput),
            stderrTail: makeTailTask(url: stderrURL, stream: .standardError, onOutput: onOutput)
        )
        return .launched(ManagedServiceRuntimeHandle(serviceID: serviceID, rootPID: rootPID))
    }

    // MARK: Observation

    func isRunning(_ serviceID: UUID) async -> Bool {
        runtimes[serviceID]?.process.isRunning ?? false
    }

    func rootPID(_ serviceID: UUID) async -> Int? {
        runtimes[serviceID]?.rootPID
    }

    func waitForExit(_ serviceID: UUID) async -> Int32? {
        if let runtime = runtimes[serviceID], let exitCode = runtime.exitCode {
            return exitCode
        }
        return await withCheckedContinuation { continuation in
            exitContinuations[serviceID, default: []].append(continuation)
        }
    }

    // MARK: Termination

    func terminate(_ serviceID: UUID) async -> Int32? {
        guard let runtime = runtimes[serviceID] else { return nil }

        if runtime.process.isRunning {
            let descendants = await descendants(of: runtime.rootPID)
            _ = Darwin.kill(Int32(runtime.rootPID), SIGTERM)
            for pid in descendants.reversed() {
                _ = Darwin.kill(Int32(pid), SIGTERM)
            }

            let deadline = ContinuousClock.now + .seconds(3)
            while runtime.process.isRunning, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }

            if runtime.process.isRunning {
                for pid in descendants.reversed() {
                    _ = Darwin.kill(Int32(pid), SIGKILL)
                }
                _ = Darwin.kill(Int32(runtime.rootPID), SIGKILL)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        let exitCode: Int32? = runtime.process.isRunning ? nil : runtime.process.terminationStatus
        cleanup(serviceID)
        return exitCode
    }

    func ownedPIDs(_ serviceID: UUID) async -> Set<Int> {
        guard let runtime = runtimes[serviceID], runtime.process.isRunning else { return [] }
        var pids: Set<Int> = [runtime.rootPID]
        pids.formUnion(await descendants(of: runtime.rootPID))
        return pids
    }

    // MARK: Internals

    private func handleExit(serviceID: UUID, code: Int32) {
        if var runtime = runtimes[serviceID] {
            runtime.exitCode = code
            runtime.stdoutTail.cancel()
            runtime.stderrTail.cancel()
            runtimes[serviceID] = runtime
        }
        let continuations = exitContinuations.removeValue(forKey: serviceID) ?? []
        for continuation in continuations {
            continuation.resume(returning: code)
        }
    }

    private func cleanup(_ serviceID: UUID) {
        guard let runtime = runtimes[serviceID] else { return }
        runtime.stdoutTail.cancel()
        runtime.stderrTail.cancel()
        try? runtime.stdoutHandle.close()
        try? runtime.stderrHandle.close()
        runtime.process.terminationHandler = nil
        runtimes[serviceID] = nil
    }

    /// Polls an append-only runtime log and forwards complete lines.
    ///
    /// Runs independently of the app's lifetime: it only reads the file, so a
    /// child keeps writing whether or not the tail is alive.
    private nonisolated func makeTailTask(
        url: URL,
        stream: ManagedServiceLogEntry.Stream,
        onOutput: @escaping @Sendable (ManagedServiceLogEntry) -> Void
    ) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            var offset: UInt64 = 0
            var pending = Data()

            func emit(_ lineData: Data) {
                var bytes = lineData
                if bytes.last == 0x0D { bytes.removeLast() }
                guard !bytes.isEmpty else { return }
                onOutput(ManagedServiceLogEntry(
                    stream: stream,
                    text: String(decoding: bytes, as: UTF8.self)
                ))
            }

            func emitCompleteLines() {
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = pending[pending.startIndex..<newline]
                    pending.removeSubrange(pending.startIndex...newline)
                    emit(line)
                }
            }

            while !Task.isCancelled {
                let read = managedServiceReadAppendedBytes(url: url, offset: offset)
                guard !read.data.isEmpty else {
                    try? await Task.sleep(for: .milliseconds(150))
                    continue
                }
                offset = read.offset
                pending.append(read.data)
                emitCompleteLines()
            }

            // Final drain so output written without a trailing newline is not
            // lost when the runtime is torn down.
            let finalRead = managedServiceReadAppendedBytes(url: url, offset: offset)
            if !finalRead.data.isEmpty { pending.append(finalRead.data) }
            emitCompleteLines()
            if !pending.isEmpty { emit(pending) }
        }
    }

    private func descendants(of rootPID: Int) async -> [Int] {
        guard let output = await ProcessExecutor.output("/bin/ps", arguments: ["-axo", "pid=,ppid="]) else {
            return []
        }
        return ManagedServiceProcessTree.descendants(of: rootPID, inPSOutput: output)
    }
}

/// Reads the bytes appended to a file since `offset`.
///
/// File scope so the tail loop never needs actor isolation; the function only
/// touches the file and its own arguments.
private func managedServiceReadAppendedBytes(url: URL, offset: UInt64) -> (data: Data, offset: UInt64) {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return (Data(), offset) }
    defer { try? handle.close() }
    do {
        try handle.seek(toOffset: offset)
    } catch {
        return (Data(), offset)
    }
    let data = ((try? handle.readToEnd()) ?? nil) ?? Data()
    return (data, offset + UInt64(data.count))
}
