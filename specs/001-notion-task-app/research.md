# Research: Finally

**Date**: 2026-03-13
**Feature**: 001-notion-task-app

## 1. Notion OAuth for iOS

### Token Exchange Server

- **Decision**: Vercel serverless function (single `/api/notion/callback` endpoint)
- **Rationale**: Notion OAuth requires `client_secret` in the token exchange step (`POST /v1/oauth/token` with Basic auth). The secret cannot be embedded in a shipped iOS binary. Vercel is zero-config, free tier covers personal use, ~30 lines of TypeScript.
- **Alternatives considered**:
  - Cloudflare Worker: strong alternative, faster cold starts, but more setup
  - AWS Lambda: overkill infrastructure for a single endpoint
  - App Attest + direct call: not viable — App Attest proves app legitimacy but doesn't solve secret exposure

### OAuth Flow on iOS

- **Decision**: `ASWebAuthenticationSession` with custom URL scheme callback
- **Rationale**: Apple's intended mechanism for OAuth since iOS 12. Secure (sandboxed browser session, no scheme hijacking). Works natively on iOS 17+.
- **Flow**:
  1. App opens `ASWebAuthenticationSession` → `https://api.notion.com/v1/oauth/authorize?client_id=...&redirect_uri=finally://oauth-callback`
  2. User authorizes in Notion
  3. Callback intercepted: `finally://oauth-callback?code=XXX`
  4. App sends `code` to Vercel function
  5. Vercel exchanges code for `access_token` using `client_secret`
  6. App stores token in Keychain
- **Alternatives considered**:
  - Universal Links: more secure against hijacking but requires domain + AASA file setup. Unnecessary since ASWebAuthenticationSession already prevents hijacking.
  - Raw custom URL scheme (without ASWebAuthenticationSession): vulnerable to scheme hijacking

### Token Storage

- **Decision**: Native iOS Keychain (Security framework with thin wrapper)
- **Rationale**: No third-party dependency for security-critical component. `kSecAttrAccessibleAfterFirstUnlock` allows background access.
- **Alternatives considered**:
  - KeychainAccess library: cleaner API but adds dependency for a small wrapper
  - UserDefaults: never appropriate for tokens (unencrypted)

### Notion API Version

- **Decision**: `2022-06-28` (verify at implementation time for newer versions)
- **Rationale**: Latest stable version as of training data. Includes status property type needed for task status.

## 2. Data Persistence

### Framework

- **Decision**: SwiftData
- **Rationale**: Greenfield iOS 17+ app. Native SwiftUI integration (`@Query`, `@Environment(\.modelContext)`). Less boilerplate than CoreData. Same SQLite backing store. Stable by iOS 17.2+. Apple's clear direction forward.
- **Alternatives considered**:
  - CoreData: works but more boilerplate, XML model files, no native SwiftUI integration
  - Realm/GRDB: unnecessary third-party dependency

### Widget Data Sharing

- **Decision**: SwiftData + App Groups (shared SQLite via App Group container)
- **Rationale**: Widget extension needs read access to tasks. Same `ModelContainer` URL pointed at App Group directory. Widget reads only; writes happen via AppIntents which run in main app process.
- **App Group**: `group.com.kaungzinye.finally`

## 3. Notion Sync Strategy

### Sync Pattern

- **Decision**: Incremental sync by default (using `last_edited_time` filter), periodic full refresh for deletion detection
- **Rationale**: Efficient API usage. Notion has no webhooks, so polling is required. `last_edited_time` filter returns only changed pages. Full refresh (~every 10th sync or daily) catches deletions that incremental sync misses.
- **Polling frequency**:
  - On app launch
  - Pull-to-refresh
  - 60-90 second timer while foregrounded
  - `BGAppRefreshTask` while backgrounded (~15-30 min)

### Optimistic Updates

- **Decision**: Optimistic local-first with `isDirty` flag
- **Rationale**: Instant UI response. Local SwiftData model updated immediately, `isDirty = true`. Background sync pushes to Notion. On failure, retry on next sync cycle.

### Conflict Resolution

- **Decision**: Last-write-wins (remote wins on pull)
- **Rationale**: Single-user app. True conflicts (editing same task in Notion web and iOS app simultaneously) are extremely rare. Remote wins keeps Notion as source of truth. Brief toast notification when local changes are overwritten.

### Rate Limits

- Notion: 3 requests/second per integration
- 500 tasks at 100/page = 5 API calls for full refresh. Well within limits.
- Handle HTTP 429 with `Retry-After` header + exponential backoff.

## 4. Recurrence Storage

- **Decision**: Select property in Notion (options: None/Daily/Weekly/Monthly/Yearly)
- **Rationale**: Notion is the source of truth. Survives app reinstall. Visible in Notion's UI. Implementation identical to Priority property. The schema validation flow (FR-002) already handles communicating required properties.
- **Alternatives considered**:
  - Local-only (SwiftData): lost on reinstall, invisible in Notion
  - Formula property: read-only via API, can't write
  - Text property: unstructured, Select is cleaner

## 5. Local Notifications

### 64-Notification Limit Strategy

- **Decision**: Rolling window priority queue — schedule nearest 60 reminders, reschedule on every change
- **Rationale**: iOS caps at 64 pending local notifications per app. Schedule the soonest-firing reminders. Leave 4 slots as buffer. Recalculate on: task CRUD, `scenePhase` → `.active`, background refresh, after any notification fires.

### Identifier Scheme

- **Decision**: Deterministic format `"task-{notionPageId}-reminder-{intervalSeconds}"`
- **Rationale**: Can reconstruct identifier from task + reminder data without querying pending notifications. Enables precise cancel/reschedule.

### Deep Linking

- **Decision**: `userInfo["taskID"]` in notification content + `UNUserNotificationCenterDelegate.didReceive` + observable navigation router
- **Rationale**: Standard iOS pattern. Router publishes navigation target, SwiftUI `NavigationStack` observes and pushes task detail view.

### Background Refresh

- **Decision**: `BGAppRefreshTaskRequest` + reschedule on foreground entry
- **Rationale**: Keeps notification slots topped up as earlier notifications fire. iOS determines actual frequency (~15-30 min for actively used apps).

## 6. WidgetKit (iOS 17+)

### Widget Families

- **Decision**: Support `.systemSmall`, `.systemMedium`, `.systemLarge`
- **Rationale**: Matches spec requirement for all three sizes. Lock Screen widgets (`.accessoryCircular`, `.accessoryRectangular`) are out of scope for MVP.

### Interactive Widgets

- **Decision**: Use `Toggle(isOn:intent:)` with `AppIntent` for task completion checkboxes
- **Rationale**: iOS 17 added interactive widgets via AppIntents. Toggle performs action in-process without launching app. System auto-reloads timeline after `perform()`.

### "+" Button

- **Decision**: `Link(destination:)` with custom URL scheme `finally://tasks/new`
- **Rationale**: Apple guidance: use `Link`/`widgetURL` for app-opening actions, not `Button(intent:)`. App handles via `.onOpenURL`.

### Timeline Refresh

- `WidgetCenter.shared.reloadTimelines(ofKind:)` on every task data change
- `.atEnd` policy in `TimelineProvider`
- Generate entries at each upcoming task due time
- Budget: ~40-70 refreshes/day (explicit reloads from foreground app don't count)
