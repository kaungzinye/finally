# Finally

Finally is a free, open-source iOS task manager that connects to [Notion](https://www.notion.com) or a Finally Server selected by the user. It supports inline task creation, reminders, recurring tasks, widgets, and provider-scoped synchronization.

[`main`](https://github.com/kaungzinye/finally/tree/main) is the public integration branch. Fork it, branch from it, and open pull requests against it.

## Features

- Notion OAuth: connect any workspace where you're a member
- Two-way sync with your Tasks and Projects databases
- Inbox, Today, Upcoming, Kanban, and project browse views
- Inline task creation with chip-based fields (due date, target date, priority, tags, project, recurrence)
- Per-task local push reminders (anchored or exact-date)
- Home screen widget
- iOS 17+ with SwiftUI and SwiftData

See [`specs/001-notion-task-app/spec.md`](specs/001-notion-task-app/spec.md) for the full product spec.

## Repository layout

| Path | Description |
|------|-------------|
| [`Finally/`](Finally/) | iOS app (SwiftUI + SwiftData) |
| [`FinallyWidget/`](FinallyWidget/) | Home screen widget extension |
| [`FinallyTests/`](FinallyTests/) | Unit, integration, and E2E tests |
| [`vercel-notion-auth/`](vercel-notion-auth/) | Serverless OAuth relay (HTTPS callback + token exchange) |
| [`specs/001-notion-task-app/`](specs/001-notion-task-app/) | Feature specs and task checklist |
| [`PRIVACY.md`](PRIVACY.md) | Privacy policy |
| [`TERMS.md`](TERMS.md) | Terms of use |
| [`SECURITY.md`](SECURITY.md) | Private vulnerability reporting |
| [`SUPPORT.md`](SUPPORT.md) | Help and issue routing |
| [`GOVERNANCE.md`](GOVERNANCE.md) | Project decision process |

## Quick start

### iOS app

Requires macOS with Xcode 15+.

```bash
git clone https://github.com/kaungzinye/finally.git
cd finally

# Compile check (no simulator needed)
xcodebuild build -project Finally.xcodeproj -scheme Finally \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet

# Unit test compile check
xcodebuild build-for-testing -project Finally.xcodeproj -scheme Finally \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
```

Full setup (Notion integration, database schema, OAuth): [`specs/001-notion-task-app/quickstart.md`](specs/001-notion-task-app/quickstart.md).

If you change `project.yml`, regenerate the Xcode project:

```bash
xcodegen generate
```

### OAuth relay

```bash
cd vercel-notion-auth
npm install
vercel dev          # local dev at http://localhost:3000
```

Deploy and env var setup: [`vercel-notion-auth/DEPLOY.md`](vercel-notion-auth/DEPLOY.md).

## Contributing

All contributions target **`main`** from a branch named `<type>/<author>/<description>`. See [CONTRIBUTING.md](CONTRIBUTING.md).

- [Bug reports](.github/ISSUE_TEMPLATE/bug_report.yml)
- [Feature ideas](.github/ISSUE_TEMPLATE/feature_request.yml)
- [Private security reports](SECURITY.md)

## License

MIT. See [LICENSE](LICENSE). Contributions are accepted under the same MIT terms.

## Links

- [Privacy Policy](PRIVACY.md)
- [Terms of Use](TERMS.md)
- [Notion API docs](https://developers.notion.com)
