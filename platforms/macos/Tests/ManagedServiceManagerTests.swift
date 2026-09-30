import Foundation
import Testing
@testable import PortKiller

// MARK: - Test doubles

/// Shared fake world connecting the fake scanner and process controller so
/// the manager's state machine can be exercised without real processes.
actor FakeManagedServiceWorld {
    private(set) var liveListeners: [PortInfo] = []
    private var preflight: [PortInfo] = []
    private var consumedPreflight = false

    func setPreflight(_ listeners: [PortInfo]) { preflight = listeners }
    func addListener(_ listener: PortInfo) { liveListeners.append(listener) }
    func removeListeners(pid: Int) { liveListeners.removeAll { $0.pid == pid } }

    func scan() -> [PortInfo] {
        if !consumedPreflight {
            consumedPreflight = true
            return preflight
        }
        return liveListeners
    }
}

actor FakeManagedServicePortScanner: PortScannerProtocol {
    let world: FakeManagedServiceWorld
    private(set) var forcedKills: [Int] = []
    private(set) var gracefulKills: [Int] = []

    init(world: FakeManagedServiceWorld) { self.world = world }

    func scanPorts() async -> [PortInfo] { await world.scan() }

    func killProcess(pid: Int, force: Bool) async -> Bool {
        forcedKills.append(pid)
        await world.removeListeners(pid: pid)
        return true
    }

    func killProcessGracefully(pid: Int) async -> Bool {
        gracefulKills.append(pid)
        await world.removeListeners(pid: pid)
        return true
    }

    func findEstablishedPids(for port: Int) async -> Set<Int> { [] }
}

actor FakeManagedServiceProcessController: ManagedServiceProcessControlling {
    let world: FakeManagedServiceWorld
    private var portByService: [UUID: Int] = [:]
    private var pidByService: [UUID: Int] = [:]
    private var outcomes: [UUID: ManagedServiceLaunchResult] = [:]
    private var suppressListener = false
    private var exitOnLaunch: Int32?
    private var running: Set<UUID> = []
    private var exitCodes: [UUID: Int32] = [:]
    private var waiters: [UUID: [CheckedContinuation<Int32?, Never>]] = [:]

    private(set) var launchCount = 0
    private(set) var terminated: [UUID] = []
    private(set) var lastCommand: String?

    init(world: FakeManagedServiceWorld) { self.world = world }

    func configure(serviceID: UUID, port: Int, pid: Int = 4242, outcome: ManagedServiceLaunchResult? = nil) {
        portByService[serviceID] = port
        pidByService[serviceID] = pid
        if let outcome { outcomes[serviceID] = outcome }
    }

    func setSuppressListener(_ suppress: Bool) { suppressListener = suppress }
    func setExitOnLaunch(_ code: Int32?) { exitOnLaunch = code }
    func lastLaunchedCommand() -> String? { lastCommand }

    func exit(serviceID: UUID, code: Int32) async {
        running.remove(serviceID)
        exitCodes[serviceID] = code
        if let pid = pidByService[serviceID] {
            await world.removeListeners(pid: pid)
        }
        resumeWaiters(serviceID, code: code)
    }

    func launch(
        serviceID: UUID,
        command: String,
        workingDirectory: String,
        onOutput: @escaping @Sendable (ManagedServiceLogEntry) -> Void
    ) async -> ManagedServiceLaunchResult {
        launchCount += 1
        lastCommand = command
        if let outcome = outcomes[serviceID] {
            return outcome
        }
        let pid = pidByService[serviceID] ?? 4242
        let port = portByService[serviceID] ?? 0
        running.insert(serviceID)
        if !suppressListener {
            await world.addListener(
                PortInfo(
                    port: port,
                    pid: pid,
                    processName: "python3",
                    address: "*:\(port)",
                    user: "tester",
                    command: command,
                    fd: "3u",
                    isActive: true,
                    processType: .webServer
                )
            )
        }
        if let code = exitOnLaunch {
            exitCodes[serviceID] = code
            running.remove(serviceID)
            await world.removeListeners(pid: pid)
            resumeWaiters(serviceID, code: code)
        }
        return .launched(ManagedServiceRuntimeHandle(serviceID: serviceID, rootPID: pid))
    }

    func isRunning(_ serviceID: UUID) async -> Bool { running.contains(serviceID) }

    func rootPID(_ serviceID: UUID) async -> Int? {
        running.contains(serviceID) ? pidByService[serviceID] : nil
    }

    func waitForExit(_ serviceID: UUID) async -> Int32? {
        if let code = exitCodes[serviceID] { return code }
        return await withCheckedContinuation { continuation in
            waiters[serviceID, default: []].append(continuation)
        }
    }

    func terminate(_ serviceID: UUID) async -> Int32? {
        terminated.append(serviceID)
        running.remove(serviceID)
        if let pid = pidByService[serviceID] {
            await world.removeListeners(pid: pid)
        }
        let code = exitCodes[serviceID] ?? 0
        exitCodes[serviceID] = code
        resumeWaiters(serviceID, code: code)
        return code
    }

    func terminateAll() async {
        for serviceID in Array(running) {
            _ = await terminate(serviceID)
        }
    }

    private func resumeWaiters(_ serviceID: UUID, code: Int32) {
        let continuations = waiters.removeValue(forKey: serviceID) ?? []
        for continuation in continuations {
            continuation.resume(returning: code)
        }
    }
}

final class InMemoryManagedServiceStorage: ManagedServiceStorageProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ManagedServiceConfig]

    init(_ initial: [ManagedServiceConfig] = []) { stored = initial }

    func load() -> [ManagedServiceConfig] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func save(_ services: [ManagedServiceConfig]) {
        lock.lock()
        defer { lock.unlock() }
        stored = services
    }
}

private struct FakeDirectoryValidator: WorkingDirectoryValidating {
    let existing: Set<String>
    func isExistingDirectory(at path: String) -> Bool { existing.contains(path) }
}

// MARK: - Tests

/**
 * State-machine tests for ManagedServiceManager driven by scripted fakes.
 *
 * Covers the start/stop/restart/conflict/relaunch portions of the Service
 * Manager test plan (design notes, section 22) without real processes.
 */
@MainActor
struct ManagedServiceManagerTests {

    private let directory = "/tmp/portkiller-manager-test"
    private let serviceID = UUID()

    private func makeConfig(
        id: UUID? = nil,
        name: String = "Python Test Server",
        port: Int = 38902
    ) -> ManagedServiceConfig {
        ManagedServiceConfig(
            id: id ?? serviceID,
            name: name,
            port: port,
            host: "localhost",
            workingDirectory: directory,
            startCommand: "python3 -m http.server {port}"
        )
    }

    private func makeSUT(
        storage: InMemoryManagedServiceStorage = InMemoryManagedServiceStorage()
    ) async -> (
        manager: ManagedServiceManager,
        world: FakeManagedServiceWorld,
        scanner: FakeManagedServicePortScanner,
        processes: FakeManagedServiceProcessController,
        storage: InMemoryManagedServiceStorage
    ) {
        let world = FakeManagedServiceWorld()
        let scanner = FakeManagedServicePortScanner(world: world)
        let processes = FakeManagedServiceProcessController(world: world)
        let manager = ManagedServiceManager(
            storage: storage,
            scanner: scanner,
            processes: processes,
            directoryValidator: FakeDirectoryValidator(existing: [directory]),
            readinessTimeout: .milliseconds(80),
            readinessPollInterval: .milliseconds(5),
            stopTimeout: .milliseconds(60),
            stopPollInterval: .milliseconds(5)
        )
        return (manager, world, scanner, processes, storage)
    }

    private func occupant(port: Int = 38902, pid: Int = 9999) -> PortInfo {
        PortInfo(
            port: port,
            pid: pid,
            processName: "nginx",
            address: "*:\(port)",
            user: "root",
            command: "nginx -g daemon off;",
            fd: "6u",
            isActive: true,
            processType: .webServer
        )
    }

    // MARK: Start

    @Test func startWithFreePortReachesRunning() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)

        await sut.manager.start(id: serviceID)

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .running)
        #expect(state?.rootPID == 4242)
        #expect(state?.listenerPIDs == [4242])
        let launches = await sut.processes.launchCount
        #expect(launches == 1)
    }

    @Test func startRendersPortPlaceholder() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig(port: 40001)) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 40001)

        await sut.manager.start(id: serviceID)

        let command = await sut.processes.lastLaunchedCommand()
        #expect(command == "python3 -m http.server 40001")
    }

    @Test func startWithOccupiedPortReportsConflictWithoutLaunching() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.world.setPreflight([occupant()])

        await sut.manager.start(id: serviceID)

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .conflict)
        #expect(state?.conflict?.occupants.first?.pid == 9999)
        let launches = await sut.processes.launchCount
        #expect(launches == 0)
    }

    @Test func launchFailureMarksFailed() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(
            serviceID: serviceID,
            port: 38902,
            outcome: .failed("launch exploded")
        )

        await sut.manager.start(id: serviceID)

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .failed)
        #expect(state?.lastError == "launch exploded")
    }

    @Test func startupTimeoutTerminatesAndFails() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.processes.setSuppressListener(true)

        await sut.manager.start(id: serviceID)

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .failed)
        #expect(state?.lastError != nil)
        let terminated = await sut.processes.terminated
        #expect(terminated.contains(serviceID))
    }

    @Test func exitBeforeReadyMarksFailed() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.processes.setExitOnLaunch(3)

        await sut.manager.start(id: serviceID)

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .failed)
        #expect(state?.lastExitCode == 3)
    }

    // MARK: Conflict resolution

    @Test func resolveConflictKillsOccupantThenStarts() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        let occupantInfo = occupant()
        await sut.world.setPreflight([occupantInfo])
        await sut.world.addListener(occupantInfo)
        await sut.processes.configure(serviceID: serviceID, port: 38902)

        await sut.manager.start(id: serviceID)
        #expect(sut.manager.service(id: serviceID)?.status == .conflict)

        await sut.manager.resolveConflictAndStart(id: serviceID)

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .running)
        let graceful = await sut.scanner.gracefulKills
        #expect(graceful == [9999])
        let forced = await sut.scanner.forcedKills
        #expect(forced.isEmpty)
    }

    // MARK: Stop and restart

    @Test func stopRunningServiceNeverKillsByPort() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)

        await sut.manager.stop(id: serviceID)

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .stopped)
        #expect(state?.rootPID == nil)
        let terminated = await sut.processes.terminated
        #expect(terminated == [serviceID])
        let forced = await sut.scanner.forcedKills
        let graceful = await sut.scanner.gracefulKills
        #expect(forced.isEmpty)
        #expect(graceful.isEmpty)
    }

    @Test func stopWithUnownedListenerReportsConflict() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)
        // An unrelated process now also holds the port.
        await sut.world.addListener(occupant(pid: 7777))

        await sut.manager.stop(id: serviceID)

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .conflict)
        #expect(state?.conflict?.occupants.first?.pid == 7777)
    }

    @Test func restartStopsThenStartsExactlyOnce() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)

        await sut.manager.restart(id: serviceID)

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .running)
        let launches = await sut.processes.launchCount
        #expect(launches == 2)
        let terminated = await sut.processes.terminated
        #expect(terminated.count == 1)
    }

    // MARK: Persistence and removal

    @Test func profilesPersistAndReloadAsStopped() async {
        let storage = InMemoryManagedServiceStorage()
        let sut = await makeSUT(storage: storage)
        #expect(sut.manager.add(makeConfig()) == nil)

        let reloaded = ManagedServiceManager(
            storage: storage,
            scanner: sut.scanner,
            processes: sut.processes,
            directoryValidator: FakeDirectoryValidator(existing: [directory])
        )
        reloaded.load()

        #expect(reloaded.services.count == 1)
        #expect(reloaded.services.first?.status == .stopped)
        #expect(reloaded.services.first?.name == "Python Test Server")
    }

    @Test func duplicateProfileIsRejectedAndNotPersisted() async {
        let storage = InMemoryManagedServiceStorage()
        let sut = await makeSUT(storage: storage)
        #expect(sut.manager.add(makeConfig()) == nil)

        let duplicate = ManagedServiceConfig(
            name: "python test server",
            port: 40000,
            host: "localhost",
            workingDirectory: directory,
            startCommand: "serve"
        )
        let error = sut.manager.add(duplicate)

        #expect(error == .duplicateName("python test server"))
        #expect(sut.manager.services.count == 1)
        #expect(storage.load().count == 1)
    }

    @Test func removeStopsOwnedServiceAndDeletesProfile() async {
        let storage = InMemoryManagedServiceStorage()
        let sut = await makeSUT(storage: storage)
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)

        await sut.manager.remove(id: serviceID)

        #expect(sut.manager.services.isEmpty)
        #expect(storage.load().isEmpty)
        let terminated = await sut.processes.terminated
        #expect(terminated == [serviceID])
    }

    @Test func removeConflictOnlyServiceKillsNothing() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.world.setPreflight([occupant()])
        await sut.manager.start(id: serviceID)
        #expect(sut.manager.service(id: serviceID)?.status == .conflict)

        await sut.manager.remove(id: serviceID)

        #expect(sut.manager.services.isEmpty)
        let forced = await sut.scanner.forcedKills
        let graceful = await sut.scanner.gracefulKills
        #expect(forced.isEmpty)
        #expect(graceful.isEmpty)
    }

    // MARK: Reconciliation

    @Test func reconcileMarksRelaunchConflictAndClearsIt() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)

        sut.manager.reconcile(with: [occupant()])
        #expect(sut.manager.service(id: serviceID)?.status == .conflict)
        #expect(sut.manager.service(id: serviceID)?.rootPID == nil)

        sut.manager.reconcile(with: [])
        #expect(sut.manager.service(id: serviceID)?.status == .stopped)
        #expect(sut.manager.service(id: serviceID)?.conflict == nil)
    }

    // MARK: Unexpected exit

    @Test func unexpectedExitMarksFailed() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)
        #expect(sut.manager.service(id: serviceID)?.status == .running)

        await sut.processes.exit(serviceID: serviceID, code: 9)
        try? await Task.sleep(for: .milliseconds(60))

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .failed)
        #expect(state?.lastExitCode == 9)
        #expect(state?.rootPID == nil)
    }
}
