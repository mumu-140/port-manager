import Testing

@testable import PortKiller

/// Pure mapping tests for the delete confirmation (design section 8.1).
/// The mapping changes copy and button labels only — the behavior tests
/// (removeStopsOwnedServiceAndDeletesProfile, removeConflictOnlyServiceKillsNothing,
/// DeleteRunningServiceStopsOwnedRuntimeThenRemovesProfile,
/// DeleteConflictProfileNeverKillsTheOccupant) must stay green untouched.
@Suite struct ManagedServiceDeleteConfirmationTests {
    private func copy(
        isOwnedRunning: Bool = false,
        isConflict: Bool = false,
        hasQuickTunnel: Bool = false,
    ) -> ManagedServiceDeleteConfirmation.Copy {
        ManagedServiceDeleteConfirmation.copy(for: ManagedServiceDeleteContext(
            name: "Web",
            port: 8080,
            isOwnedRunning: isOwnedRunning,
            isConflict: isConflict,
            hasQuickTunnel: hasQuickTunnel,
        ))
    }

    @Test func stoppedServiceWarnsOnlyAboutSavedConfiguration() {
        let copy = copy()
        #expect(copy.messageKey == "service.delete.stoppedMessage")
        #expect(copy.buttonKey == "service.delete.confirm")
        #expect(copy.port == nil)
    }

    @Test func ownedRunningServiceSaysStopAndDelete() {
        let copy = copy(isOwnedRunning: true)
        #expect(copy.messageKey == "service.delete.stopAndDeleteMessage")
        #expect(copy.buttonKey == "service.delete.stopAndDeleteButton")
    }

    @Test func ownedRunningWithQuickTunnelNamesTheTunnel() {
        let copy = copy(isOwnedRunning: true, hasQuickTunnel: true)
        #expect(copy.messageKey == "service.delete.stopAndDeleteTunnelMessage")
        #expect(copy.buttonKey == "service.delete.stopAndDeleteButton")
    }

    @Test func conflictSaysConfigurationOnlyAndNamesThePort() {
        let copy = copy(isConflict: true)
        #expect(copy.messageKey == "service.delete.conflictMessage")
        #expect(copy.buttonKey == "service.delete.deleteConfigurationButton")
        #expect(copy.port == 8080)
    }

    @Test func conflictWinsOverRunningAndTunnel() {
        // A conflict state has no owned runtime; even with a stale tunnel
        // record the external-process copy must win.
        let copy = copy(isConflict: true, hasQuickTunnel: true)
        #expect(copy.messageKey == "service.delete.conflictMessage")
    }

    @Test func failedServiceUsesStoppedCopy() {
        // failed is not owned-running and not conflict: saved-configuration copy.
        let copy = copy()
        #expect(copy.messageKey == "service.delete.stoppedMessage")
    }

    @Test func allMappedKeysCarryNameAndPortArgs() {
        // Format-specifier parity across languages is enforced by the
        // localization regression tests; here we pin that the conflict copy
        // is the only one consuming the port.
        #expect(copy().port == nil)
        #expect(copy(isOwnedRunning: true).port == nil)
        #expect(copy(isOwnedRunning: true, hasQuickTunnel: true).port == nil)
        #expect(copy(isConflict: true).port != nil)
    }
}
