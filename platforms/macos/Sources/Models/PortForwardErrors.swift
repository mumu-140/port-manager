import Foundation

// MARK: - Process Types

enum PortForwardProcessType: String, Sendable {
    case portForward = "kubectl"
    case proxy = "socat"
}

// MARK: - Errors

enum KubectlError: Error, LocalizedError, Sendable {
    case kubectlNotFound
    case executionFailed(String)
    case parsingFailed(String)
    case clusterNotConnected

    var errorDescription: String? {
        switch self {
        case .kubectlNotFound:
            return L("error.kubectl.notFound")
        case .executionFailed(let message):
            return L("error.kubectl.executionFailed", message)
        case .parsingFailed(let message):
            return L("error.kubectl.parsingFailed", message)
        case .clusterNotConnected:
            return L("error.kubectl.clusterNotConnected")
        }
    }
}

// MARK: - Callback Types

/// Callback for log output from port-forward processes
typealias LogHandler = @Sendable (String, PortForwardProcessType, Bool) -> Void

/// Callback for port conflict errors (address already in use)
typealias PortConflictHandler = @Sendable (Int) -> Void
