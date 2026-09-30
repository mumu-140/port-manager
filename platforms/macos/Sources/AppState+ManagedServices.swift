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

    /// Stops every owned managed service runtime (app termination).
    func stopAllManagedServices() async {
        await managedServiceManager.stopAll()
    }
}

extension TunnelManager: ManagedServiceTunnelCoordinating {}
