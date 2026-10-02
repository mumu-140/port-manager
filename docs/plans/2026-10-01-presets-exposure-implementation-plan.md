# Presets + Exposure UX v1 — Implementation Plan

**Status:** IMPLEMENTED — merged to `main` at `4b3bcbebf89979eb4656dbfb53d485fce0716995`
**Date:** 2026-10-01
**Design:** `docs/plans/2026-10-01-presets-exposure-design.md` (companion)
**Research:** `docs/research/2026-10-01-presets-exposure-research.md`
**Base SHA:** `3e007d4` (main)

File-level plan per milestone. Paths relative to repo root. No milestone changes manager/process/tunnel/storage behavior.

---

## M1 — Preset core + model field

### macOS
- Modify: `platforms/macos/Sources/Models/ManagedService.swift` — add `var presetID: String?` (Codable-safe: custom decode `decodeIfPresent`, encode skips nil; verify synthesized path or add explicit Codable as the file already does).
- Create: `platforms/macos/Sources/Services/Presets/ManagedServicePreset.swift` — struct + `PresetCategory` + `PresetField` descriptors (text/port/directory/single-select) + `PresetValue`.
- Create: `platforms/macos/Sources/Services/Presets/ManagedServicePresetRenderer.swift` — pure renderer: macOS zsh single-quote escaping (verified rule) + charset validation hooks.
- Create: `platforms/macos/Sources/Services/Presets/Presets/` — `StaticFileSharePreset.swift`, `SSHTunnelPresets.swift` (local/socks5/reverse), `DufsPreset.swift`, `JupyterPreset.swift`, `PresetRegistry.swift`.
- Tests: `PortKillerTests/ManagedServicePresetTests.swift` (generator validity × presets, fixed-flag presence, renderer adversarial matrix, field validators), extend `ManagedServiceModelTests` with presetID round-trip + missing-key decode.

### Windows
- Modify: `platforms/windows/PortKiller/Models/ManagedService.cs` — add `public string? PresetId { get; set; }` (System.Text.Json tolerant; `[JsonIgnore]` NOT applied — it must persist, unlike NormalizedHost).
- Create: `platforms/windows/PortKiller/Services/Presets/` — same conceptual set (`ManagedServicePreset.cs`, `PresetRegistry.cs`, `ManagedServicePresetRenderer.cs`, preset definitions).
- Tests: `PortKiller.Tests/ManagedServicePresetTests.cs` mirroring the macOS suite; lockstep checklist test asserting the same preset ids + field ids exist on both platforms (simple static list comparison inside each repo's suite; ids kept in sync manually per this plan).

**Exit criteria:** all new tests green; existing model tests green; no UI change.

---

## M2 — Dependency discovery layer

### macOS
- Create: `platforms/macos/Sources/Services/Presets/DependencyRequirement.swift` + `PathDependencyProbe.swift` (fileExists known paths → PATH probe via launch-path search; cached + `recheck()`).
- Definitions: python3 (macOS paths: /usr/bin/python3, /opt/homebrew/bin/python3, /usr/local/bin/python3), ssh (/usr/bin/ssh), dufs (/opt/homebrew/bin/dufs, /usr/local/bin/dufs), jupyter (PATH + ~/.local/bin/jupyter).
- Reuse: `AlertBanner` for the notInstalled state in forms.
- Tests: `PathDependencyProbeTests.swift` (stubs with temp dirs; state mapping; no network/no shell assertions via code review + probe design).

### Windows
- Create: `platforms/windows/PortKiller/Services/Presets/DependencyRequirement.cs` + `PathDependencyProbe.cs` (File.Exists known paths → `where.exe <binary>`; ssh: %SystemRoot%\\System32\\OpenSSH\\ssh.exe FIRST; dufs: scoop shims; python: PATH + py launcher).
- Tests: `PathDependencyProbeTests.cs` (same shape).

**Exit criteria:** probe states (available/notInstalled) proven by tests; cloudflared behavior unchanged (its existing detection stays as-is; migration of cloudflared onto the new layer is OUT of M2 scope to avoid touching frozen tunnel code).

---

## M3 — Editor integration macOS

- Modify: `platforms/macos/Sources/Views/ManagedServices/ManagedServicesListView.swift` — "+" opens preset picker (Menu) with Custom first, then registry order.
- Modify: `platforms/macos/Sources/Views/ManagedServices/ManagedServiceEditorView.swift` + `platforms/macos/Sources/ViewModels/ManagedServiceEditorViewModel.swift` — add preset mode: preset form renders fields (prefilled), Save → generator → existing `draftConfig` path → validator; Edit of a profile with presetID reopens the preset form; unknown presetID falls back to custom.
- Localization: extend `ManagedServiceStrings.entries` with `preset.*` keys (en + zh-Hans).
- Tests: extend `ManagedServiceEditorViewModelTests` (preset mode begin/beginEdit/draft/generator handoff); localization table tests auto-cover new keys.

---

## M4 — Editor integration Windows

- Modify: `platforms/windows/PortKiller/Views/ManagedServiceEditorWindow.xaml(.cs)` — preset picker (ComboBox or menu) + preset form panel; Save → generator → existing validation/save path; FolderBrowserDialog for directory fields (scoped to preset forms).
- Modify: `platforms/windows/PortKiller/Views/ManagedServicesView.xaml.cs` — "+" opens the same editor window in preset-pick mode.
- Localization: resource dictionary additions (en + zh-Hans), same keys as macOS.
- Tests: editor VM tests mirroring M3.

---

## M5 — Delete confirmation semantics

### macOS
- Create: `platforms/macos/Sources/Models/ManagedServiceDeleteConfirmation.swift` — pure mapping (status, tunnelActive, port, name) → (messageKey/format args, destructive button key).
- Modify: `ManagedServiceDetailView.swift` + `ManagedServicesListView.swift` — consume the mapping (title stays "Delete Service"; destructive button label per state; conflict message mentions the port and that the external process is not terminated; running+tunnel message names the temporary tunnel).
- Modify strings: extend `service.delete.*` (button variants: Delete / Stop & Delete / Delete Configuration Only + messages, en + zh).
- Tests: new `ManagedServiceDeleteConfirmationTests` (full matrix); update `deleteConfirmationsIncludeServiceName` expectations.

### Windows
- Create: `platforms/windows/PortKiller/Models/ManagedServiceDeleteCopy.cs` (same mapping; returns MessageBox text + buttons per state).
- Modify: `ManagedServicesView.xaml.cs` `Delete_Click` — keep transitioning guard; state-mapped YesNo with explicit destructive labels ("Stop & Delete" / "Delete" / "Delete Configuration Only"); zh resources.
- Tests: `ManagedServiceDeleteCopyTests.cs` (matrix); existing delete behavior tests unchanged.

---

## M6 — Exposure / Network Access panel

### macOS
- Modify: `platforms/macos/Sources/Views/ManagedServices/ManagedServiceDetailView.swift` — rename section slot to "Network Access" (new key `exposure.section`); three rows: Local (Open/Copy when running), Temporary public (existing Quick Tunnel controls re-worded: intent-based labels + helper copy), Stable public (link row to the existing Cloudflare tunnels UI — navigation via existing AppState/sidebar routing).
- Capability-gated actions: Open and Quick Tunnel controls are visible only for HTTP presets (`isHTTPService` metadata); custom services keep them. (SSH reverse preset removed during review — see the design doc's "Deferred" note.)
- Tests: view-model level (row visibility matrix); localization tests.

### Windows
- Modify: `ManagedServicesView.xaml(.cs)` + `TunnelViewModel.cs` surface (UI only) — same three rows; Named row hidden on Windows (decision a) — reviewer may override).
- Quick Tunnel runtime calls unchanged.

---

## M7 — Dufs + Jupyter presets (forms + warnings)

- Forms land with dependency banners (available at <path> / notInstalled + install link: brew/GitHub releases for dufs; jupyter.org for jupyter), mode selects (Dufs: read-only/upload/read+write with warnings), Jupyter fixed-flags notice + working-directory validation (rejects / and drive roots; home root warns only).
- Warnings wiring: writable Dufs + exposure → double warning in Exposure panel; public Jupyter warning text.
- Tests: generator/validator coverage (M1 suite extends); localization keys.

---

## M8 — Docs + manual QA

- README section: presets + exposure overview.
- Manual smoke checklist (documented results in PR):
  - macOS: python3 file share round-trip; ssh -L to a local throwaway listener; ssh -R against a reachable host (optional); dufs read-only share; jupyter start with token URL Open; Quick Tunnel share + stop-with-service; delete matrix incl. conflict + running+tunnel.
  - Windows: same minus Named row; ssh FoD notInstalled state rendering (dev machine with capability removed or stubbed probe).
- Run full suites: `swift test` (macOS); `dotnet test` (Windows runner).

---

## Verification commands

- macOS: `cd platforms/macos && swift build && swift test` (filter: `--filter ManagedService`).
- Windows: `cd platforms/windows && dotnet build && dotnet test`.
- Localization: existing localization regression tests must pass unmodified except extended key coverage.

## Risk register (short)

1. cmd.exe renderer edge cases → mitigated by constrain-and-quote + adversarial matrix + conservative charsets; worst case a preset rejects an exotic-but-legal path with a clear validation message (fail-safe, not fail-open).
2. Windows ssh not-present machines → first-class notInstalled state + install docs; preset remains usable after install.
3. jupyter --port-retries regression (user edits command via Custom and drops the flag) → acceptable: that is the custom path, user-authored; preset always renders the flag.
4. Scope creep in exposure panel → frozen: grouping + link only; provider protocol explicitly deferred.
