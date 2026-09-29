/**
 * Errors.swift
 * PortKiller
 *
 * Defines error types for the PortKiller application.
 * All errors conform to LocalizedError to provide user-friendly messages.
 */

import Foundation

/// Application-specific error types
///
/// PortKillerError defines all possible error conditions that can occur
/// during port scanning, process killing, and permission checks. Each error
/// provides localized, user-friendly descriptions suitable for display in alerts.
enum PortKillerError: Error, LocalizedError {
    /// Port scanning operation failed
    case scanFailed(String)

    /// Failed to kill a process
    case killFailed(pid: Int, reason: String)

    /// Required system permission is denied
    case permissionDenied

    /// Network or system operation error
    case networkError(String)

    /// User-friendly error description
    var errorDescription: String? {
        switch self {
        case .scanFailed(let reason):
            return L("error.scanFailed", reason)
        case .killFailed(let pid, let reason):
            return L("error.killFailed", pid, reason)
        case .permissionDenied:
            return L("error.permissionDenied")
        case .networkError(let reason):
            return L("error.networkError", reason)
        }
    }

    /// Detailed failure reason
    var failureReason: String? {
        switch self {
        case .scanFailed:
            return L("error.scanFailed.reason")
        case .killFailed:
            return L("error.killFailed.reason")
        case .permissionDenied:
            return L("error.permissionDenied.reason")
        case .networkError:
            return L("error.networkError.reason")
        }
    }

    /// Suggested recovery action
    var recoverySuggestion: String? {
        switch self {
        case .scanFailed:
            return L("error.scanFailed.recovery")
        case .killFailed:
            return L("error.killFailed.recovery", pid)
        case .permissionDenied:
            return L("error.permissionDenied.recovery")
        case .networkError:
            return L("error.networkError.recovery")
        }
    }

    /// PID involved in the error (if applicable)
    private var pid: Int {
        switch self {
        case .killFailed(let pid, _):
            return pid
        default:
            return 0
        }
    }
}
