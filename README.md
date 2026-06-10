# Finally

Finally is a free, open-source iOS task manager that connects to your [Notion](https://www.notion.com) workspace. It syncs tasks from your Notion databases, supports Todoist-style inline creation, per-task reminders, recurring tasks, widgets, and dark mode.

**Status:** Active development. The iOS app lives on the [`001-notion-task-app`](https://github.com/kaungzinye/finally/tree/001-notion-task-app) branch; `main` currently holds the OAuth relay and project docs.

## Features

- Notion OAuth — connect any workspace where you're a member
- Two-way sync with your Tasks and Projects databases
- Inbox, Today, Upcoming, Kanban, and project browse views
- Inline task creation with chip-based fields (due date, target date, priority, tags, project, recurrence)
- Per-task local push reminders (anchored or exact-date)
- Home screen widget
- iOS 17+ with SwiftUI and SwiftData

See [`specs/001-notion-task-app/spec.md`](https://github.com/kaungzinye/finally/blob/001-notion-task-app/specs/001-notion-task-app/spec.md) on the development branch for the full product spec.

## Repository layout

| Path | Description |
|------|-------------|
| [`vercel-notion-auth/`](vercel-notion-auth/) | Serverless OAuth relay (HTTPS callback + token exchange) |
| [`PRIVACY.md`](PRIVACY.md) | Privacy policy |
| [`TERMS.md`](TERMS.md) | Terms of use |
| `001-notion-task-app` branch | iOS app, widget, tests, specs, Xcode project |

### Branch strategy

| Branch | Purpose |
|--------|---------|
| `main` | Stable infra (OAuth relay) and top-level docs |
| `001-notion-task-app` | Active app development (default branch for now) |

When contributing to the **iOS app**, branch off `001-notion-task-app`. When contributing to the **OAuth relay**, branch off `main`.

## Quick start

### OAuth relay (this branch)

```bash
cd vercel-notion-auth
npm install
vercel dev          # local dev at http://localhost:3000
```

Deploy and env var setup: [`vercel-notion-auth/DEPLOY.md`](vercel-notion-auth/DEPLOY.md).

### iOS app (development branch)

Requires macOS with Xcode 15+.

```bash
git checkout 001-notion-task-app

# Compile check (no simulator needed)
xcodebuild build -project Finally.xcodeproj -scheme Finally \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet

# Run unit tests (compile-only)
xcodebuild build-for-testing -project Finally.xcodeproj -scheme FinallyTests \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
```

Full setup (Notion integration, database schema, OAuth): see [`specs/001-notion-task-app/quickstart.md`](https://github.com/kaungzinye/finally/blob/001-notion-task-app/specs/001-notion-task-app/quickstart.md) on the development branch.

## Contributing

We welcome issues and pull requests. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR.

- **Bug reports** — use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.yml)
- **Feature ideas** — use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.yml)
- **Security issues** — see [SECURITY.md](SECURITY.md) (do not open public issues)

## License

MIT — see [LICENSE](LICENSE).

## Links

- [Privacy Policy](PRIVACY.md)
- [Terms of Use](TERMS.md)
- [Notion API docs](https://developers.notion.com)
