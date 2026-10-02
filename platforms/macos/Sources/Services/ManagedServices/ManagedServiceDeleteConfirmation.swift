import Foundation

/// Semantic inputs for the delete confirmation (design section 8.1).
///
/// Transitioning services never reach the dialog (Delete stays disabled as
/// today), so no transitioning case exists here.
struct ManagedServiceDeleteContext {
    var name: String
    var port: Int
    /// Owned runtime active right now (running && rootPID != nil).
    var isOwnedRunning: Bool
    /// Status == .conflict.
    var isConflict: Bool
    /// An owned Quick Tunnel is attached to this port right now.
    var hasQuickTunnel: Bool
}

/// Pure semantic mapping: delete state -> (message key + args, destructive
/// button key). The wording matches actual behavior exactly:
/// - Running (owned): the owned service IS stopped first (ManagedServiceManager.stop).
/// - Running + Quick Tunnel: the tunnel is stopped too (stop() calls
///   tunnelCoordinator.stopTunnel).
/// - Conflict: the external occupant is NEVER terminated (stop() ignores
///   conflict state; remove() only deletes the profile).
/// Behavior never changes here — copy and button labels only.
enum ManagedServiceDeleteConfirmation {
    struct Copy: Equatable {
        /// Localized message key; consumed via L(key, name[, port]).
        let messageKey: String
        let name: String
        /// Non-nil only for the conflict copy (%ld port specifier).
        let port: Int?
        /// Destructive button label key.
        let buttonKey: String
    }

    static func copy(for context: ManagedServiceDeleteContext) -> Copy {
        if context.isConflict {
            return Copy(
                messageKey: "service.delete.conflictMessage",
                name: context.name,
                port: context.port,
                buttonKey: "service.delete.deleteConfigurationButton",
            )
        }
        if context.isOwnedRunning {
            if context.hasQuickTunnel {
                return Copy(
                    messageKey: "service.delete.stopAndDeleteTunnelMessage",
                    name: context.name,
                    port: nil,
                    buttonKey: "service.delete.stopAndDeleteButton",
                )
            }
            return Copy(
                messageKey: "service.delete.stopAndDeleteMessage",
                name: context.name,
                port: nil,
                buttonKey: "service.delete.stopAndDeleteButton",
            )
        }
        return Copy(
            messageKey: "service.delete.stoppedMessage",
            name: context.name,
            port: nil,
            buttonKey: "service.delete.confirm",
        )
    }
}
