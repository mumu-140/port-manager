# Release Policy

This document describes releases for the independently maintained `mumu-140/port-manager` fork.

## Source of truth

Production release artifacts must originate from:

https://github.com/mumu-140/port-manager

They must not be uploaded to, downloaded from, or auto-updated from the upstream `productdevbook/port-killer` release channel.

## Workflow behavior

`.github/workflows/release.yml` has two modes.

### Tag release

Pushing a `v*` tag creates a GitHub Release in this repository and builds platform artifacts.

Example:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release workflow creates release notes and uploads the generated artifacts to the matching release.

### Manual dispatch

Manual `workflow_dispatch` is a **build/test mode**. It produces Actions artifacts and does not create a production GitHub Release.

This separation prevents the previous failure mode where a branch name such as `main` could accidentally be treated as a release tag.

## macOS signing state

The current fork does not yet have its own complete production signing chain.

Therefore current CI/release macOS artifacts should be treated as unsigned or ad-hoc-signed test builds and are **not represented as Apple-notarized production binaries**.

Before enabling production-quality macOS distribution, provision this fork's own:

1. Apple Developer ID certificate,
2. notarization credentials,
3. hardened-runtime signing workflow,
4. Sparkle EdDSA key pair,
5. signed `appcast.xml` generation,
6. release verification tests.

Do not reuse upstream signing material.

## Sparkle policy

Sparkle remains a dependency, but automatic updates are disabled because the upstream feed/key were deliberately removed.

The updater may only be re-enabled after this repository has its own signed update feed. `Info.plist` must then receive this fork's own `SUFeedURL` and `SUPublicEDKey`.

## Homebrew

This fork does not publish into `productdevbook/homebrew-tap` and does not document the upstream Homebrew cask as an installation method.

If a Homebrew tap is introduced later, it must be owned and maintained by this fork's maintainer.

## Windows and Linux

Windows and Linux artifacts are built from the current repository revision by GitHub Actions.

Any future installer signing, package registry publishing, or distribution channel must likewise be configured under this project's own accounts and credentials.
