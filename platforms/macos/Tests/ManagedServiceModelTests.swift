import Foundation
import Testing
@testable import PortKiller

/**
 * Pure model, validation and command-rendering tests for managed services.
 *
 * These cover the "Pure model/renderer" portion of the Service Manager test
 * plan (design notes, section 22) and never touch the process layer.
 */
struct ManagedServiceModelTests {

    // MARK: - Fixtures

    private struct FakeDirectoryValidator: WorkingDirectoryValidating {
        let existing: Set<String>

        func isExistingDirectory(at path: String) -> Bool {
            existing.contains(path)
        }
    }

    private let validDirectory = "/tmp/portkiller-service-test"
    private var validator: FakeDirectoryValidator {
        FakeDirectoryValidator(existing: [validDirectory])
    }

    private func config(
        id: UUID = UUID(),
        name: String = "Test Service",
        port: Int = 38902,
        host: String = "localhost",
        workingDirectory: String? = nil,
        startCommand: String = "python3 -m http.server {port}"
    ) -> ManagedServiceConfig {
        ManagedServiceConfig(
            id: id,
            name: name,
            port: port,
            host: host,
            workingDirectory: workingDirectory ?? validDirectory,
            startCommand: startCommand
        )
    }

    // MARK: - Valid profile

    @Test func validProfilePassesValidation() {
        #expect(ManagedServiceValidator.validate(config(), existing: [], directoryValidator: validator) == nil)
    }

    @Test func configRoundTripsThroughCodable() throws {
        let original = config()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ManagedServiceConfig.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Name

    @Test func emptyNameIsRejected() {
        let candidate = config(name: "   ")
        #expect(ManagedServiceValidator.validate(candidate, existing: [], directoryValidator: validator) == .emptyName)
    }

    @Test func duplicateNameIsRejectedCaseInsensitively() {
        let existing = config(name: "Python Test Server")
        let candidate = config(name: "python test server")
        let error = ManagedServiceValidator.validate(candidate, existing: [existing], directoryValidator: validator)
        #expect(error == .duplicateName("python test server"))
    }

    @Test func editingSameProfileDoesNotCollideWithItself() {
        let id = UUID()
        let existing = ManagedServiceConfig(
            id: id,
            name: "Same",
            port: 4000,
            host: "localhost",
            workingDirectory: validDirectory,
            startCommand: "serve {port}"
        )
        let edited = ManagedServiceConfig(
            id: id,
            name: "Same",
            port: 4000,
            host: "localhost",
            workingDirectory: validDirectory,
            startCommand: "serve --port {port}"
        )
        #expect(ManagedServiceValidator.validate(edited, existing: [existing], directoryValidator: validator) == nil)
    }

    // MARK: - Port

    @Test(arguments: [0, -1, 65536, 99999])
    func portOutOfRangeIsRejected(_ port: Int) {
        let candidate = config(port: port)
        #expect(ManagedServiceValidator.validate(candidate, existing: [], directoryValidator: validator) == .portOutOfRange(port))
    }

    @Test(arguments: [1, 80, 65535])
    func portBoundsAreAccepted(_ port: Int) {
        let candidate = config(port: port)
        #expect(ManagedServiceValidator.validate(candidate, existing: [], directoryValidator: validator) == nil)
    }

    @Test func duplicateManagedPortIsRejected() {
        let existing = config(name: "First", port: 38902)
        let candidate = config(id: UUID(), name: "Second", port: 38902)
        let error = ManagedServiceValidator.validate(candidate, existing: [existing], directoryValidator: validator)
        #expect(error == .duplicatePort(38902))
    }

    // MARK: - Host, directory and command

    @Test func emptyHostIsRejected() {
        let candidate = config(host: "  ")
        #expect(ManagedServiceValidator.validate(candidate, existing: [], directoryValidator: validator) == .emptyHost)
    }

    @Test func missingWorkingDirectoryIsRejected() {
        let candidate = config(workingDirectory: "/definitely/not/here")
        let error = ManagedServiceValidator.validate(candidate, existing: [], directoryValidator: validator)
        #expect(error == .missingWorkingDirectory("/definitely/not/here"))
    }

    @Test func emptyCommandIsRejected() {
        let candidate = config(startCommand: "   ")
        #expect(ManagedServiceValidator.validate(candidate, existing: [], directoryValidator: validator) == .emptyCommand)
    }

    // MARK: - Placeholders

    @Test(arguments: ["{PORT}", "{host}", "{foo}", "{}"])
    func unknownPlaceholdersAreRejected(_ token: String) {
        let candidate = config(startCommand: "run --port {port} " + token)
        let error = ManagedServiceValidator.validate(candidate, existing: [], directoryValidator: validator)
        #expect(error == .unsupportedPlaceholder(token))
    }

    @Test func exactPortPlaceholderIsAccepted() {
        let candidate = config(startCommand: "python3 -m http.server {port}")
        #expect(ManagedServiceValidator.validate(candidate, existing: [], directoryValidator: validator) == nil)
    }

    @Test func renderReplacesEveryPortPlaceholder() {
        let rendered = ManagedServiceCommandRenderer.render("run {port} --alt {port}", port: 38902)
        #expect(rendered == "run 38902 --alt 38902")
    }

    @Test func renderLeavesCommandWithoutPlaceholderUnchanged() {
        let command = "npm run start"
        #expect(ManagedServiceCommandRenderer.render(command, port: 1234) == command)
    }

    @Test func validationRejectsCommandWithoutPlaceholderOnlyWhenOtherwiseInvalid() {
        // A command without the placeholder is valid; the port is simply not substituted.
        let candidate = config(startCommand: "npm run start")
        #expect(ManagedServiceValidator.validate(candidate, existing: [], directoryValidator: validator) == nil)
    }

    // MARK: - Host normalization and Open URL

    @Test(arguments: ["0.0.0.0", "*", "::", "[::]"])
    func wildcardHostNormalizesToLocalhost(_ host: String) {
        #expect(config(host: host).normalizedHost == "localhost")
    }

    @Test func openURLUsesNormalizedHostAndPort() {
        let candidate = config(port: 38902, host: "0.0.0.0")
        #expect(candidate.openURL?.absoluteString == "http://localhost:38902")
    }

    @Test func openURLBracketsIPv6Literals() {
        let candidate = config(port: 38902, host: "::1")
        #expect(candidate.openURL?.absoluteString == "http://[::1]:38902")
    }

    // MARK: - Runtime state

    @Test @MainActor func outputBufferStaysBounded() {
        let state = ManagedServiceState(config: config())
        for index in 0..<(ManagedServiceState.maxOutputLines + 50) {
            state.appendOutput("line \(index)", stream: .standardOutput)
        }
        #expect(state.recentOutput.count == ManagedServiceState.maxOutputLines)
        #expect(state.recentOutput.first?.text == "line 50")
        #expect(state.recentOutput.last?.text == "line \(ManagedServiceState.maxOutputLines + 49)")
    }

    @Test @MainActor func clearRuntimeDropsOwnership() {
        let state = ManagedServiceState(config: config())
        state.status = .running
        state.rootPID = 4242
        state.listenerPIDs = [4242]
        state.conflict = ManagedServiceConflict(serviceID: state.id, port: state.port, occupants: [])
        state.clearRuntime()
        #expect(state.rootPID == nil)
        #expect(state.listenerPIDs.isEmpty)
        #expect(state.conflict == nil)
    }

    @Test @MainActor func statusHasLocalizationKey() {
        #expect(ManagedServiceStatus.running.localizationKey == "service.status.running")
        #expect(ManagedServiceStatus.allCases.count == 6)
    }
}
