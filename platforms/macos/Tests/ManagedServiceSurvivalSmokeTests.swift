/**
 * ManagedServiceSurvivalSmokeTests.swift
 * PortKiller
 *
 * End-to-end app-quit survival smoke test. Skipped unless
 * `PORTKILLER_SURVIVAL_SMOKE` is set, because these tests deliberately leave
 * a real child process running so `scripts/smoke-service-survival.sh` can
 * prove it outlives this process.
 *
 * launch mode: start a real managed service through the production manager and
 *              then return; the test process exits, simulating quitting Port
 *              Manager without stopping the child.
 * relaunch mode: reload the profile in a fresh process, reconcile against a
 *              real port scan and require the survivor to appear as Conflict
 *              that this app does not own.
 */

import Foundation
import Testing
@testable import PortKiller

@MainActor
struct ManagedServiceSurvivalSmokeTests {
    private static let serviceID = UUID(uuidString: "A1B2C3D4-0000-4000-8000-000000000001")!

    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PORTKILLER_SURVIVAL_SMOKE"] == "launch"))
    func launchServiceThenLetThisProcessExit() async throws {
        let port = try #require(Int(environment["PORTKILLER_SURVIVAL_PORT"] ?? ""))
        let scriptPath = try #require(environment["PORTKILLER_SURVIVAL_SCRIPT"])
        let infoPath = try #require(environment["PORTKILLER_SURVIVAL_INFO"])
        let workingDirectory = URL(fileURLWithPath: scriptPath).deletingLastPathComponent().path

        let config = ManagedServiceConfig(
            id: Self.serviceID,
            name: "Survival Smoke",
            port: port,
            host: "localhost",
            workingDirectory: workingDirectory,
            startCommand: "/usr/bin/env python3 -u \(scriptPath) {port}"
        )

        let manager = ManagedServiceManager(
            storage: InMemoryManagedServiceStorage([config]),
            scanner: PortScanner(),
            processes: ManagedServiceProcessController(),
            directoryValidator: FileSystemWorkingDirectoryValidator(),
            readinessTimeout: .seconds(20),
            readinessPollInterval: .milliseconds(200)
        )
        manager.load()
        await manager.start(id: Self.serviceID)

        let state = manager.service(id: Self.serviceID)
        guard let state, state.status == .running, let pid = state.rootPID else {
            Issue.record(
                "service did not reach running (status=\(String(describing: state?.status)), error=\(state?.lastError ?? "nil"))"
            )
            return
        }

        let info = [
            "pid=\(pid)",
            "stdout=\(ManagedServiceRuntimeLogStore.stdoutURL(for: Self.serviceID).path)",
            "stderr=\(ManagedServiceRuntimeLogStore.stderrURL(for: Self.serviceID).path)",
        ].joined(separator: "\n")
        try info.write(toFile: infoPath, atomically: true, encoding: .utf8)
        print("SURVIVAL_LAUNCH pid=\(pid) port=\(port)")

        // Intentionally no stop: this process exiting is the simulated quit.
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PORTKILLER_SURVIVAL_SMOKE"] == "relaunch"))
    func relaunchDetectsSurvivingServiceAsConflict() async throws {
        let port = try #require(Int(environment["PORTKILLER_SURVIVAL_PORT"] ?? ""))
        let infoPath = try #require(environment["PORTKILLER_SURVIVAL_INFO"])
        let info = try String(contentsOfFile: infoPath, encoding: .utf8)
        let expectedPID = try #require(
            info.split(separator: "\n")
                .first { $0.hasPrefix("pid=") }
                .flatMap { Int($0.dropFirst(4)) }
        )

        let config = ManagedServiceConfig(
            id: Self.serviceID,
            name: "Survival Smoke",
            port: port,
            host: "localhost",
            workingDirectory: "/tmp",
            startCommand: "true"
        )

        let scanner = PortScanner()
        let manager = ManagedServiceManager(
            storage: InMemoryManagedServiceStorage([config]),
            scanner: scanner,
            processes: ManagedServiceProcessController(),
            directoryValidator: FileSystemWorkingDirectoryValidator()
        )
        manager.load()
        await manager.reconcile(with: await scanner.scanPorts())

        let state = try #require(manager.service(id: Self.serviceID))
        let occupantPIDs = state.conflict?.occupants.map(\.pid) ?? []
        print(
            "SURVIVAL_RELAUNCH status=\(String(describing: state.status)) owned=\(state.isOwned) occupants=\(occupantPIDs)"
        )
        #expect(state.status == .conflict)
        #expect(!state.isOwned)
        #expect(state.rootPID == nil)
        #expect(occupantPIDs.contains(expectedPID))
    }
}
