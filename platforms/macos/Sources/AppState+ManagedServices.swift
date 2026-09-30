/**
 * AppState+ManagedServices.swift
 * PortKiller
 *
 * Thin app-level wrappers that connect the managed service manager to the
 * wider app: refreshes after lifecycle changes and Quick Tunnel teardown.
 */

import Foundation

extension AppState {
    /// Starts a managed service and refreshes the port list afterwards.
    func startManagedService(id: UUID) async {
        await managedServiceManager.start(id: id)
        await refresh()
    }

    /// Stops a managed service and refreshes the port list afterwards.
    func stopManagedService(id: UUID) async {
        await managedServiceManager.stop(id: id)
        await refresh()
    }

    /// Restarts a managed service and refreshes the port list afterwards.
    func restartManagedService(id: UUID) async {
        await managedServiceManager.restart(id: id)
        await refresh()
    }

    /// Kills the occupants of a conflicting port with explicit consent, then starts.
    func resolveManagedServiceConflict(id: UUID) async {
        await managedServiceManager.resolveConflictAndStart(id: id)
        await refresh()
    }

    /// Deletes a managed service profile (stopping it first when owned).
    func deleteManagedService(id: UUID) async {
        await managedServiceManager.remove(id: id)
        await refresh()
    }

    /// Adds a managed service profile and refreshes the port list.
    @discardableResult
    func addManagedService(_ config: ManagedServiceConfig) async -> ManagedServiceValidationError? {
        let error = managedServiceManager.add(config)
        await refresh()
        return error
    }

    /// Updates a managed service profile and reconciles against its new port.
    @discardableResult
    func updateManagedService(_ config: ManagedServiceConfig) async -> ManagedServiceValidationError? {
        let error = managedServiceManager.update(config)
        await refresh()
        return error
    }

    /// Stops an owned runtime so its profile can be edited.
    ///
    /// Returns true only once the runtime reached the stopped state, so the
    /// caller opens the editor only after a verified stop (design notes, 12.2).
    func prepareManagedServiceForEditing(id: UUID) async -> Bool {
        let ready = await managedServiceManager.stopForEditing(id: id)
        await refresh()
        return ready
    }
}

extension TunnelManager: ManagedServiceTunnelCoordinating {}
