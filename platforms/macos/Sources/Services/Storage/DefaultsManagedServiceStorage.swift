/**
 * DefaultsManagedServiceStorage.swift
 * PortKiller
 *
 * UserDefaults-backed storage for managed local service profiles.
 */

import Foundation
import Defaults

/// Default implementation of ManagedServiceStorageProtocol using UserDefaults.
struct DefaultsManagedServiceStorage: ManagedServiceStorageProtocol {
    func load() -> [ManagedServiceConfig] {
        Defaults[.managedServices]
    }

    func save(_ services: [ManagedServiceConfig]) {
        Defaults[.managedServices] = services
    }
}
