/**
 * ManagedServiceRuntimeLogTests.swift
 * PortKiller
 *
 * Integration coverage for the app-quit survival guarantee: a managed child
 * writes stdout/stderr to runtime files, not to parent-owned pipes, so it can
 * keep running after Port Manager exits.
 */

import Foundation
import Testing
@testable import PortKiller

/// Collects output delivered by the controller's tail tasks.
private actor ManagedServiceOutputCollector {
    private(set) var entries: [ManagedServiceLogEntry] = []

    func append(_ entry: ManagedServiceLogEntry) { entries.append(entry) }

    func text(for stream: ManagedServiceLogEntry.Stream) -> String {
        entries.filter { $0.stream == stream }.map(\.text).joined(separator: "\n")
    }
}

private func makeTestDirectory(_ label: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("portkiller-tests-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeTestScript(_ body: String, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent("service.py")
    try body.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(10),
    _ condition: @MainActor () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await condition()
}

private func processIsAlive(_ pid: Int) -> Bool {
    Darwin.kill(Int32(pid), 0) == 0
}

@MainActor
struct ManagedServiceRuntimeLogTests {

    // MARK: Store

    @Test func runtimeLogStorePreparesOwnerOnlyFiles() throws {
        let serviceID = UUID()
        defer { ManagedServiceRuntimeLogStore.removeLogs(for: serviceID) }

        let directory = try ManagedServiceRuntimeLogStore.prepare(for: serviceID)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect(directoryAttributes[.posixPermissions] as? Int == 0o700)

        for url in [ManagedServiceRuntimeLogStore.stdoutURL(for: serviceID),
                    ManagedServiceRuntimeLogStore.stderrURL(for: serviceID)] {
            #expect(FileManager.default.fileExists(atPath: url.path))
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect(attributes[.posixPermissions] as? Int == 0o600)
        }
    }

    @Test func runtimeLogStorePrepareTruncatesPreviousRun() throws {
        let serviceID = UUID()
        defer { ManagedServiceRuntimeLogStore.removeLogs(for: serviceID) }

        _ = try ManagedServiceRuntimeLogStore.prepare(for: serviceID)
        let stdout = ManagedServiceRuntimeLogStore.stdoutURL(for: serviceID)
        try Data("stale output".utf8).write(to: stdout)

        _ = try ManagedServiceRuntimeLogStore.prepare(for: serviceID)

        let contents = try Data(contentsOf: stdout)
        #expect(contents.isEmpty)
    }

    @Test func runtimeLogStoreRemoveLogsLeavesOtherServicesAlone() throws {
        let keep = UUID()
        let drop = UUID()
        _ = try ManagedServiceRuntimeLogStore.prepare(for: keep)
        _ = try ManagedServiceRuntimeLogStore.prepare(for: drop)
        defer {
            ManagedServiceRuntimeLogStore.removeLogs(for: keep)
            ManagedServiceRuntimeLogStore.removeLogs(for: drop)
        }

        ManagedServiceRuntimeLogStore.removeLogs(for: drop)

        #expect(!FileManager.default.fileExists(atPath: ManagedServiceRuntimeLogStore.directory(for: drop).path))
        #expect(FileManager.default.fileExists(atPath: ManagedServiceRuntimeLogStore.directory(for: keep).path))
    }

    /// Startup cleanup removes a whole log root. Exercised against a scoped
    /// temporary directory so it cannot disturb concurrently running tests.
    @Test func runtimeLogStoreRemoveContentsWipesScopedRoot() throws {
        let scoped = try makeTestDirectory("scoped-root")
        let nested = scoped.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        ManagedServiceRuntimeLogStore.removeContents(of: scoped)

        #expect(!FileManager.default.fileExists(atPath: scoped.path))
    }

    // MARK: Failure mode

    /// Proves why pipe redirection was unsafe and why files are robust:
    /// closing the reader kills a pipe-backed writer, while discarding the
    /// parent's handle leaves a file-backed writer untouched.
    @Test func fileBackedChildSurvivesReaderTeardownWhilePipeBackedChildDoesNot() async throws {
        let directory = try makeTestDirectory("survival-mechanism")
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try writeTestScript(
            "import time\nwhile True:\n    print('tick', flush=True)\n    time.sleep(0.05)\n",
            in: directory
        )

        // Pipe-backed control: once the read end closes the child dies.
        let pipe = Pipe()
        let pipeProcess = Process()
        pipeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        pipeProcess.arguments = ["python3", "-u", script.path]
        pipeProcess.standardOutput = pipe
        pipeProcess.standardError = pipe
        try pipeProcess.run()
        let pipePID = Int(pipeProcess.processIdentifier)
        pipe.fileHandleForReading.closeFile()
        try? await Task.sleep(for: .milliseconds(800))
        #expect(!processIsAlive(pipePID), "pipe-backed child must die once the reader closes")
        if processIsAlive(pipePID) { Darwin.kill(Int32(pipePID), SIGKILL) }

        // File-backed: the child owns its descriptor, so the app dropping its
        // handle (modelling app exit) cannot affect it.
        let logURL = directory.appendingPathComponent("out.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        let fileProcess = Process()
        fileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        fileProcess.arguments = ["python3", "-u", script.path]
        fileProcess.standardOutput = handle
        fileProcess.standardError = handle
        try fileProcess.run()
        let filePID = Int(fileProcess.processIdentifier)
        try handle.close()
        defer { if processIsAlive(filePID) { Darwin.kill(Int32(filePID), SIGTERM) } }

        try? await Task.sleep(for: .milliseconds(800))
        #expect(processIsAlive(filePID), "file-backed child must survive parent handle teardown")
        let size = (try FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
        #expect(size > 0, "the surviving child must still be writing")
    }

    // MARK: Controller

    @Test func realControllerCapturesContinuousOutputToRegularFiles() async throws {
        let directory = try makeTestDirectory("controller")
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try writeTestScript(
            "import sys, time\nfor i in range(100000):\n    print(f'out {i}', flush=True)\n    print(f'err {i}', file=sys.stderr, flush=True)\n    time.sleep(0.05)\n",
            in: directory
        )

        let serviceID = UUID()
        let controller = ManagedServiceProcessController()
        let collector = ManagedServiceOutputCollector()
        let result = await controller.launch(
            serviceID: serviceID,
            command: "/usr/bin/env python3 -u \(script.path)",
            workingDirectory: directory.path,
            onOutput: { entry in Task { await collector.append(entry) } }
        )

        guard case .launched(let handle) = result else {
            Issue.record("launch failed: \(result)")
            ManagedServiceRuntimeLogStore.removeLogs(for: serviceID)
            return
        }

        let sawBothStreams = await waitUntil {
            let stdout = await collector.text(for: .standardOutput)
            let stderr = await collector.text(for: .standardError)
            return stdout.contains("out 0") && stderr.contains("err 0")
        }
        #expect(sawBothStreams, "continuous stdout and stderr must be tailed")

        // The child's stdout/stderr must be regular files, not pipes: that is
        // exactly what makes it independent of this process.
        let descriptors = await ProcessExecutor.output(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-a", "-p", "\(handle.rootPID)", "-d", "1,2"]
        ) ?? ""
        #expect(descriptors.contains("REG"), "child stdio must be regular files, got: \(descriptors)")
        #expect(!descriptors.contains("PIPE"), "child stdio must not be pipes, got: \(descriptors)")

        // Output keeps flowing well past readiness.
        let firstCount = await collector.entries.count
        try? await Task.sleep(for: .milliseconds(400))
        let secondCount = await collector.entries.count
        #expect(secondCount > firstCount)

        _ = await controller.terminate(serviceID)
        ManagedServiceRuntimeLogStore.removeLogs(for: serviceID)
    }
}
