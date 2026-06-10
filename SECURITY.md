# Security Policy

## Supported versions

| Component | Branch | Notes |
|-----------|--------|-------|
| OAuth relay (`vercel-notion-auth/`) | `main` | Receives auth codes; must not log or persist tokens |
| iOS app | `001-notion-task-app` | Stores Notion tokens in Keychain only |

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Instead, email **kaungzinye11@gmail.com** with:

- Description of the vulnerability
- Steps to reproduce
- Impact assessment (what an attacker could access or do)
- Your suggested fix, if any

We aim to acknowledge reports within **72 hours** and will keep you updated on remediation progress.

## Scope

In scope:

- OAuth token exchange or callback handling in `vercel-notion-auth/`
- Notion token storage or leakage in the iOS app
- Authentication or authorization bypasses
- Injection or data exfiltration via sync/API handling

Out of scope:

- Denial-of-service against Notion's API
- Social engineering
- Issues in third-party services (Notion, Vercel) — report those to the vendor directly

## Safe harbor

We appreciate responsible disclosure and will not pursue legal action against researchers who report issues in good faith and allow reasonable time for a fix before public disclosure.
