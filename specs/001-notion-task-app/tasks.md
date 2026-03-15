# Tasks: Finally — Notion Task App with Reminders

**Input**: Design documents from `/specs/001-notion-task-app/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested. Test tasks omitted.

**Organization**: Tasks grouped by user story for independent implementation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1-US8)
- Exact file paths included in descriptions

---

## Phase 1: Setup

**Purpose**: Xcode project initialization, targets, and shared infrastructure

- [x] T001 Create Xcode project `Finally` with SwiftUI App lifecycle, bundle ID `com.kaungzinye.finally`, deployment target iOS 17.0, team GN4UMU6766
- [x] T002 Add Widget Extension target `FinallyWidget` to the Xcode project
- [x] T003 Configure App Group capability `group.com.kaungzinye.finally` on both main app and widget extension targets
- [x] T004 Register custom URL scheme `finally` in main app target Info.plist
- [x] T005 Enable Background Modes capability (Background fetch) on main app target
- [x] T006 [P] Create `Finally/Shared/Constants.swift` with App Group ID, URL scheme, Vercel API base URL, Notion API base URL, and Notion API version header
- [x] T007 [P] Create `vercel-notion-auth/` directory with `package.json`, `vercel.json`, and placeholder `api/notion/token.ts`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: SwiftData models, Keychain helper, Notion API client, and shared ModelContainer — all user stories depend on these

- [x] T008 Create `Finally/Models/Enums.swift` with `TaskStatus` (.notStarted/.inProgress/.done), `TaskPriority` (.urgent/.high/.medium/.low with color properties), and `Recurrence` (.none/.daily/.weekly/.monthly/.yearly with date-advancing logic)
- [x] T009 Create `Finally/Models/ProjectItem.swift` SwiftData @Model with fields: notionPageId (String), title (String), lastEditedTime (Date?), lastSyncedAt (Date?), and inverse relationship to tasks
- [x] T010 Create `Finally/Models/TaskItem.swift` SwiftData @Model with fields: notionPageId, title, status (TaskStatus), dueDate (Date?), priority (TaskPriority?), tags ([String]), recurrence (Recurrence), lastEditedTime, lastSyncedAt, isDirty (Bool), isDeleted (Bool), relationship to ProjectItem, and cascade relationship to ReminderItem array
- [x] T011 Create `Finally/Models/ReminderItem.swift` SwiftData @Model with fields: id (UUID), intervalSeconds (Int), label (String), notificationId (String), isScheduled (Bool), relationship to TaskItem
- [x] T012 Create `Finally/Models/UserSession.swift` SwiftData @Model with fields: id (UUID), workspaceId, workspaceName, tasksDatabaseId, projectsDatabaseId, propertyMappings (stored as JSON Data), lastFullSyncAt, createdAt — note: accessToken stored in Keychain, not here
- [x] T013 Create `Finally/Shared/ModelContainer+Shared.swift` configuring a shared ModelContainer pointing at the App Group container URL for all model types
- [x] T014 [P] Create `Finally/Services/KeychainHelper.swift` with save/read/delete methods wrapping Security framework (SecItemAdd/SecItemCopyMatching/SecItemDelete) using kSecAttrAccessibleAfterFirstUnlock
- [x] T015 [P] Create `Finally/Services/NotionAPIService.swift` with base HTTP client: method to build URLRequest with Bearer token + Notion-Version header, generic request executor with JSON decoding, error handling for 401/429/5xx per contracts/notion-api.md, and rate limit retry with Retry-After header
- [x] T016 Create `Finally/App/NavigationRouter.swift` as @Observable class with properties for: selectedTab, deepLinkTaskId, showNewTaskSheet — handles URL parsing from .onOpenURL per contracts/url-schemes.md
- [x] T017 Create `Finally/App/FinallyApp.swift` as @main App struct with: shared ModelContainer setup, NavigationRouter as environment, .onOpenURL handler routing to NavigationRouter, UNUserNotificationCenter delegate setup

**Checkpoint**: Foundation ready — all models, Keychain, API client, and app shell in place

---

## Phase 3: User Story 1 — Connect Notion Account via OAuth (Priority: P1)

**Goal**: User can connect Notion workspace, authenticate via OAuth, and establish a session with token stored securely.

**Independent Test**: Launch app → tap "Connect Notion" → complete OAuth → verify token stored and session created.

### Implementation

- [x] T018 [US1] Implement `vercel-notion-auth/api/notion/token.ts` serverless function: receive POST `{ code }`, call Notion `/v1/oauth/token` with Basic auth (client_id:client_secret from env vars), return `{ access_token, workspace_id, workspace_name, bot_id }` or error response
- [x] T019 [US1] Create `Finally/Services/NotionAuthService.swift` with: buildAuthorizationURL (Notion OAuth URL with client_id, redirect_uri, response_type=code, owner=user), startOAuthFlow using ASWebAuthenticationSession with callbackURLScheme "finally", extractAuthCode from callback URL, exchangeCodeForToken calling Vercel function, and storeSession saving token to Keychain + creating UserSession in SwiftData
- [x] T020 [US1] Create `Finally/Views/Onboarding/NotionConnectView.swift` showing app logo, "Connect to Notion" button that triggers NotionAuthService.startOAuthFlow, loading state during token exchange, and error display with retry option
- [x] T021 [US1] Wire up OAuth callback in NavigationRouter: when URL matches `finally://oauth-callback?code=XXX`, extract code and trigger token exchange flow
- [x] T022 [US1] Add session detection in FinallyApp.swift: on launch check if UserSession exists + Keychain has valid token → if yes show main tab view, if no show NotionConnectView
- [x] T023 [US1] Handle 401 token revocation in NotionAPIService.swift: detect unauthorized response → clear Keychain + delete UserSession → navigate to NotionConnectView with "Session expired" message

**Checkpoint**: User can authenticate with Notion and the app persists the session across launches

---

## Phase 4: User Story 2 — View Tasks in Todoist-style Views (Priority: P1)

**Goal**: User sees Notion tasks organized in Inbox, Today, Upcoming, and per-Project views with bottom tab navigation.

**Independent Test**: Connect Notion → verify tasks appear grouped correctly in each tab view → pull-to-refresh updates data.

### Implementation

- [x] T024 [US2] Add query/create/update page methods to `NotionAPIService.swift`: queryDatabase (with filter + sort + pagination using start_cursor/has_more), retrieveDatabase (for schema), createPage, updatePage — all returning decoded Notion JSON structures
- [x] T025 [US2] Create `Finally/Services/SyncService.swift` with: fetchAllTasks (paginated query of Tasks database → map Notion page properties to TaskItem fields → upsert into SwiftData), fetchAllProjects (same for Projects), incrementalSync using last_edited_time filter, fullSync that detects deletions by comparing Notion page IDs to local notionPageIds, and syncOnLaunch entry point
- [x] T026 [US2] Create `Finally/Views/Task/TaskRowView.swift` — Todoist-style task row with: circular checkbox (tap to complete), task title, colored priority indicator dot, due date chip, project name chip, tags as small pills — use swipe actions (right: complete, left: more options)
- [x] T027 [US2] Create `Finally/Views/Tabs/InboxView.swift` — List of tasks where project relation is nil, using @Query with predicate filtering project == nil and status != .done, sorted by dueDate, with pull-to-refresh triggering SyncService
- [x] T028 [P] [US2] Create `Finally/Views/Tabs/TodayView.swift` — Two sections: "Overdue" (dueDate < today, status != .done) and "Today" (dueDate == today, status != .done), sorted by priority then dueDate, with pull-to-refresh
- [x] T029 [P] [US2] Create `Finally/Views/Tabs/UpcomingView.swift` — Tasks grouped by date headers scrolling into the future, using Dictionary(grouping:) on dueDate, sorted ascending, with pull-to-refresh
- [x] T030 [P] [US2] Create `Finally/Views/Tabs/BrowseProjectsView.swift` — List of all ProjectItems, each tappable to navigate to a filtered task list showing only tasks for that project
- [x] T031 [P] [US2] Create `Finally/Views/Tabs/SearchFilterView.swift` — Search bar filtering tasks by title, with filter chips for priority and status
- [x] T032 [US2] Create main TabView in `Finally/Views/ContentView.swift` with 5 tabs: Inbox (tray icon), Today (calendar icon), Upcoming (calendar.badge.clock icon), Search (magnifyingglass icon), Browse (folder icon) — bind selected tab to NavigationRouter.selectedTab
- [x] T033 [US2] Wire up sync-on-launch in FinallyApp.swift: after session detection succeeds, trigger SyncService.syncOnLaunch as a background Task, show loading indicator during first sync

**Checkpoint**: All task views populated from Notion data, tab navigation works, pull-to-refresh syncs

---

## Phase 5: User Story 3 — Add and Edit Tasks Inline (Priority: P2)

**Goal**: User can create tasks with inline Todoist-style creation bar (chip-based fields) and edit existing tasks, synced to Notion.

**Independent Test**: Tap "+" → type task name → set date/priority/tags/project/recurrence via chip buttons → submit → verify task appears in Notion and in app.

### Implementation

- [x] T034 [P] [US3] Create `Finally/Views/Components/ChipView.swift` — reusable tappable colored pill component with label text, optional SF Symbol icon, background color, and tap action closure
- [x] T035 [P] [US3] Create `Finally/Views/Components/DatePickerSheet.swift` — bottom sheet with calendar date picker, returns selected Date
- [x] T036 [P] [US3] Create `Finally/Views/Components/PriorityPicker.swift` — compact picker showing 4 options (Urgent/red, High/orange, Medium/blue, Low/default) as colored rows, returns TaskPriority
- [x] T037 [P] [US3] Create `Finally/Views/Components/TagPicker.swift` — multi-select list of existing tags fetched from Notion database options, returns [String]
- [x] T038 [P] [US3] Create `Finally/Views/Components/ProjectPicker.swift` — list of all ProjectItems from SwiftData plus "Inbox" option, returns ProjectItem?
- [x] T039 [P] [US3] Create `Finally/Views/Components/RecurrencePicker.swift` — picker with None/Daily/Weekly/Monthly/Yearly options, returns Recurrence
- [x] T040 [US3] Create `Finally/Views/Task/InlineTaskCreator.swift` — Todoist-style bottom bar: text field for task name, horizontal quick-action button row below (calendar, flag, tag, folder, repeat icons), selected values shown as ChipView instances, send button to submit — on submit: create TaskItem locally with isDirty=true, push to Notion via NotionAPIService.createPage in background
- [x] T041 [US3] Create `Finally/Views/Task/TaskDetailView.swift` — modal sheet showing all task fields as tappable rows/chips: title (editable text), due date (ChipView → DatePickerSheet), priority (ChipView → PriorityPicker), tags (ChipView row → TagPicker), project (ChipView → ProjectPicker), recurrence (ChipView → RecurrencePicker), reminders section (placeholder for US4) — on edit: update local model with isDirty=true, push to Notion via NotionAPIService.updatePage in background
- [x] T042 [US3] Add InlineTaskCreator to all tab views (InboxView, TodayView, UpcomingView, BrowseProjectsView project detail) as an overlay at the bottom, triggered by a floating "+" button
- [x] T043 [US3] Implement task completion in TaskRowView: checkbox tap → if non-recurring: update status to .done locally + push to Notion; if recurring: handled in US5 (for now just mark done)
- [x] T044 [US3] Implement optimistic sync in SyncService: add pushDirtyChanges method that queries all isDirty==true entities and pushes each to Notion, clearing isDirty on success — call after every local mutation

**Checkpoint**: Tasks can be created and edited inline with all fields, changes sync to Notion

---

## Phase 6: User Story 4 — Set Custom Staggered Reminders per Task (Priority: P2)

**Goal**: User can configure multiple reminders per task at custom intervals before the due date, delivered as local push notifications.

**Independent Test**: Open task with due date → add 3 reminders (1 day, 2 hours, 30 min before) → verify notifications arrive at correct times.

### Implementation

- [x] T045 [US4] Create `Finally/Services/NotificationService.swift` with: requestPermission (UNUserNotificationCenter.requestAuthorization), scheduleReminder (create UNNotificationRequest with UNCalendarNotificationTrigger from dueDate - intervalSeconds, identifier format "task-{notionPageId}-reminder-{intervalSeconds}", userInfo with taskID for deep linking), cancelRemindersForTask (remove by identifier prefix), rescheduleAllReminders (rolling window: sort all reminders by fire date, schedule nearest 60, mark isScheduled accordingly), checkPermissionStatus
- [x] T046 [US4] Create `Finally/Views/Task/ReminderListView.swift` — section in TaskDetailView showing list of configured ReminderItems with labels and delete buttons, plus "Add Reminder" button that presents a picker for interval selection (preset options: 5 min, 15 min, 30 min, 1 hour, 2 hours, 1 day, 2 days, 1 week + custom)
- [x] T047 [US4] Wire reminder management into TaskDetailView.swift: add ReminderListView section, on add/delete reminder: create/delete ReminderItem in SwiftData, call NotificationService.rescheduleAllReminders
- [x] T048 [US4] Implement notification tap deep linking: in FinallyApp.swift, set UNUserNotificationCenter.delegate, implement didReceive to extract taskID from userInfo and set NavigationRouter.deepLinkTaskId, which triggers navigation to TaskDetailView
- [x] T049 [US4] Add reminder rescheduling on due date change: in TaskDetailView when due date is edited, call NotificationService.rescheduleAllReminders; in task completion, call NotificationService.cancelRemindersForTask
- [ ] T050 [US4] Add background notification refresh: register BGAppRefreshTaskRequest in app launch, handler calls NotificationService.rescheduleAllReminders to top up notification slots; also reschedule on scenePhase change to .active
- [x] T051 [US4] Request notification permission on first task reminder creation: if permission not yet granted, show system prompt via NotificationService.requestPermission before scheduling

**Checkpoint**: Multiple reminders per task work, notifications fire at correct times, deep linking to task works

---

## Phase 7: User Story 5 — Complete Recurring Tasks (Priority: P3)

**Goal**: Completing a recurring task advances its due date to the next occurrence and resets status to "Not Started" instead of marking done.

**Independent Test**: Create weekly recurring task due today → mark complete → verify due date advances 7 days and status resets in app and Notion.

### Implementation

- [x] T052 [US5] Add due date advancement logic to `Recurrence` enum in `Enums.swift`: method `nextDueDate(from: Date) -> Date` that computes: daily +1 day, weekly +7 days, monthly +1 month (Calendar.date(byAdding: .month)), yearly +1 year — if result is still in past, advance again until future date
- [x] T053 [US5] Update task completion in `TaskRowView.swift` and `TaskDetailView.swift`: check task.recurrence — if != .none: set dueDate to recurrence.nextDueDate(from: dueDate), set status to .notStarted, set isDirty=true; if == .none: set status to .done, set isDirty=true
- [x] T054 [US5] Update SyncService.pushDirtyChanges to correctly push both status reset and new due date for recurring tasks in a single PATCH call to Notion
- [x] T055 [US5] After recurring task completion, call NotificationService.rescheduleAllReminders to reschedule reminders relative to the new due date

**Checkpoint**: Recurring tasks cycle correctly in both app and Notion, no duplicate rows

---

## Phase 8: User Story 6 — Notion Database Schema Validation (Priority: P3)

**Goal**: App validates Notion database schemas on connection and shows actionable errors for missing properties. Setup guide accessible from Settings.

**Independent Test**: Connect a database missing "Status" property → verify app shows specific error naming the missing property.

### Implementation

- [x] T056 [US6] Create `Finally/Services/SchemaValidator.swift` with: validateTasksDatabase (retrieve database → check for title property, status property, date property → for optional: check select for Priority, multi_select for Tags, relation for Project, select for Recurrence) and validateProjectsDatabase (check for title property) — returns ValidationResult with list of missing/mismatched properties and suggestions
- [x] T057 [US6] Create `Finally/Views/Onboarding/DatabasePickerView.swift` — after OAuth success, list all databases the user shared with the integration, let user select which is "Tasks" and which is "Projects", then run SchemaValidator
- [x] T058 [US6] Create `Finally/Views/Onboarding/SchemaErrorView.swift` — display validation errors as a clear list: each missing property shows name, expected type, and instructions to add it in Notion (e.g., "Add a Status property with options: Not Started, In Progress, Done")
- [x] T059 [US6] Handle property name ambiguity in SchemaValidator: when multiple date properties exist, present a picker letting the user choose which is "Due Date"; store mappings in UserSession.propertyMappings
- [x] T060 [US6] Create `Finally/Views/Settings/DatabaseSetupGuideView.swift` — static guide showing minimum required schema tables for Tasks and Projects databases per quickstart.md, accessible from Settings
- [x] T061 [US6] Wire database selection into the onboarding flow: NotionConnectView → (OAuth) → DatabasePickerView → (validate) → SchemaErrorView or main ContentView

**Checkpoint**: Schema validation catches missing properties with actionable messages, property mapping works

---

## Phase 9: User Story 7 — Dark Mode / Light Mode (Priority: P3)

**Goal**: App follows iOS system appearance by default with in-app override (System/Light/Dark).

**Independent Test**: Toggle iOS system appearance → app updates. Override to "Light" in Settings → app stays light regardless of system.

### Implementation

- [x] T062 [US7] Create `Finally/Views/Settings/AppearanceSettingView.swift` — picker with three options: System, Light, Dark — stored in @AppStorage("appearanceMode") as Int (0=system, 1=light, 2=dark)
- [x] T063 [US7] Apply appearance override in FinallyApp.swift: read @AppStorage("appearanceMode"), apply .preferredColorScheme(.light/.dark/nil) on the root view based on selection
- [x] T064 [US7] Create `Finally/Views/Settings/SettingsView.swift` — settings screen with sections: Appearance (link to AppearanceSettingView), Database (link to DatabaseSetupGuideView), Account (connected workspace name, disconnect button that clears Keychain + UserSession)

**Checkpoint**: Dark/light mode follows system or user override, Settings screen complete

---

## Phase 10: User Story 8 — Home Screen Widgets (Priority: P3)

**Goal**: Home screen widgets in small/medium/large showing task list with interactive checkboxes and "+" button.

**Independent Test**: Add each widget size to home screen → verify tasks display with checkboxes → tap checkbox completes task → tap "+" opens app to task creation.

### Implementation

- [ ] T065 [US8] Create `FinallyWidget/ToggleTaskCompleteIntent.swift` — AppIntent with taskID String parameter, perform() reads shared SwiftData container, toggles task completion (respecting recurrence logic from Enums.swift), calls SyncService equivalent to push to Notion
- [x] T066 [US8] Create `FinallyWidget/TaskListWidget.swift` — Widget definition with WidgetConfiguration supporting .systemSmall/.systemMedium/.systemLarge families, TimelineProvider that reads tasks from shared SwiftData container sorted by dueDate (non-done, nearest first), generates timeline entries with .atEnd policy
- [x] T067 [P] [US8] Create `FinallyWidget/WidgetViews.swift` — three layout views: SmallWidgetView (3-4 tasks, checkbox Toggle with ToggleTaskCompleteIntent, task title truncated, "+" Link bottom-right), MediumWidgetView (4-6 tasks with checkbox + title + due date, "+" Link bottom-right), LargeWidgetView (8-10 tasks with checkbox + title + due date + priority color dot, "+" Link bottom-right) — all with empty state message when no tasks
- [ ] T068 [US8] Add WidgetCenter.shared.reloadTimelines(ofKind: "TaskListWidget") calls in SyncService after every data change, in task completion, and in task creation
- [ ] T069 [US8] Move shared model and enum files to a Shared framework or ensure both targets can access TaskItem, ProjectItem, Enums, and Constants via target membership

**Checkpoint**: All three widget sizes display tasks, checkboxes work, "+" button opens app

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: Offline handling, error states, performance, and final wiring

- [x] T070 Implement offline indicator: detect network reachability via NWPathMonitor in a NetworkService, show a subtle banner when offline across all views, disable push operations when offline (queue via isDirty flag)
- [x] T071 Add pull-to-refresh (.refreshable) to all tab views (InboxView, TodayView, UpcomingView, BrowseProjectsView) triggering SyncService.syncOnLaunch
- [x] T072 [P] Add haptic feedback (UIImpactFeedbackGenerator) on task completion checkbox tap
- [x] T073 [P] Add task completion animation in TaskRowView: strikethrough + fade opacity on checkbox toggle
- [x] T074 Implement periodic foreground sync: Timer in FinallyApp that triggers incremental sync every 90 seconds while scenePhase == .active
- [ ] T075 Deploy Vercel function: configure environment variables NOTION_CLIENT_ID and NOTION_CLIENT_SECRET, deploy vercel-notion-auth/, update Constants.swift with production Vercel URL
- [ ] T076 Final integration test: run through complete flow — OAuth → database selection → schema validation → view tasks → create task → set reminders → complete recurring task → verify widget updates

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1
- **Phase 3 (US1 - OAuth)**: Depends on Phase 2 — BLOCKS US2 (need auth to fetch data)
- **Phase 4 (US2 - Views)**: Depends on Phase 3 (needs working Notion connection)
- **Phase 5 (US3 - Create/Edit)**: Depends on Phase 4 (needs views to place inline creator)
- **Phase 6 (US4 - Reminders)**: Depends on Phase 5 (needs task detail view)
- **Phase 7 (US5 - Recurring)**: Depends on Phase 5 (needs task completion logic)
- **Phase 8 (US6 - Schema Validation)**: Can start after Phase 3 (only needs OAuth + API client)
- **Phase 9 (US7 - Dark Mode)**: Can start after Phase 2 (only needs app shell)
- **Phase 10 (US8 - Widgets)**: Depends on Phase 5 (needs data model + completion logic)
- **Phase 11 (Polish)**: Depends on all desired user stories

### Parallel Opportunities

After Phase 5 (Create/Edit) completes, these can run in parallel:
- Phase 6 (US4 - Reminders)
- Phase 7 (US5 - Recurring)
- Phase 10 (US8 - Widgets)

Phase 8 (US6 - Schema Validation) can run in parallel with Phase 4/5.
Phase 9 (US7 - Dark Mode) can run in parallel with anything after Phase 2.

### Within Each Phase

- Models before services
- Services before views
- Parallel [P] tasks can run simultaneously

---

## Parallel Example: Phase 2 (Foundational)

```
# These can run in parallel (different files):
T014: KeychainHelper.swift
T015: NotionAPIService.swift

# Then sequentially:
T016: NavigationRouter.swift (depends on Constants)
T017: App entry point (depends on ModelContainer + Router)
```

## Parallel Example: Phase 5 (US3 - Create/Edit)

```
# All component pickers in parallel (separate files):
T034: ChipView.swift
T035: DatePickerSheet.swift
T036: PriorityPicker.swift
T037: TagPicker.swift
T038: ProjectPicker.swift
T039: RecurrencePicker.swift

# Then sequentially (depends on components):
T040: InlineTaskCreator.swift
T041: TaskDetailView.swift
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: US1 (OAuth) — can now connect to Notion
4. Complete Phase 4: US2 (Views) — can now see tasks
5. **STOP and VALIDATE**: App connects to Notion and displays tasks in Todoist-style views

### Incremental Delivery

1. Setup + Foundational → Project builds and runs
2. Add US1 (OAuth) → Can authenticate with Notion
3. Add US2 (Views) → Can view tasks (MVP!)
4. Add US3 (Create/Edit) → Full task management
5. Add US4 (Reminders) → Differentiating feature
6. Add US5 (Recurring) → Power user feature
7. Add US6 (Schema Validation) → Better onboarding
8. Add US7 (Dark Mode) → Polish
9. Add US8 (Widgets) → Platform integration
10. Polish → Production ready

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- Commit after each task or logical group
- Stop at any checkpoint to validate independently
- Total tasks: 76
- Tasks per story: Setup=7, Foundation=10, US1=6, US2=10, US3=11, US4=7, US5=4, US6=6, US7=3, US8=5, Polish=7
