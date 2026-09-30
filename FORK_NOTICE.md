# Fork Notice and Project Provenance

## Origin

This repository, `mumu-140/port-manager`, began as a fork of:

**productdevbook/port-killer**  
https://github.com/productdevbook/port-killer

The original project supplied substantial code, design, project structure, and history that remain present in this repository.

## Independent maintenance

This fork is now maintained independently in:

**mumu-140/port-manager**  
https://github.com/mumu-140/port-manager

Independent maintenance means that normal operation and release engineering for this fork are not expected to depend on upstream infrastructure.

In particular, this fork has removed or replaced direct dependencies on:

- upstream GitHub Releases for in-app updates,
- the upstream Sparkle feed and EdDSA public key,
- upstream sponsor/static-data endpoints,
- upstream contributor API endpoints,
- upstream Homebrew tap publishing,
- release jobs that target upstream repositories,
- upstream social/funding links presented as this fork's maintainer links.

The upstream repository remains referenced where attribution and historical provenance require it.

## Names retained for compatibility

The application still uses the **PortKiller** name in executables, bundles, namespaces, install paths, and UI.

This is intentional compatibility, not a claim that the fork is the original upstream project.

A full product rename would require a separate migration for:

- macOS bundle identity and preferences,
- LaunchAtLogin state,
- notifications and permissions,
- Windows namespaces and packaging,
- Linux desktop/install paths,
- persisted user data,
- release artifact naming.

Until such a migration is deliberately implemented, compatibility identifiers remain unchanged.

## License and copyright

The project remains licensed under the MIT License.

The original copyright notice is retained in `LICENSE`. A second notice identifies contributions made in the independently maintained fork.

Nothing in this notice removes or diminishes attribution to upstream authors or contributors.

## Relationship to upstream

This repository is a fork, not an official continuation endorsed by the upstream maintainers.

Changes made here may diverge from upstream behavior, UI, localization, release policy, and roadmap. Upstream changes may still be reviewed and selectively ported when useful, but they are not automatically authoritative for this fork.

## Attribution policy for future contributors

Future contributions should preserve:

1. the MIT license,
2. this fork notice,
3. the upstream origin reference in the README,
4. relevant third-party notices and dependency licenses.

Upstream references should not be removed merely to make the repository appear unrelated to its history.
