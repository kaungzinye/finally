# Contract: URL Schemes & Deep Linking

**Date**: 2026-03-13

## Custom URL Scheme

**Scheme**: `finally://`

### Routes

| URL | Source | Action |
|-----|--------|--------|
| `finally://oauth-callback?code={code}` | Notion OAuth redirect | Extract `code`, exchange for token via Vercel function |
| `finally://tasks/new` | Widget "+" button | Open app, present inline task creation |
| `finally://tasks/{externalTaskID}` | Notification tap, widget task tap | Open app, navigate to the task inside the selected provider workspace |

### Handling

All URLs handled via SwiftUI `.onOpenURL { url in ... }` modifier on the root view. An observable `NavigationRouter` parses the URL and sets navigation state.
