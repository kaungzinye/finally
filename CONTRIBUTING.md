# Contributing to Finally

Thank you for your interest in contributing. This guide covers how to get set up, where to work, and what we expect in pull requests.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## Where to contribute

| Area | Base branch | Path |
|------|-------------|------|
| iOS app, widget, tests, specs | `001-notion-task-app` | `Finally/`, `FinallyWidget/`, `FinallyTests/`, `specs/` |
| OAuth relay | `main` | `vercel-notion-auth/` |
| Top-level docs (README, legal) | `main` | repo root |

Check which branch is relevant before you start. Most contributions today target **`001-notion-task-app`**.

## Getting started

1. **Fork** the repository on GitHub.
2. **Clone** your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/finally.git
   cd finally
   ```
3. **Create a branch** from the appropriate base:
   ```bash
   # iOS app work
   git checkout 001-notion-task-app
   git checkout -b your-name/short-description

   # OAuth relay work
   git checkout main
   git checkout -b your-name/short-description
   ```
4. **Set up** your environment — see [README.md](README.md) and, for the iOS app, `specs/001-notion-task-app/quickstart.md` on the development branch.
5. **Make your changes** with focused commits and clear messages.
6. **Verify** your changes compile (see below).
7. **Open a pull request** against the correct base branch.

## Build and test

### iOS app (`001-notion-task-app`)

Always verify the project compiles before submitting a PR:

```bash
# App compile check
xcodebuild build -project Finally.xcodeproj -scheme Finally \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet

# Unit test target compile check
xcodebuild build-for-testing -project Finally.xcodeproj -scheme FinallyTests \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
```

If you change `project.yml`, regenerate the Xcode project first:

```bash
xcodegen generate
```

**E2E tests** hit the live Notion API and require credentials in `FinallyTests/E2E/E2EConfig.swift`. They are optional for most PRs — unit and integration tests in `FinallyTests/Services/` are the default bar.

### OAuth relay (`main`)

```bash
cd vercel-notion-auth
npm install
npm run typecheck   # if available; see package.json
vercel dev          # manual smoke test
```

## Pull request guidelines

- **One concern per PR** when possible — easier to review and revert.
- **Link related issues** (`Fixes #123` or `Relates to #456`).
- **Describe what changed and why** — screenshots for UI changes are appreciated.
- **Update specs** if you change behavior covered by `specs/001-notion-task-app/`.
- **No secrets** — never commit Notion client secrets, tokens, or personal API keys.
- **Match existing style** — see conventions below.

### Commit messages

Use clear, imperative subject lines:

```
feat: add target date chip to inline task creator
fix: reschedule anchored reminders when due date changes
docs: update quickstart for Vercel callback URL
test: add Phase 6B reminder fire-date unit tests
```

## Code conventions

### Swift / SwiftUI (iOS)

- Swift 5.9+, iOS 17 deployment target
- SwiftData for persistence; follow existing model patterns in `Finally/Models/`
- Use `if #available(iOS 26, *)` with fallbacks for liquid-glass styling
- Priority colors: Urgent=red, High=orange, Medium=blue/yellow, Low=default
- Prefer extending existing services over duplicating Notion API logic

### TypeScript (OAuth relay)

- Keep handlers minimal — the relay only bridges OAuth; no business logic
- Secrets live in Vercel env vars, never in source

### Specs

Feature specs live under `specs/001-notion-task-app/`. If your change affects user-visible behavior, update `spec.md` and/or `tasks.md` in the same PR or a follow-up docs PR.

## Notion integration setup (for iOS contributors)

You'll need your own Notion public integration to test OAuth locally:

1. Create a public integration at [notion.so/my-integrations](https://www.notion.so/my-integrations)
2. Register redirect URI: `https://finally-auth.vercel.app/api/notion/callback` (or your own Vercel deployment)
3. Deploy `vercel-notion-auth/` or use the shared relay for development
4. Create Tasks and Projects databases matching the schema in `quickstart.md`

Do **not** commit your client secret. The iOS app only embeds the public client ID.

## Review process

1. A maintainer will review your PR.
2. Address feedback with additional commits or amend as requested.
3. Once approved, your PR will be merged.

We aim to respond within a few days; nudge politely if a PR sits idle.

## Questions?

Open a [GitHub Discussion](https://github.com/kaungzinye/finally/discussions) or issue if Discussions aren't enabled. For security concerns, see [SECURITY.md](SECURITY.md).
