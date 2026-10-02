# Presets & exposure — manual smoke checklist

Companion to `2026-10-01-presets-exposure-design.md` (section 18). Automated
coverage: macOS `swift test` (222 tests, 17 suites, green); Windows xunit
suite runs in CI. Items below need a human at the UI; checked items were
verified on macOS during implementation.

## Security invariants (must hold at every milestone)

- [x] No process is ever signalled except runtimes this session owns, or conflict occupants with explicit per-PID confirmation (preset paths only generate ordinary profiles; no new kill paths).
- [x] No credentials, tokens, passwords, or key material in profiles, commands, logs, or memory (no preset has a credential field; Jupyter token stays server-generated).
- [x] Every listening preset binds `127.0.0.1` explicitly — including the SSH local forward's listener (`-L 127.0.0.1:{port}:`); no non-loopback bind is offered (SSH reverse preset is not in v1).
- [x] Dependency discovery is read-only; no installs, no network, no config writes (PATH probes only).
- [x] Quick Tunnel lifecycle unchanged: process-bound, auto-stopped with the service, never auto-restarted (runtime untouched; only the section slot was re-grouped).
- [x] Stop service stops its tunnels; restart never re-shares; relaunch leaves surviving listeners as unowned Conflict (manager paths untouched).
- [x] Delete copy states exactly what will happen; conflict delete never touches the external occupant (semantic mapping tested on both platforms).
- [x] No auto-restart/persistence of any service or tunnel; profiles reload as Stopped (persistence untouched).

## macOS smoke pass

- [x] Plus menu lists Custom + five presets; uninstalled presets show "— not installed".
- [x] Static file share: directory chooser, port 8123 default, generated command uses POSIX single quotes for paths with spaces.
- [x] SSH local forward: host/remote port fields, generated command carries `-N -L 127.0.0.1:{port}:` (explicit loopback bind), keepalives, ExitOnForwardFailure; no extra-options field.
- [x] Switching presets re-renders the form live (Custom → SSH Local clears preset fields; Save-enabled state follows validation immediately).
- [x] Dufs: dependency banner shows dufs path or install-docs button; mode picker; writable mode shows the writable warning.
- [x] Jupyter: token + public warnings shown; `--port-retries=0` in the generated command.
- [x] Home directory root as share directory adds the home-root warning.
- [x] Re-opening a saved preset profile pre-fills the form (extractor round-trip).
- [x] Switching preset → Custom keeps the generated command in the start-command field.
- [x] Network Access section: Local row with URL + Copy/Open while running; Temporary public with helper copy; Stable public deep-links to Tunnels.
- [x] Sharing a writable Dufs or Jupyter shows the exposure confirmation before the tunnel starts.
- [x] Delete confirmations: stopped → "Delete service…"; running → "Stop and delete…"; running + Quick Tunnel → names the tunnel; conflict → "Delete Configuration Only" and names the port.
- [x] zh-CN localization renders for every new key (en + zh provided; CI guards parity).

## Windows smoke pass (needs a Windows machine / CI runner)

- [ ] Plus button opens the editor; Type ComboBox lists Custom + five presets with "— not installed" suffixes.
- [ ] Static file share: Choose... opens FolderBrowserDialog; generated command quotes paths with spaces.
- [ ] SSH presets: generated command carries the fixed flags and the explicit `-L 127.0.0.1:{port}:` / `-D 127.0.0.1:{port}` binds; keepalives editable.
- [ ] Dufs: dependency banner via where.exe probe; Store-alias stub filtered.
- [ ] Jupyter: warnings rendered; `--port-retries=0` present.
- [ ] Re-opening a saved preset profile pre-fills the form.
- [ ] Network Access section: Local URL row; Temporary public card; no Stable public row (hidden by design).
- [ ] Sharing a writable Dufs or Jupyter shows the exposure task-dialog confirmation.
- [ ] Delete confirmations show the semantic task dialog (Stop & Delete / Delete / Delete Configuration Only).
- [ ] Transitioning guard message still appears while a service is starting/stopping.
