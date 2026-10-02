import Foundation
import Observation
import Testing

@testable import PortKiller

/**
 * Observation regression tests for the preset form (review fix, 2026-10-02).
 *
 * The form's preset state (presetID, fieldValues) drives form switching,
 * field rendering, warnings, invalidPresetField and Save enabled state, so
 * mutations MUST be observable. These tests use withObservationTracking to
 * prove each mutation fires, including switching to SSH Local Forward — the
 * one preset with no suggested port whose selection previously changed only
 * ignored state.
 */
@Suite struct ManagedServiceEditorObservationTests {

    /// Records whether the handler runs for a mutation of the tracked
    /// properties, using the public Observation API.
    private func mutationIsObserved(_ mutate: () -> Void) -> Bool {
        final class Box: @unchecked Sendable {
            var fired = false
        }
        let box = Box()
        withObservationTracking {
            // Track every property the form reads for rendering.
            _ = ManagedServicePresets.all
        } onChange: {
            box.fired = true
        }
        mutate()
        return box.fired
    }

    private func observeProperty(_ read: () -> Void, mutate: () -> Void) -> Bool {
        final class Box: @unchecked Sendable {
            var fired = false
        }
        let box = Box()
        withObservationTracking {
            read()
        } onChange: {
            box.fired = true
        }
        mutate()
        return box.fired
    }

    @Test func changingPresetIDIsObservable() {
        let model = ManagedServiceEditorViewModel()
        model.beginAdd()
        let fired = observeProperty(
            { _ = model.presetID },
            mutate: { model.beginPreset(ManagedServicePresets.preset(withID: "ssh-local-forward")!) }
        )
        #expect(fired, "beginPreset(ssh-local-forward) must be observable")
    }

    /// Switching Custom -> SSH Local specifically: no suggested port, so
    /// selection previously changed only ignored state.
    @Test func switchingCustomToSSHLocalIsObservable() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "static-file-share")!)
        let fired = observeProperty(
            { _ = model.presetID },
            mutate: { model.selectPreset(ManagedServicePresets.preset(withID: "ssh-local-forward")!) }
        )
        #expect(fired, "Custom -> SSH Local must be observable")
        #expect(model.presetID == "ssh-local-forward")
        #expect(model.fieldValues["sshHost"] == "")
        // No suggested port: the previously chosen port stays.
        #expect(model.portText == "8123")
    }

    @Test func mutatingFieldValueIsObservable() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "ssh-local-forward")!)
        let fired = observeProperty(
            { _ = model.fieldValues },
            mutate: { model.fieldValues["remotePort"] = "5432" }
        )
        #expect(fired, "field value edits must be observable")
    }

    /// Live validation can update after a field edit: the invalid-field
    /// caption reads fieldValues, so an edit that fixes a violation must
    /// clear it for observers.
    @Test func invalidPresetFieldUpdatesAfterFieldEdit() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "ssh-local-forward")!)
        model.fieldValues["remotePort"] = "5432"
        #expect(model.invalidPresetField?.field.id == "sshHost")
        #expect(model.invalidPresetField?.error == .empty)

        let fired = observeProperty(
            { _ = model.invalidPresetField },
            mutate: { model.fieldValues["sshHost"] = "web.example.com" }
        )
        #expect(fired, "fixing a violation must be observable")
        #expect(model.invalidPresetField == nil)
    }

    /// Field edits keep updating live validation in both directions.
    @Test func liveValidationUpdatesBothDirections() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "ssh-local-forward")!)
        model.fieldValues["sshHost"] = "web.example.com"
        model.fieldValues["remotePort"] = "5432"
        #expect(model.invalidPresetField == nil)

        model.fieldValues["remotePort"] = "not-a-port"
        #expect(model.invalidPresetField?.field.id == "remotePort")
        model.fieldValues["remotePort"] = "5432"
        #expect(model.invalidPresetField == nil)
    }
}
