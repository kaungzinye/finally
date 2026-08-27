# Contributing to Finally

Finally accepts focused bug fixes, features, tests, and documentation updates. All pull requests target `main`.

## Before you start

- Search existing issues and pull requests.
- Open a bug report for reproducible defects.
- Open a feature request before investing in a large change.
- Report security problems through the private channel in [SECURITY.md](SECURITY.md).
- Keep credentials, task data, screenshots with personal information, and OAuth callbacks out of issues and commits.

## Branch names

Use `<type>/<author>/<short-description>`.

- `feat/alice/widget-actions`
- `fix/alice/reminder-reschedule`
- `doc/alice/server-setup`
- `feat/agent/provider-architecture` for an automated coding agent

Use `feat`, `fix`, or `doc` for the type. Use your GitHub handle for the author segment. Automated agents use `agent`.

## Set up the project

You need macOS, Xcode 15 or later, and XcodeGen when changing `project.yml`.

```bash
git clone https://github.com/YOUR_USERNAME/finally.git
cd finally
git checkout -b feat/YOUR_USERNAME/short-description origin/main
```

The full Notion and OAuth setup is in [`specs/001-notion-task-app/quickstart.md`](specs/001-notion-task-app/quickstart.md).

## Build and test

Compile the app and test target before opening a pull request:

```bash
xcodebuild build -project Finally.xcodeproj -scheme Finally \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet

xcodebuild build-for-testing -project Finally.xcodeproj -scheme Finally \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
```

Run relevant unit or integration tests on an iOS Simulator when behavior changes. End-to-end Notion tests require private credentials and are optional unless the change affects that path.

For OAuth relay changes:

```bash
cd vercel-notion-auth
npm ci
npm run typecheck
```

Run `xcodegen generate` after changing `project.yml`.

## Pull requests

- Keep one concern in each pull request.
- Explain the user-visible behavior and the reason for the change.
- Link the issue with `Fixes #123` when the pull request resolves it.
- Add screenshots or recordings for interface changes.
- Update tests, specs, privacy text, or setup instructions when the behavior requires it.
- Disclose meaningful AI assistance. You remain responsible for every submitted line.
- Respond to review comments and keep the branch current with `main`.

Use Conventional Commit subjects such as `feat:`, `fix:`, `docs:`, `test:`, or `chore:`.

## Contribution terms

By submitting a contribution, you confirm that you have the right to provide it and agree that it is licensed under this repository's [MIT License](LICENSE). Identify copied or adapted work in the pull request and preserve any required copyright or license notices.

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). The maintainer reviews contributions under the process described in [GOVERNANCE.md](GOVERNANCE.md).
