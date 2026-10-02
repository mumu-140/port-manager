/**
 * ManagedServicePresetCommandRenderer.swift
 * PortKiller
 *
 * Pure, table-free rendering helpers for preset start commands.
 *
 * Presets differ from the custom editor: the app composes the command from
 * user-controlled field values, so the app owns safe rendering. On macOS the
 * execution model is /bin/zsh -lc with the command string passed as a single
 * argv element, so POSIX single-quote escaping fully isolates every value
 * (verified empirically against the exact execution model during research,
 * 2026-10-01). Values whose charset forbids shell metacharacters are inserted
 * raw; everything else is single-quoted.
 *
 * The custom-command renderer (ManagedServiceCommandRenderer) is deliberately
 * untouched: custom service stays user-authored shell input.
 */

import Foundation

enum ManagedServicePresetCommandRenderer {
    /// Wraps a value in POSIX single quotes so it round-trips byte-identically
    /// through /bin/zsh: every interior quote becomes quote-backslash-quote-
    /// quote-quote.
    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
