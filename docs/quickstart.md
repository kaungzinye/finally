# Quickstart: Finally

## Prerequisites

1. **Xcode 26.6+** to compile the iOS 26 Liquid Glass APIs
2. **Apple Developer account** (Team ID: GN4UMU6766)
3. **Notion account** with a public integration created at https://www.notion.so/my-integrations
4. **Vercel account** (free tier) for the OAuth token exchange serverless function
5. **Node.js 18+** (for Vercel development)

## Notion Integration Setup

1. Go to https://www.notion.so/my-integrations → "New integration"
2. Set type to **Public** (for OAuth)
3. Set redirect URI to `finally://oauth-callback`
4. Note the **Client ID** and **Client Secret**
5. Set up your Notion databases (see "Minimum Database Schema" below)

## Vercel Token Exchange Function

1. Create a Vercel project with a single serverless function at `api/notion/token`
2. Set environment variables: `NOTION_CLIENT_ID`, `NOTION_CLIENT_SECRET`
3. The function receives `{ code }`, calls Notion's `/v1/oauth/token`, returns `{ access_token, workspace_id, ... }`
4. Deploy to Vercel

## Xcode Project Setup

1. Create a new SwiftUI App project: `Finally`
2. **Bundle ID**: `com.kaungzinye.finally`
3. **Team**: GN4UMU6766
4. **Deployment Target**: iOS 17.0
5. **Capabilities**:
   - App Groups: `group.com.kaungzinye.finally`
   - Push Notifications (for local notifications permission)
   - Background Modes: Background fetch
6. Add a **Widget Extension** target: `FinallyWidget`
   - Add the same App Group capability
7. Register URL scheme `finally` in Info.plist

## Minimum Notion Database Schema

### Tasks Database (Required Properties)

| Property | Type | Options |
|----------|------|---------|
| Name (or any name) | `title` | — |
| Status | `status` | Groups: To-do (Not started), In progress (In progress), Complete (Done) |
| Due Date | `date` | — |

### Tasks Database (Recommended Properties)

| Property | Type | Options |
|----------|------|---------|
| Priority | `select` | Urgent, High, Medium, Low |
| Tags | `multi_select` | (user-defined) |
| Project | `relation` | Points to Projects database |
| Recurrence | `select` | None, Daily, Weekly, Monthly, Yearly |

### Projects Database (Required Properties)

| Property | Type | Options |
|----------|------|---------|
| Name (or any name) | `title` | — |

## Project Structure

```
Finally/
├── Finally/              # Main app target
│   ├── App/
│   │   ├── FinallyApp.swift
│   │   └── NavigationRouter.swift
│   ├── Models/
│   │   ├── TaskItem.swift               # SwiftData @Model
│   │   ├── ProjectItem.swift
│   │   ├── ReminderItem.swift
│   │   └── UserSession.swift
│   ├── Services/
│   │   ├── NotionAuthService.swift      # OAuth + ASWebAuthenticationSession
│   │   ├── NotionAPIService.swift       # API calls (query, create, update)
│   │   ├── SyncService.swift            # Incremental + full sync orchestration
│   │   ├── NotificationService.swift    # UNUserNotificationCenter management
│   │   ├── SchemaValidator.swift        # Database property detection + validation
│   │   └── KeychainHelper.swift         # Thin wrapper over Security framework
│   ├── Views/
│   │   ├── Tabs/
│   │   │   ├── InboxView.swift
│   │   │   ├── TodayView.swift
│   │   │   ├── UpcomingView.swift
│   │   │   ├── SearchFilterView.swift
│   │   │   └── BrowseProjectsView.swift
│   │   ├── Task/
│   │   │   ├── TaskRowView.swift        # Single task row with checkbox + chips
│   │   │   ├── TaskDetailView.swift     # Full task editing sheet
│   │   │   ├── InlineTaskCreator.swift  # Bottom bar with quick-action buttons
│   │   │   └── ReminderListView.swift   # Manage reminders for a task
│   │   ├── Components/
│   │   │   ├── ChipView.swift           # Tappable colored pill
│   │   │   ├── PriorityPicker.swift
│   │   │   ├── DatePickerSheet.swift
│   │   │   ├── TagPicker.swift
│   │   │   ├── ProjectPicker.swift
│   │   │   └── RecurrencePicker.swift
│   │   ├── Onboarding/
│   │   │   ├── NotionConnectView.swift
│   │   │   ├── DatabasePickerView.swift
│   │   │   └── SchemaErrorView.swift
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       ├── AppearanceSettingView.swift
│   │       └── DatabaseSetupGuideView.swift
│   └── Shared/
│       ├── ModelContainer+Shared.swift  # App Group container config
│       └── Constants.swift              # App Group ID, URL scheme, API URLs
├── FinallyWidget/        # Widget extension target
│   ├── TaskListWidget.swift             # Widget definition + timeline provider
│   ├── WidgetViews.swift                # Small/Medium/Large layouts
│   └── ToggleTaskCompleteIntent.swift   # AppIntent for checkbox
├── Shared/                              # Shared between app + widget
│   └── SharedConstants.swift            # App Group ID, shared model config
└── vercel-notion-auth/                  # Vercel serverless function
    ├── api/
    │   └── notion/
    │       └── token.ts
    ├── package.json
    └── vercel.json
```

## Running the Project

1. Open `Finally.xcodeproj` in Xcode 26.6+
2. Set the scheme to the main app target
3. Build and run on iPhone simulator (iOS 17+) or device
4. On first launch, choose Notion or Finally Server as your task provider

## Supported iOS versions

The app, widget, and test targets support iOS 17.0 and later. iOS 17–18 use
material surfaces and bordered primary buttons. iOS 26+ use Liquid Glass.
The deployment target stays at iOS 17 when building with a newer SDK.

`FinallyUITests/LaunchTests.swift` verifies first-use onboarding, all four tabs,
and inline task creation. Run it on a fresh simulator with each runtime:

```bash
xcodebuild test -project Finally.xcodeproj -scheme Finally \
  -destination 'platform=iOS Simulator,id=<simulator-uuid>' \
  -only-testing:FinallyUITests CODE_SIGNING_ALLOWED=NO
```

For a physical iPhone, pair it with the Mac, enable Developer Mode in Settings
under Privacy & Security, and confirm Enable after the phone restarts. Use an
Xcode version with device support for the phone's iOS version.
