# Contributing to Finally

Thank you for your interest in contributing. **`main` is the only base branch** — fork it, create a feature branch, and open your pull request back to `main`.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## Branch strategy

```
main          ← public default; all PRs merge here
  └── your-feature-branch
```

We use a **single-branch workflow** on purpose:

- **Simple for contributors** — one place to clone, one PR target, no "which branch do I use?" confusion.
- **Matches how you'll publish** — GitHub default branch, releases, and README all point at `main`.
- **Good enough pre-1.0** — feature branches + PR review give you integration safety without a separate staging branch.

### When would you add `staging`?

Consider a `staging` branch later if you need:

- TestFlight builds from a fixed integration point while `main` accepts drive-by fixes
- Required CI gates before anything lands on the release branch
- Multiple maintainers merging large features in parallel before a coordinated release

Until then, **`main` + short-lived feature branches** is the right default for a solo or small OSS iOS project.

## Getting started

1. **Fork** [github.com/kaungzinye/finally](https://github.com/kaungzinye/finally).
2. **Clone** your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/finally.git
   cd finally
   ```
3. **Create a branch** off `main`:
   ```bash
   git checkout main
   git pull origin main
   git checkout -b your-name/short-description
   ```
4. **Set up** your environment — see [README.md](README.md) and [`specs/001-notion-task-app/quickstart.md`](specs/001-notion-task-app/quickstart.md).
5. **Make changes** with focused commits.
6. **Verify** your changes compile (see below).
7. **Open a pull request** targeting **`main`**.

## Build and test

Always verify the project compiles before submitting an iOS PR:

```bash
# App compile check
xcodebuild build -project Finally.xcodeproj -scheme Finally \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet

# Unit test target compile check
xcodebuild build-for-testing -project Finally.xcodeproj -scheme FinallyTests \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
```

If you change `project.yml`:

```bash
xcodegen generate
```

**E2E tests** hit the live Notion API and require credentials in `FinallyTests/E2E/E2EConfig.swift`. Optional for most PRs — unit and integration tests in `FinallyTests/Services/` are the default bar.

### OAuth relay changes

When editing `vercel-notion-auth/`:

```bash
cd vercel-notion-auth
npm ci
npm run typecheck
vercel dev          # manual smoke test
```

## Pull request guidelines

- **Target `main`** — always.
- **One concern per PR** when possible.
- **Link related issues** (`Fixes #123`).
- **Describe what changed and why** — screenshots for UI changes help.
- **Update specs** if you change behavior in `specs/001-notion-task-app/`.
- **No secrets** — never commit Notion client secrets, tokens, or API keys.

### Commit messages

```
feat: add target date chip to inline task creator
fix: reschedule anchored reminders when due date changes
docs: update quickstart for Vercel callback URL
test: add Phase 6B reminder fire-date unit tests
```

## Code conventions

### Swift / SwiftUI

- Swift 5.9+, iOS 17 deployment target
- SwiftData for persistence
- Wrap iOS 26 liquid-glass APIs in `if #available(iOS 26, *)` with fallbacks
- Priority colors: Urgent=red, High=orange, Medium=blue/yellow, Low=default

### TypeScript (OAuth relay)

- Handlers stay minimal — bridge OAuth only; no business logic
- Secrets in Vercel env vars only

### Specs

Feature specs live under `specs/001-notion-task-app/`. Update `spec.md` and/or `tasks.md` when user-visible behavior changes.

## Notion integration setup

1. Create a public integration at [notion.so/my-integrations](https://www.notion.so/my-integrations)
2. Register redirect URI: `https://finally-auth.vercel.app/api/notion/callback`
3. Deploy `vercel-notion-auth/` or use the shared relay for development
4. Create Tasks and Projects databases per `quickstart.md`

Do **not** commit your client secret.

## Review process

1. A maintainer reviews your PR.
2. Address feedback with additional commits.
3. Merge to `main` once approved.

## Questions?

Open a GitHub issue. For security concerns, see [SECURITY.md](SECURITY.md).
