# Security Policy

## Reporting a vulnerability

Prefer GitHub's private vulnerability reporting / Security Advisory flow for this repository when it is available.

Do not post credentials, tokens, private keys, cookies, personally identifying logs, or exploitable secrets in a public issue.

If a public issue is the only available contact path, report only the minimum non-sensitive description needed to establish that a security problem exists. Sensitive reproduction details should wait for a private channel.

## Scope

Security-sensitive areas include:

- process termination and privilege boundaries,
- command execution,
- Kubernetes configuration and subprocess handling,
- Cloudflare tunnel invocation,
- persisted paths and user configuration,
- auto-start / launch-at-login behavior,
- update and release infrastructure,
- artifact integrity.

## Release/update trust

This fork does not trust the upstream project's signing keys or release feed as its own.

Automatic Sparkle updates remain disabled until `mumu-140/port-manager` provisions an independent signed update channel.

## Secrets

Repository workflows must never print or persist signing certificates, passwords, API tokens, SSH private keys, Sparkle private keys, or other credentials.

New release credentials should be stored only in the repository's protected GitHub Actions secrets/environments and should be scoped to the minimum required permissions.
