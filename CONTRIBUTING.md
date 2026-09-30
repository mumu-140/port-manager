# Contributing to mumu-140/port-manager

This repository is an independently maintained fork of [productdevbook/port-killer](https://github.com/productdevbook/port-killer). Contributions should target this repository's roadmap and infrastructure, not the upstream release or sponsor systems.

## Clone this repository

```bash
git clone https://github.com/mumu-140/port-manager.git
cd port-manager
```

Do not use the upstream repository as the default origin for normal development.

## Development requirements

### macOS

- macOS 15+
- Full Xcode installation
- Swift toolchain compatible with `platforms/macos/Package.swift`

```bash
cd platforms/macos
swift build
swift test --parallel
./scripts/build-app.sh
```

The app bundle build is the authoritative local packaging check. The package uses Swift macros and dependencies that may not work with Command Line Tools alone.

### Windows

- Windows 10+
- .NET 9 SDK

```powershell
cd platforms/windows/PortKiller
dotnet restore
dotnet build
```

### Linux

Runtime dependencies vary by distribution. Typical Debian/Ubuntu dependencies:

```bash
sudo apt install python3 python3-gi gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1
```

Tests:

```bash
python3 -m unittest discover -s platforms/linux/tests -v

cd portkiller-core
cargo build
cargo test
cargo clippy -- -D warnings
cargo fmt --check
```

## macOS localization rules

All user-visible English/Simplified-Chinese strings must use the existing localization registry:

```swift
Text(L("domain.key"))
Text(L("domain.formatted", value))
```

Do not introduce a second localization framework without an explicit migration plan.

Before submitting macOS UI changes, ensure:

- every literal `L("...")` key exists,
- English/Chinese printf placeholders remain compatible,
- user-visible English is not hardcoded into common SwiftUI initializers,
- language switching does not restart long-lived port-forward/tunnel state.

These checks are enforced in `LocalizationRegressionTests.swift`.

## Pull request workflow

1. Create a focused branch.
2. Make one logically scoped change.
3. Run the relevant platform tests.
4. Review the diff for unrelated formatting or generated files.
5. Push the branch and open a PR against `mumu-140/port-manager:main`.
6. Wait for the applicable GitHub Actions workflows.

For macOS PRs, the optional PR build workflow can produce an unsigned test artifact. It is not a notarized production build.

## Commit style

Use specific messages such as:

```text
feat(macos): add service start and stop controls
fix(linux): preserve tray state after scanner failure
test(macos): guard service editing persistence
docs: clarify independent release workflow
```

Avoid vague messages such as `cleanup`, `misc fixes`, or `update files`.

## Independence rules

The following must not be reintroduced without an explicit decision:

- upstream Sparkle feed URLs or signing keys,
- upstream GitHub Releases as the app's update source,
- upstream sponsor/static-data endpoints,
- upstream Homebrew tap publishing,
- workflows that write into upstream repositories,
- upstream credentials or secrets.

The upstream URL may appear where provenance, attribution, comparison, or historical context requires it.

## Compatibility identifiers

The application currently retains the `PortKiller` product/executable name and existing platform identifiers. This is deliberate: renaming them is a separate migration because it affects preferences, launch items, notifications, packaging, and user data.

Do not rename bundle IDs, namespaces, executables, install paths, or persisted keys as part of unrelated work.

## Code review expectations

Prefer:

- minimal changes,
- explicit failure handling,
- deterministic CI,
- platform-native patterns,
- no secret exposure,
- no destructive migrations without a compatibility plan.

For macOS Swift code, preserve strict concurrency assumptions and existing state-lifecycle boundaries.

## Fork provenance

Do not remove [FORK_NOTICE.md](FORK_NOTICE.md), the upstream attribution in README, or the preserved original copyright notice in [LICENSE](LICENSE).
