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

    private var replacementAfterRemoval: [Int: PortInfo] = [:]

    func setPreflight(_ listeners: [PortInfo]) { preflight = listeners }
    func addListener(_ listener: PortInfo) { liveListeners.append(listener) }

    /// Installs a process that grabs the port the moment `pid` releases it,
    /// modelling the TOCTOU window between confirmation and force-kill.
    func setReplacement(afterRemoving pid: Int, with listener: PortInfo) {
        replacementAfterRemoval[pid] = listener
    }

    func removeListeners(pid: Int) {
        liveListeners.removeAll { $0.pid == pid }
        if let replacement = replacementAfterRemoval.removeValue(forKey: pid) {
            liveListeners.append(replacement)
        }
    }

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
    /// PIDs that ignore SIGTERM, so the force fallback path is exercised.
    private var stubbornPIDs: Set<Int> = []

    init(world: FakeManagedServiceWorld) { self.world = world }

    func setStubborn(_ pids: Set<Int>) { stubbornPIDs = pids }

    func scanPorts() async -> [PortInfo] { await world.scan() }

    func killProcess(pid: Int, force: Bool) async -> Bool {
        forcedKills.append(pid)
        await world.removeListeners(pid: pid)
        return true
    }

    func killProcessGracefully(pid: Int) async -> Bool {
        gracefulKills.append(pid)
        if !stubbornPIDs.contains(pid) {
            await world.removeListeners(pid: pid)
        }
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

    func ownedPIDs(_ serviceID: UUID) async -> Set<Int> {
        guard running.contains(serviceID), let pid = pidByService[serviceID] else { return [] }
        return [pid]
    }

    /// Drops the tracked runtime without resuming waiters, modelling a root
    /// process that vanished before the exit watcher observed it.
    func forget(serviceID: UUID) {
        running.remove(serviceID)
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

    @Test func editorPortInspectionFindsExternalOccupant() async {
        let sut = await makeSUT()
        await sut.world.setPreflight([occupant(pid: 7777)])

        let listeners = await sut.manager.inspectPortForEditor(38902, editingID: nil)

        #expect(listeners.count == 1)
        #expect(listeners.first?.pid == 7777)
    }

    @Test func editorPortInspectionFiltersOwnedListenerButKeepsExternalOccupant() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)
        #expect(sut.manager.service(id: serviceID)?.listenerPIDs == [4242])

        var listeners = await sut.manager.inspectPortForEditor(38902, editingID: serviceID)
        #expect(listeners.isEmpty)

        await sut.world.addListener(occupant(pid: 7777))
        listeners = await sut.manager.inspectPortForEditor(38902, editingID: serviceID)

        #expect(listeners.count == 1)
        #expect(listeners.first?.pid == 7777)
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

        await sut.manager.reconcile(with: [occupant()])
        #expect(sut.manager.service(id: serviceID)?.status == .conflict)
        #expect(sut.manager.service(id: serviceID)?.rootPID == nil)

        await sut.manager.reconcile(with: [])
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

    // MARK: Ownership reconciliation

    @Test func reconcileKeepsRunningWhileOwnedListenerPresent() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)

        await sut.manager.reconcile(with: [occupant(pid: 4242)])

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .running)
        #expect(state?.listenerPIDs == [4242])
    }

    @Test func reconcileRunningBecomesConflictWhenListenerIsUnowned() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)
        // The replacement occupant is a real, unrelated listener.
        await sut.world.addListener(occupant(pid: 7777))

        await sut.manager.reconcile(with: [occupant(pid: 7777)])

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .conflict)
        #expect(state?.rootPID == nil)
        #expect(state?.conflict?.occupants.first?.pid == 7777)

        // The owned runtime is terminated before the unowned conflict is
        // reported, so no live runtime stays owned under this identifier.
        let owned = await sut.processes.ownedPIDs(serviceID)
        #expect(owned.isEmpty)
        let terminated = await sut.processes.terminated
        #expect(terminated == [serviceID])

        // The external occupant is untouched and no scanner kill is issued.
        let live = await sut.world.liveListeners
        #expect(live.contains { $0.pid == 7777 })
        let graceful = await sut.scanner.gracefulKills
        let forced = await sut.scanner.forcedKills
        #expect(graceful.isEmpty)
        #expect(forced.isEmpty)
    }

    @Test func reconcileRunningFailsWhenPortStopsListening() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)

        await sut.manager.reconcile(with: [])

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .failed)
        #expect(state?.rootPID == nil)
        #expect(state?.lastError == L("service.error.readinessLost", 38902))

        // The still-live owned runtime is terminated, never abandoned.
        let owned = await sut.processes.ownedPIDs(serviceID)
        #expect(owned.isEmpty)
        let terminated = await sut.processes.terminated
        #expect(terminated == [serviceID])

        // Cleanup never falls back to killing by port.
        let graceful = await sut.scanner.gracefulKills
        let forced = await sut.scanner.forcedKills
        #expect(graceful.isEmpty)
        #expect(forced.isEmpty)
    }

    /// A readiness-loss failure must leave no owned runtime behind, otherwise
    /// the retrying Start could overwrite the controller's entry for this
    /// service identifier and orphan the previous process.
    @Test func retryingStartAfterReadinessLossCannotLeaveOlderOwnedRuntime() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902, pid: 4242)
        await sut.manager.start(id: serviceID)
        #expect(sut.manager.service(id: serviceID)?.status == .running)

        await sut.manager.reconcile(with: [])
        #expect(sut.manager.service(id: serviceID)?.status == .failed)
        let abandoned = await sut.processes.ownedPIDs(serviceID)
        #expect(abandoned.isEmpty)

        // Retry with a fresh runtime identity: the old one must be gone, so
        // the new launch replaces nothing.
        await sut.processes.configure(serviceID: serviceID, port: 38902, pid: 5151)
        await sut.manager.start(id: serviceID)

        let retried = sut.manager.service(id: serviceID)
        #expect(retried?.status == .running)
        #expect(retried?.rootPID == 5151)
        #expect(retried?.listenerPIDs == [5151])
        let launches = await sut.processes.launchCount
        #expect(launches == 2)
        let terminated = await sut.processes.terminated
        #expect(terminated == [serviceID])
    }

    @Test func reconcileRunningFailsWhenOwnedRuntimeExited() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)
        await sut.processes.forget(serviceID: serviceID)

        await sut.manager.reconcile(with: [occupant(pid: 4242)])

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .failed)
        #expect(state?.lastError == L("service.error.ownedRuntimeLost"))
    }

    @Test func reconcileConflictStaysUntilPortIsFree() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.world.setPreflight([occupant()])
        await sut.manager.start(id: serviceID)
        #expect(sut.manager.service(id: serviceID)?.status == .conflict)

        await sut.manager.reconcile(with: [occupant()])
        #expect(sut.manager.service(id: serviceID)?.status == .conflict)

        await sut.manager.reconcile(with: [])
        #expect(sut.manager.service(id: serviceID)?.status == .stopped)
    }

    @Test func relaunchLoadedProfileIsNeverOwned() async {
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

        await reloaded.reconcile(with: [occupant(pid: 31337)])

        let state = reloaded.services.first
        #expect(state?.status == .conflict)
        #expect(state?.isOwned == false)
        #expect(state?.rootPID == nil)
    }

    // MARK: Conflict TOCTOU safety

    @Test func resolveConflictNeverKillsUnconfirmedReplacement() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        let confirmed = occupant(pid: 9999)
        await sut.world.setPreflight([confirmed])
        await sut.world.addListener(confirmed)
        await sut.world.setReplacement(afterRemoving: 9999, with: occupant(pid: 1234))

        await sut.manager.start(id: serviceID)
        #expect(sut.manager.service(id: serviceID)?.status == .conflict)

        await sut.manager.resolveConflictAndStart(id: serviceID)

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .conflict)
        #expect(state?.conflict?.occupants.first?.pid == 1234)
        let forced = await sut.scanner.forcedKills
        let graceful = await sut.scanner.gracefulKills
        #expect(forced.isEmpty)
        #expect(graceful == [9999])
    }

    @Test func resolveConflictForceKillsOnlyConfirmedSurvivors() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        let confirmed = occupant(pid: 9999)
        await sut.world.setPreflight([confirmed])
        await sut.world.addListener(confirmed)
        await sut.scanner.setStubborn([9999])
        await sut.processes.configure(serviceID: serviceID, port: 38902)

        await sut.manager.start(id: serviceID)
        await sut.manager.resolveConflictAndStart(id: serviceID)

        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .running)
        let forced = await sut.scanner.forcedKills
        #expect(forced == [9999])
    }

    // MARK: Edit preparation

    @Test func stopForEditingStopsOwnedRuntime() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)

        let ready = await sut.manager.stopForEditing(id: serviceID)

        #expect(ready)
        let state = sut.manager.service(id: serviceID)
        #expect(state?.status == .stopped)
        #expect(state?.rootPID == nil)
    }

    @Test func stopForEditingReportsFalseWhenPortLandsInConflict() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)
        await sut.processes.configure(serviceID: serviceID, port: 38902)
        await sut.manager.start(id: serviceID)
        await sut.world.addListener(occupant(pid: 5555))

        let ready = await sut.manager.stopForEditing(id: serviceID)

        #expect(ready == false)
        #expect(sut.manager.service(id: serviceID)?.status == .conflict)
    }

    @Test func stopForEditingIsTrueForAlreadyStoppedService() async {
        let sut = await makeSUT()
        #expect(sut.manager.add(makeConfig()) == nil)

        let ready = await sut.manager.stopForEditing(id: serviceID)

        #expect(ready)
    }

    // MARK: Localization

    @Test func deleteConfirmationsIncludeServiceName() {
        let name = "Python Test Server"

        // Semantic delete copy (design section 8.1): every message carries the name.
        #expect(L("service.delete.stoppedMessage", name).contains(name))
        #expect(L("service.delete.stopAndDeleteMessage", name).contains(name))
        #expect(L("service.delete.stopAndDeleteTunnelMessage", name).contains(name))
        #expect(L("service.delete.conflictMessage", name, 8080).contains(name))
    }
}

