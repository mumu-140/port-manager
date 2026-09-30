import Foundation
import Testing
@testable import PortKiller

/// Stand-in directory validator so editor tests never touch the file system.
private struct StubDirectoryValidator: WorkingDirectoryValidating {
    let existing: Set<String>

    init(existing: Set<String> = []) {
        self.existing = existing
    }

    func isExistingDirectory(at path: String) -> Bool {
        existing.contains(path)
    }
}

/// Counting validator proving the working-directory stat is memoized.
private final class CountingDirectoryValidator: WorkingDirectoryValidating, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private let existing: Set<String>

    init(existing: Set<String> = []) {
        self.existing = existing
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    func isExistingDirectory(at path: String) -> Bool {
        lock.lock()
        callCount += 1
        lock.unlock()
        return existing.contains(path)
    }
}

private func makeConfig(
    id: UUID = UUID(),
    name: String = "Web",
    port: Int = 3000,
    host: String = "localhost",
    workingDirectory: String = "/tmp/web",
    startCommand: String = "npm run dev"
) -> ManagedServiceConfig {
    ManagedServiceConfig(
        id: id,
        name: name,
        port: port,
        host: host,
        workingDirectory: workingDirectory,
        startCommand: startCommand
    )
}

@Suite("Managed service editor view model")
struct ManagedServiceEditorViewModelTests {

    @Test("beginAdd clears every field")
    func beginAddClearsFields() {
        let model = ManagedServiceEditorViewModel()
        model.beginEdit(makeConfig())
        model.beginAdd()

        #expect(model.name.isEmpty)
        #expect(model.portText.isEmpty)
        #expect(model.workingDirectory.isEmpty)
        #expect(model.startCommand.isEmpty)
        #expect(model.isEditing == false)
        #expect(model.titleKey == "service.editor.addTitle")
    }

    @Test("beginEdit loads the config and switches the title")
    func beginEditLoadsConfig() {
        let config = makeConfig(port: 5173, host: "127.0.0.1", startCommand: "vite")
        let model = ManagedServiceEditorViewModel()
        model.beginEdit(config)

        #expect(model.isEditing)
        #expect(model.titleKey == "service.editor.editTitle")
        #expect(model.name == config.name)
        #expect(model.portText == "5173")
        #expect(model.host == "127.0.0.1")
        #expect(model.workingDirectory == config.workingDirectory)
        #expect(model.startCommand == "vite")
    }

    @Test("draftConfig trims whitespace and reuses the edited identifier")
    func draftConfigTrimsAndKeepsID() {
        let id = UUID()
        let model = ManagedServiceEditorViewModel()
        model.beginEdit(makeConfig(id: id))
        model.name = "  Web  "
        model.portText = " 4100 "
        model.host = " localhost "
        model.workingDirectory = " /tmp/web "
        model.startCommand = " npm run dev "

        let draft = model.draftConfig()

        #expect(draft.id == id)
        #expect(draft.name == "Web")
        #expect(draft.port == 4100)
        #expect(draft.host == "localhost")
        #expect(draft.workingDirectory == "/tmp/web")
        #expect(draft.startCommand == "npm run dev")
    }

    @Test("non-numeric port text falls back to zero and fails validation")
    func invalidPortFailsValidation() {
        let model = ManagedServiceEditorViewModel()
        model.beginAdd()
        model.name = "Web"
        model.workingDirectory = "/tmp/web"
        model.startCommand = "npm run dev"
        model.portText = "abc"

        #expect(model.parsedPort == 0)
        let error = model.validate(existing: [], directoryValidator: StubDirectoryValidator())
        #expect(error == .portOutOfRange(0))
        #expect(model.validationError == .portOutOfRange(0))
    }

    @Test("empty name is rejected before anything else")
    func emptyNameFailsValidation() {
        let model = ManagedServiceEditorViewModel()
        model.beginAdd()
        model.portText = "3000"
        model.workingDirectory = "/tmp/web"
        model.startCommand = "npm run dev"

        let error = model.validate(existing: [], directoryValidator: StubDirectoryValidator())
        #expect(error == .emptyName)
    }

    @Test("duplicate names and ports are rejected")
    func duplicatesFailValidation() {
        let existing = [makeConfig(name: "Web", port: 3000)]
        let validator = StubDirectoryValidator(existing: ["/tmp/web"])

        let nameModel = ManagedServiceEditorViewModel()
        nameModel.beginAdd()
        nameModel.name = "Web"
        nameModel.portText = "4100"
        nameModel.workingDirectory = "/tmp/web"
        nameModel.startCommand = "npm run dev"
        #expect(nameModel.validate(existing: existing, directoryValidator: validator) == .duplicateName("Web"))

        let portModel = ManagedServiceEditorViewModel()
        portModel.beginAdd()
        portModel.name = "Api"
        portModel.portText = "3000"
        portModel.workingDirectory = "/tmp/web"
        portModel.startCommand = "npm run dev"
        #expect(portModel.validate(existing: existing, directoryValidator: validator) == .duplicatePort(3000))
    }

    @Test("missing working directory is reported")
    func missingDirectoryFailsValidation() {
        let model = ManagedServiceEditorViewModel()
        model.beginAdd()
        model.name = "Web"
        model.portText = "3000"
        model.workingDirectory = "/tmp/does-not-exist"
        model.startCommand = "npm run dev"

        let error = model.validate(existing: [], directoryValidator: StubDirectoryValidator())
        #expect(error == .missingWorkingDirectory("/tmp/does-not-exist"))
    }

    @Test("valid input clears the validation error")
    func validInputPassesValidation() {
        let model = ManagedServiceEditorViewModel()
        model.beginAdd()
        model.name = "Web"
        model.portText = "3000"
        model.workingDirectory = "/tmp/web"
        model.startCommand = "npm run dev"

        let error = model.validate(
            existing: [],
            directoryValidator: StubDirectoryValidator(existing: ["/tmp/web"])
        )

        #expect(error == nil)
        #expect(model.validationError == nil)
        #expect(model.draftConfig().port == 3000)
    }

    @Test("live validation reports an invalid port before Save is clicked")
    func liveValidationRejectsInvalidPort() {
        let model = ManagedServiceEditorViewModel()
        model.beginAdd()
        model.name = "Web"
        model.portText = "70000"
        model.workingDirectory = "/tmp/web"
        model.startCommand = "npm run dev"

        let error = model.liveValidationError(
            existing: [],
            directoryValidator: StubDirectoryValidator(existing: ["/tmp/web"])
        )

        #expect(error == .portOutOfRange(70000))
    }

    @Test("live validation memoizes the working-directory check")
    func liveValidationMemoizesDirectoryCheck() {
        let validator = CountingDirectoryValidator(existing: ["/tmp/web"])
        let model = ManagedServiceEditorViewModel()
        model.beginAdd()
        model.name = "Web"
        model.portText = "3000"
        model.workingDirectory = "/tmp/web"
        model.startCommand = "npm run dev"

        _ = model.liveValidationError(existing: [], directoryValidator: validator)
        model.name = "Web 2"
        model.startCommand = "npm run start"
        let second = model.liveValidationError(existing: [], directoryValidator: validator)

        #expect(second == nil)
        #expect(validator.calls == 1)
    }

    @Test("live validation re-checks the directory when the path changes")
    func liveValidationRechecksChangedPath() {
        let validator = CountingDirectoryValidator(existing: ["/tmp/web"])
        let model = ManagedServiceEditorViewModel()
        model.beginAdd()
        model.name = "Web"
        model.portText = "3000"
        model.workingDirectory = "/tmp/web"
        model.startCommand = "npm run dev"

        _ = model.liveValidationError(existing: [], directoryValidator: validator)
        model.workingDirectory = "/tmp/missing"
        let error = model.liveValidationError(existing: [], directoryValidator: validator)

        #expect(error == .missingWorkingDirectory("/tmp/missing"))
        #expect(validator.calls == 2)
    }
}

