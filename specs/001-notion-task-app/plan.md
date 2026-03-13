# Implementation Plan: Finally

**Branch**: `001-notion-task-app` | **Date**: 2026-03-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-notion-task-app/spec.md`

## Summary

Build an iOS 17+ SwiftUI app that connects to Notion via OAuth to read/write Tasks and Projects databases. The app presents a Todoist-style UI with inline task creation (chip-based fields), bottom tab navigation (Inbox/Today/Upcoming/Search/Browse), per-task custom staggered local push notifications, recurring task support (in-place due date advancement), home screen widgets with interactive checkboxes, and dark/light mode following system settings. A Vercel serverless function handles the OAuth token exchange to protect the Notion client secret.

## Technical Context

**Language/Version**: Swift 5.9+ / SwiftUI
**Primary Dependencies**: SwiftData, WidgetKit, AppIntents, UserNotifications, BackgroundTasks, AuthenticationServices (ASWebAuthenticationSession), Security (Keychain)
**Storage**: SwiftData (SQLite-backed) for local cache + Notion API as source of truth
**Testing**: XCTest
**Target Platform**: iOS 17.0+, iPhone-only
**Project Type**: Mobile app + serverless function (Vercel/TypeScript)
**Performance Goals**: Views load < 3s, task creation < 15s, sync < 5s for 500 tasks
**Constraints**: 64 local notification limit, Notion API 3 req/s rate limit, offline read-only
**Scale/Scope**: Single user, ~500 tasks, ~15 screens, 2 targets (app + widget extension)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

No constitution file found. Gate passes by default — no constraints to validate against.

**Post-Phase 1 re-check**: Design uses standard iOS patterns (SwiftData, WidgetKit, AppIntents). No exotic dependencies. Two targets (app + widget) is the minimum needed for home screen widget support. Vercel function is a single ~30-line endpoint. Architecture is straightforward.

## Project Structure

### Documentation (this feature)

```text
specs/001-notion-task-app/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: technical research findings
├── data-model.md        # Phase 1: entity definitions and relationships
├── quickstart.md        # Phase 1: setup and project structure guide
├── contracts/           # Phase 1: API and interface contracts
│   ├── notion-api.md    # Notion API endpoints and error handling
│   ├── url-schemes.md   # Deep linking URL scheme routes
│   └── widget-contract.md # Widget families, interactions, data sharing
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
Finally/                  # Main app target
├── App/
│   ├── FinallyApp.swift  # App entry, ModelContainer setup, .onOpenURL
│   └── NavigationRouter.swift           # Observable deep link navigation state
├── Models/
│   ├── TaskItem.swift                   # SwiftData @Model
│   ├── ProjectItem.swift                # SwiftData @Model
│   ├── ReminderItem.swift               # SwiftData @Model (local-only)
│   ├── UserSession.swift                # SwiftData @Model (non-secret metadata)
│   └── Enums.swift                      # TaskStatus, TaskPriority, Recurrence
├── Services/
│   ├── NotionAuthService.swift          # OAuth flow (ASWebAuthenticationSession)
│   ├── NotionAPIService.swift           # API calls (query, create, update pages)
│   ├── SyncService.swift                # Incremental + full sync orchestration
│   ├── NotificationService.swift        # UNUserNotificationCenter, rolling window
│   ├── SchemaValidator.swift            # Database property detection + validation
│   └── KeychainHelper.swift             # Security framework thin wrapper
├── Views/
│   ├── Tabs/
│   │   ├── InboxView.swift
│   │   ├── TodayView.swift
│   │   ├── UpcomingView.swift
│   │   ├── SearchFilterView.swift
│   │   └── BrowseProjectsView.swift
│   ├── Task/
│   │   ├── TaskRowView.swift            # Checkbox + name + chips
│   │   ├── TaskDetailView.swift         # Full editing sheet
│   │   ├── InlineTaskCreator.swift      # Quick-action bar
│   │   └── ReminderListView.swift       # Manage per-task reminders
│   ├── Components/
│   │   ├── ChipView.swift               # Tappable colored pill
│   │   ├── PriorityPicker.swift
│   │   ├── DatePickerSheet.swift
│   │   ├── TagPicker.swift
│   │   ├── ProjectPicker.swift
│   │   └── RecurrencePicker.swift
│   ├── Onboarding/
│   │   ├── NotionConnectView.swift
│   │   ├── DatabasePickerView.swift
│   │   └── SchemaErrorView.swift
│   └── Settings/
│       ├── SettingsView.swift
│       ├── AppearanceSettingView.swift
│       └── DatabaseSetupGuideView.swift
└── Shared/
    ├── ModelContainer+Shared.swift      # App Group container config
    └── Constants.swift                  # App Group ID, URL scheme, API URLs

FinallyWidget/            # Widget extension target
├── TaskListWidget.swift                 # Widget definition + TimelineProvider
├── WidgetViews.swift                    # Small/Medium/Large layouts
└── ToggleTaskCompleteIntent.swift       # AppIntent for checkbox

FinallyTests/             # Unit + integration tests
├── Services/
│   ├── SyncServiceTests.swift
│   ├── SchemaValidatorTests.swift
│   └── NotificationServiceTests.swift
└── Models/
    └── RecurrenceTests.swift

vercel-notion-auth/                      # Vercel serverless function
├── api/notion/token.ts                  # Token exchange endpoint
├── package.json
└── vercel.json
```

**Structure Decision**: Mobile app + lightweight API pattern. Two Xcode targets: main app and widget extension, sharing data via App Groups with SwiftData. A standalone Vercel project handles the single OAuth token exchange endpoint. Tests in a standard XCTest target.

## Complexity Tracking

No constitution violations to justify. Architecture uses standard iOS patterns with minimal abstraction.
