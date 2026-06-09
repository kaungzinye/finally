# Feature Specification: Finally — Notion Task App with Reminders

**Feature Branch**: `001-notion-task-app`
**Created**: 2026-03-13
**Updated**: 2026-03-18
**Status**: In Progress — Parts A–H shipped; Part I (Notion Platform 2026) planned
**Input**: User description: "Build a SwiftUI iOS app called Finally that connects to Notion via OAuth, reads from Tasks and Projects databases, has Todoist-like UI with inline task creation and chip-based fields, per-task custom staggered local push notifications, recurring task support, dark/light mode following system settings, and Notion database schema validation. iPhone-only, iOS 17+"

## Shipped Parts

| Part | Description | Status |
|------|-------------|--------|
| A | Data model, OAuth, Keychain, SwiftData schema | ✅ Done |
| B | Notion sync (full + incremental), schema validation | ✅ Done |
| C | Task list views (Today, Upcoming, Inbox, Browse), tab bar | ✅ Done |
| D | Kanban board with drag-and-drop between status columns | ✅ Done |
| E | Inline task creation, chip-based fields, NLP parsing | ✅ Done |
| F | Task detail view, editing, recurring task completion | ✅ Done |
| G | Reminders (local push notifications), widget extension | ✅ Done |
| H | Sync bug fixes (5 bugs) + E2E Notion tests | ✅ Done |
| I | Notion Platform 2026: webhooks, Workers, Markdown body, any-member OAuth | 🔲 Planned |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Connect Notion Account via OAuth (Priority: P1)

A user opens the app for the first time and connects their Notion workspace. They are guided through the Notion OAuth consent screen where they select the databases (Tasks and Projects) to share with the app. Upon return to the app, they see their tasks populated from Notion.

**Why this priority**: Without Notion connectivity, no other feature works. This is the foundation for all data access.

**Independent Test**: Can be fully tested by launching the app, tapping "Connect Notion", completing OAuth, and verifying tasks appear. Delivers value by establishing the data connection.

**Acceptance Scenarios**:

1. **Given** the user has not connected Notion, **When** they tap "Connect to Notion", **Then** the Notion OAuth consent screen opens in an in-app browser, showing the app's requested permissions.
2. **Given** the user completes OAuth consent, **When** they return to the app, **Then** the app stores the access token securely and begins syncing data from their selected databases.
3. **Given** the user has connected Notion, **When** they reopen the app, **Then** they are automatically authenticated without re-doing OAuth (token persists until revoked).
4. **Given** the user grants access to databases that lack required properties, **When** the app validates the schema, **Then** the app displays a clear error identifying which properties are missing and how to add them.

---

### User Story 2 - View Tasks in Todoist-style + Board Views (Priority: P1)

A user sees their Notion tasks organized in familiar views: Inbox (tasks with no project or assigned to the Inbox project), Today (tasks due today + overdue), Upcoming (tasks grouped by date into the future), and a Board view (Kanban-style columns by status). They can tap into any Project to see its tasks. Navigation uses a bottom tab bar.

**Why this priority**: The core value proposition — seeing your Notion tasks in a clean, actionable mobile interface. Co-equal with OAuth since the app is useless without either.

**Independent Test**: Can be tested by connecting Notion and verifying tasks appear correctly grouped in each view. Delivers value by providing organized, at-a-glance task visibility.

**Acceptance Scenarios**:

1. **Given** the user has synced tasks, **When** they open the Today tab, **Then** they see overdue tasks in a separate section at the top, followed by tasks due today, sorted by the active sort configuration (e.g., priority, date, project).
2. **Given** the user has synced tasks, **When** they open the Upcoming tab, **Then** they see tasks grouped under date headers scrolling into the future.
3. **Given** the user taps a project in the Browse tab, **When** the project view loads, **Then** they see only tasks linked to that project.
4. **Given** the user has tasks with no project relation (or project set to "Inbox"), **When** they open the Inbox tab, **Then** those tasks appear here.
5. **Given** the user opens the Board tab, **When** it loads, **Then** they see three columns "To Do", "In Progress", and "Done" with counts and task cards for each status.
6. **Given** the user drags a task card from one column to another on the Board view, **When** they drop it, **Then** the task’s status updates immediately and this change syncs back to Notion.
7. **Given** the user pulls down on any task list, **When** the refresh completes, **Then** the latest data from Notion is displayed.

---

### User Story 3 - Add and Edit Tasks Inline (Priority: P2)

A user adds or edits a task using an inline task creation bar at the bottom of any task list (Todoist-style). The planning model uses two dates: a required primary `dueDate` and an optional secondary `targetDate`. `dueDate` is the real deadline. `targetDate` is the earlier planning date the user aims for and also absorbs the practical scheduling role the old start-date concept would have served. Both dates sync to Notion, with `dueDate` treated as primary in the UI and `targetDate` as secondary. The user can also manage subtasks that mirror Notion subtasks as real child pages. Chosen values appear as tappable chips.

**Why this priority**: Creating and editing tasks from mobile is essential for a task manager, but viewing existing tasks (P1) provides standalone value first.

**Independent Test**: Can be tested by tapping "+", entering a task name, setting fields via chips, and verifying the task appears in Notion and in the app's list.

**Acceptance Scenarios**:

1. **Given** the user is on any task list, **When** they tap the "+" button, **Then** an inline text field appears with a quick-action bar showing `dueDate` first, followed by priority, tags, project, and recurrence, then `targetDate`.
2. **Given** the user sets a hard deadline, **When** they choose a due date, **Then** that date is stored as the official `dueDate` and synced to Notion as the primary task date.
3. **Given** the user also wants a planned earlier date, **When** they choose a target date, **Then** that date is stored as `targetDate`, must remain earlier than `dueDate`, and syncs to Notion as the secondary task-planning date.
4. **Given** the user taps the priority icon, **When** they select a priority level (Urgent/High/Medium/Low), **Then** a colored chip appears (Urgent=red, High=orange, Medium=blue, Low=no color).
5. **Given** the user taps the tags icon, **When** they select one or more tags from the multi-select picker, **Then** tag chips appear. The picker shows existing tags from the Notion database.
6. **Given** the user taps the project icon, **When** they select a project, **Then** a project chip appears. Default is "Inbox" if unselected.
7. **Given** the user taps the recurrence icon, **When** they select a recurrence pattern (Daily/Weekly/Monthly/Yearly/Custom), **Then** a recurrence chip appears.
8. **Given** the user submits the task, **When** creation succeeds, **Then** the task appears in the appropriate view and is created as a page in the Notion Tasks database with `Due` and optional `Target` synced to Notion, with `dueDate` treated as the primary UI date.
9. **Given** the user has subtasks, **When** they add or edit them, **Then** each subtask is synced as a real page in the same Notion Tasks database using the same parent-child structure the user sees in Notion.
10. **Given** the app detects legacy local-only subtasks from the old model, **When** it prepares to migrate them, **Then** it asks for explicit user confirmation before promoting them into real Notion pages.

---

### User Story 4 - Set Custom Staggered Reminders per Task (Priority: P2)

A user sets multiple reminders for a task using two reminder kinds: anchored reminders and explicit-date reminders. Anchored reminders are stored locally as `(anchor, value, unit, direction)` where `anchor` is either `due` or `target`; `unit` is one of minutes, hours, days, weeks, or months; and `direction` is `before` or `after`. Explicit-date reminders are stored as a direct date/time and do not require an anchor. Reminders are delivered as local push notifications even when the app is not open.

**Why this priority**: Reminders are the differentiating feature (it's in the app name). But it depends on tasks existing (P1) and being editable (P2 task creation).

**Independent Test**: Can be tested by setting 2-3 reminders on a task with a near-future due date and verifying notifications arrive at the correct times.

**Acceptance Scenarios**:

1. **Given** the user opens the task detail and taps "Reminders", **When** the reminder UI appears, **Then** anchored reminders default the selected anchor to `due`.
2. **Given** the task has a `targetDate`, **When** the reminder UI appears, **Then** `target` is shown as an optional secondary anchor alongside `due`.
3. **Given** the task does not yet have a `dueDate`, **When** the user opens the reminder UI, **Then** anchored reminders are disabled because there is no valid anchor, but explicit-date reminders remain available.
4. **Given** the user taps "Add Reminder", **When** they configure a reminder such as `(target, 1, weeks, before)` or `(due, 2, days, after)`, **Then** that reminder is stored locally as an anchored reminder rather than as a pre-baked preset type.
5. **Given** the user chooses a quick preset like "1 week before target", **When** they save it, **Then** the app generates the equivalent anchored reminder under the hood.
6. **Given** the user chooses "Exact date", **When** they pick a specific date and time, **Then** that reminder is stored as an explicit-date reminder with no anchor.
7. **Given** the user enters an offset value, **When** the selected unit is minutes, hours, days, weeks, or months, **Then** the app enforces these bounds respectively: `1–59`, `1–23`, `1–30`, `1–51`, and `1–11`.
8. **Given** a reminder is anchored to `target`, **When** the task's target date changes, **Then** the reminder is rescheduled relative to the new target date.
9. **Given** a reminder is anchored to `due`, **When** the due date changes, **Then** the reminder is rescheduled relative to the due date.
10. **Given** a reminder is anchored to `due` with direction `after`, **When** the due date passes, **Then** the reminder can be used for follow-up nudges after the deadline.
11. **Given** a task has an explicit-date reminder, **When** the due date or target date changes, **Then** that reminder keeps its chosen date/time because it is not anchor-derived.
12. **Given** a subtask has reminder offsets, **When** the parent task's reminders change, **Then** the subtask reminders remain independent and unchanged.
13. **Given** the app is not running in the foreground, **When** a reminder time arrives, **Then** the user receives a push notification showing the task name and deadline context.
14. **Given** the user taps a notification, **When** the app opens, **Then** it navigates directly to the relevant task's detail view.
15. **Given** the user marks a task as done, **When** the task completes, **Then** all pending reminders for that task are cancelled.

---

### User Story 5 - Complete Recurring Tasks (Priority: P3)

A user marks a recurring task as complete. The app creates a new logical cycle in its planning model, while Notion continues to use the same persisted task page and the same persisted subtask pages. The recurrence rule determines the next cycle's `dueDate`, and the optional `targetDate` plus anchored reminders are re-applied to that next cycle.

**Why this priority**: Recurring tasks are a natural extension once basic task management works. P3 because it's not needed for first-use value.

**Independent Test**: Can be tested by creating a weekly recurring task due today, marking it complete, and verifying the due date advances by 7 days and status resets to "Not Started" in both the app and Notion.

**Acceptance Scenarios**:

1. **Given** a task with recurrence set to "Weekly" and due date of March 13, **When** the user marks it complete, **Then** the task's due date updates to March 20 and status resets to "Not Started" in Notion.
2. **Given** a task with recurrence set to "Monthly" and due date of March 15, **When** the user marks it complete, **Then** the due date updates to April 15.
3. **Given** a task with recurrence set to "Yearly", **When** the user marks it complete, **Then** the due date advances by one year.
4. **Given** a task with recurrence set to "Daily", **When** the user marks it complete, **Then** the due date advances to tomorrow.
5. **Given** a task with a custom recurrence rule, **When** the user marks it complete, **Then** the due date advances according to that rule and status resets to "Not Started".
6. **Given** a recurring task with both `dueDate` and `targetDate`, **When** the task rolls into its next cycle, **Then** the target date is recalculated or copied forward according to the recurrence rule so it stays meaningfully earlier than the new due date.
7. **Given** a recurring task with anchored reminders, **When** the task rolls into its next cycle, **Then** the same reminders are re-applied to the new cycle using their explicit anchors instead of being shared as already-fired reminders.
8. **Given** a recurring task with subtasks, **When** the task rolls into its next cycle, **Then** the existing subtask pages persist in Notion and their status resets for the new cycle rather than creating duplicate subtask pages.
9. **Given** a task with no recurrence, **When** the user marks it complete, **Then** the status changes to "Done" and no date change occurs.

---

### User Story 6 - Notion Database Schema Validation and Setup Guide (Priority: P3)

When a user connects their Notion databases, the app validates that the Tasks and Projects databases have the required properties. If properties are missing, the app shows a clear, actionable error screen listing what's needed. A setup guide (accessible from Settings) explains the minimum database requirements.

**Why this priority**: Important for onboarding and error prevention, but most users with existing Notion task databases will already have compatible schemas.

**Independent Test**: Can be tested by connecting a Notion database that is missing the "Status" property and verifying the app shows a specific error message naming the missing property.

**Acceptance Scenarios**:

1. **Given** the user connects a Tasks database missing a `status` type property, **When** the app validates the schema, **Then** the app displays: "Your Tasks database is missing a Status property (type: status). Please add one with options: Not Started, In Progress, Done."
2. **Given** the user connects a Tasks database with all required properties, **When** the app validates the schema, **Then** the app proceeds to sync without errors.
3. **Given** the user connects databases where property names differ from defaults (e.g., "Task Name" instead of "Name"), **When** the app validates, **Then** it detects properties by type rather than exact name, and allows the user to map properties if ambiguous (e.g., multiple date fields — which one is "due date"?).
4. **Given** the user opens Settings > "Database Setup Guide", **When** the guide loads, **Then** it shows the minimum required schema for both Tasks and Projects databases.

---

### User Story 7 - Dark Mode / Light Mode (Priority: P3)

The app follows the user's iOS system appearance setting (light or dark mode) by default. A Settings screen also allows the user to override this with a forced light or dark preference.

**Why this priority**: Standard iOS expectation but not a blocker for core functionality.

**Independent Test**: Can be tested by toggling iOS system appearance in Settings and verifying the app updates immediately.

**Acceptance Scenarios**:

1. **Given** the user's iPhone is set to dark mode, **When** they open the app with the default "System" appearance setting, **Then** the app renders in dark mode.
2. **Given** the user overrides appearance to "Light" in the app's Settings, **When** they are in a dark mode system, **Then** the app stays in light mode.
3. **Given** the user changes their iOS system appearance while the app is open, **When** the app appearance setting is "System", **Then** the app transitions to the new appearance immediately.

---

### User Story 8 - Home Screen Widgets (Priority: P3)

The user adds a home screen widget showing a list of upcoming tasks with checkboxes to complete them directly from the widget. A "+" button in the bottom-right corner opens the app to create a new task. Widgets are available in all three iOS sizes: small, medium, and large.

**Why this priority**: Widgets provide at-a-glance task visibility without opening the app, but the core app must work first.

**Independent Test**: Can be tested by adding each widget size to the home screen and verifying tasks display with tappable checkboxes and the "+" button opens the app's task creation flow.

**Acceptance Scenarios**:

1. **Given** the user adds the small widget, **When** it renders, **Then** it shows a compact list of the nearest due tasks (as many as fit) with a checkbox next to each, and a "+" button in the bottom-right corner.
2. **Given** the user adds the medium widget, **When** it renders, **Then** it shows more tasks in a wider layout with task name, checkbox, and due date visible, plus a "+" button in the bottom-right corner.
3. **Given** the user adds the large widget, **When** it renders, **Then** it shows an extended list of tasks with checkboxes, task names, due dates, and priority colors, plus a "+" button in the bottom-right corner.
4. **Given** the user taps a checkbox on a widget task, **When** the task completes, **Then** the task is marked as done in Notion (or due date advances if recurring) and the widget refreshes.
5. **Given** the user taps the "+" button on any widget, **When** the app opens, **Then** it navigates directly to the inline task creation flow.
6. **Given** the user has no tasks, **When** the widget renders, **Then** it shows an empty state message and the "+" button.

---

### Edge Cases

- What happens when the user's Notion token is revoked externally? The app detects 401 responses and prompts re-authentication with a clear message.
- What happens when a reminder offset resolves to a time in the past? That reminder is skipped rather than scheduled immediately.
- What happens when a task's due date is in the past and has reminders? Reminders for past times are not scheduled; only future reminders are queued.
- What happens when a user configures a target date that lands on or after the due date? The app rejects it; `targetDate` must always be strictly earlier than `dueDate`.
- What happens when a task has no target date? Target-anchored reminders are unavailable, but due-anchored reminders still work.
- What happens when a parent task has no target date? Subtask suggested dates default to working backward from `dueDate`, one slot per subtask index.
- What happens when the user has more than 100 tasks (Notion API pagination limit)? The app paginates through all results using cursor-based pagination.
- What happens when the user has no internet connection? The app shows cached data with a clear offline indicator and queues changes for sync when connectivity returns.
- What happens when a recurring task's due date is already past when completed? The due date advances to the next future occurrence (skipping past dates).
- What happens when the Notion API rate limit is hit? The app respects rate limit headers and shows a non-blocking "Syncing..." indicator.
- What happens when iOS revokes notification permissions? The app detects this and shows a prompt in Settings to re-enable notifications, with a deep link to iOS Settings.
- What happens when there are more than 64 scheduled local notifications (iOS limit)? The app prioritizes notifications for the soonest tasks and re-schedules as earlier notifications fire.
- What happens when the app finds legacy local-only subtasks from the current implementation? It offers a one-time, user-confirmed migration into real Notion child pages instead of silently promoting them.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST authenticate users via Notion OAuth (public integration flow) and securely store the access token.
- **FR-002**: System MUST validate connected Notion databases against a minimum required schema (Tasks: title + status + date properties; Projects: title property).
- **FR-003**: System MUST detect database properties by type (not just name) and allow user mapping when multiple properties of the same type exist.
- **FR-004**: System MUST display tasks in primary views: Inbox, Today (due today + overdue), Upcoming (grouped by date), Board (Kanban by status), and per-Project views.
- **FR-005**: System MUST provide a bottom tab bar with tabs for: Inbox, Today, Upcoming, Board, Search/Filters, and Browse (projects list).
- **FR-006**: System MUST support inline task creation with a quick-action bar containing buttons for: start date, due date / deadline, target date, priority, tags, project, and recurrence.
- **FR-007**: System MUST display selected task field values as tappable colored chips (not traditional form fields).
- **FR-008**: Users MUST be able to create, edit, and complete tasks, with all changes synced to the Notion Tasks database.
- **FR-009**: System MUST support two local reminder kinds: anchored reminders stored as `(anchor, value, unit, direction)` and explicit-date reminders stored as a direct date/time.
- **FR-010**: System MUST cancel pending reminders when a task is completed or deleted, and reschedule reminders when a task's due date or target date changes.
- **FR-011**: System MUST handle recurring tasks by updating the existing task's due date to the next occurrence (based on Daily/Weekly/Monthly/Yearly/Custom pattern) and resetting status to "Not Started" upon completion — no new rows created.
- **FR-012**: System MUST follow the iOS system appearance setting (light/dark mode) by default, with an in-app override option (System/Light/Dark).
- **FR-013**: System MUST support swipe gestures on tasks: swipe right to complete, swipe left for more actions (reschedule, delete), and multi-select bulk actions (complete/delete) in list-based views.
- **FR-014**: System MUST paginate through all Notion API results using cursor-based pagination.
- **FR-015**: System MUST handle offline state gracefully by displaying cached data and showing an offline indicator.
- **FR-016**: System MUST respect the iOS 64 scheduled notification limit by prioritizing nearest due tasks and re-scheduling as slots become available.
- **FR-017**: System MUST provide a "Database Setup Guide" accessible from Settings explaining the minimum Notion database requirements.
- **FR-018**: System MUST support pull-to-refresh on all task list views.
- **FR-019**: System MUST navigate to the relevant task detail view when a notification is tapped.
- **FR-020**: System MUST support iOS 17 and later, iPhone-only.
- **FR-021**: Reminder metadata MUST be stored locally on-device as JSON since Notion has no native reminder fields for these concepts.
- **FR-022**: System MUST display task priority using color coding: Urgent=red, High=orange, Medium=blue, Low=default/no color.
- **FR-023**: System MUST provide home screen widgets in all three iOS sizes (small, medium, large) showing a list of upcoming tasks with checkboxes to complete tasks directly from the widget.
- **FR-024**: All widget sizes MUST include a "+" button in the bottom-right corner that opens the app to the task creation flow.
- **FR-025**: Widget task completion MUST sync to Notion (marking done or advancing recurring task due date) and trigger a widget refresh.
- **FR-026**: System MUST support parent tasks and subtasks, where app subtasks mirror Notion subtasks as real Notion pages in the same Tasks database linked via the native parent-child relation.
- **FR-027**: System MUST hide parent tasks from Today-style list views when they have incomplete subtasks, surfacing actionable subtasks instead.
- **FR-028**: System MUST treat `dueDate` as the primary task date and `targetDate` as a secondary planning date in all UI.
- **FR-029**: The task planning layer MUST support a required primary `dueDate` and an optional secondary `targetDate`.
- **FR-030**: `targetDate`, when present, MUST always be earlier than `dueDate`.
- **FR-031**: Reminder quick presets such as "1 week before target" MUST be convenience constructors that create anchored reminder entries under the hood; they MUST NOT be stored as a separate reminder type.
- **FR-032**: `ReminderOffset.unit` MUST be restricted to `minutes`, `hours`, `days`, `weeks`, or `months`. `years` is out of scope; month-based offsets are used instead.
- **FR-033**: `ReminderOffset` bounds MUST be enforced as follows: `minutes 1–59`, `hours 1–23`, `days 1–30`, `weeks 1–51`, `months 1–11`.
- **FR-034**: Reminder anchors MUST be explicit: `target` or `due`. The system MUST NOT infer the anchor implicitly from whether a target date exists.
- **FR-035**: Subtasks MUST retain local-only metadata for at least: `sortIndex`, `suggestedDateOverride`, and reminder JSON.
- **FR-036**: When the app migrates legacy local-only subtasks from the current model, it MUST ask for explicit user confirmation before creating Notion child pages.
- **FR-037**: The system MUST compute default subtask suggested dates from the parent planning window: if parent has a `targetDate`, subtasks default to working backward from `targetDate`; otherwise they default to working backward from `dueDate` by subtask order.
- **FR-038**: Recurrence and reminders MUST remain separate concerns: recurrence defines when the next cycle happens; reminder offsets define when notifications fire for that cycle.
- **FR-039**: For recurring tasks, `targetDate` MUST roll forward coherently with the new `dueDate` so the planning gap between them remains meaningful.
- **FR-040**: The sync layer MUST map `targetDate` to a secondary Notion date field and `dueDate` to the primary Notion `Due` field.
- **FR-041**: Recurring subtasks MUST persist as the same Notion pages and reset their state for each cycle rather than creating duplicate child pages for every recurrence.
- **FR-042**: The reminder UI MUST default the selected anchor to `due`.
- **FR-043**: The reminder UI MUST only show `target` as an available anchor when the task has a `targetDate`.
- **FR-044**: When a task has no `dueDate`, anchored reminders MUST be disabled, but explicit-date reminders MAY still be created.
- **FR-045**: Explicit-date reminders MUST remain fixed at their chosen date/time and MUST NOT be rescheduled when `dueDate` or `targetDate` changes.

### Three-Layer Model

- **Layer 1: Task Planning**: required `dueDate` and optional `targetDate`
- **Layer 2: Reminders**: anchored reminders plus explicit-date reminders
- **Layer 3: Sync**: Notion `Due`, Notion `Target`, plus local reminder metadata

### Key Entities

- **Task**: A unit of work synced from Notion. Key attributes: name (title), status (Not Started / In Progress / Done), required primary `dueDate`, optional secondary `targetDate`, priority (Urgent / High / Medium / Low), tags, project, recurrence pattern (None / Daily / Weekly / Monthly / Yearly / Custom), local reminder JSON, parent/child relationships for subtasks, and local subtask ordering metadata.
- **Project**: A grouping of tasks, synced from Notion. Key attributes: name (title). A virtual "Inbox" project exists for unassigned tasks.
- **ReminderOffset**: A local-only reminder descriptor stored on a task. Key attributes: `anchor`, `value`, `unit`, `direction`. It resolves to a scheduled notification time relative to `targetDate` or `dueDate`.
- **Subtask**: A task that is also a real Notion child page. Key attributes: parent task relation, local `sortIndex`, computed or overridden suggested date, independent reminder metadata, and normal task fields like status and due date.
- **User Session**: The authenticated connection to Notion. Key attributes: access token, workspace info, selected database IDs, property mappings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can connect their Notion workspace and see their tasks within 60 seconds of first app launch.
- **SC-002**: Users can create a new task with name, due date, priority, and project in under 15 seconds using the inline creation flow.
- **SC-003**: 100% of scheduled reminders are delivered at the correct time (within 1-minute tolerance of the resolved anchor time or fixed explicit date/time), where reminders are measured from explicit `target` or `due` anchors or from their exact chosen timestamp.
- **SC-004**: Recurring task completion updates the due date in Notion within 5 seconds of marking complete, carries the target date forward coherently, and does not create duplicate subtask pages.
- **SC-005**: The app correctly identifies and reports missing database properties for at least 95% of common Notion task database configurations.
- **SC-006**: The app displays correctly in both light and dark mode, matching the user's system preference with zero manual configuration.
- **SC-007**: All task views (Inbox, Today, Upcoming, Project) load within 3 seconds on a standard network connection.
- **SC-008**: The app supports at least 500 tasks across all views without noticeable performance degradation.

## Assumptions

- **A-001**: The app will be distributed as a Notion public integration, requiring the full OAuth flow (not internal integration tokens).
- **A-002**: Notion access tokens do not expire; the app does not need a refresh token flow. It handles revocation by detecting 401 responses.
- **A-003**: Reminder metadata is stored on-device only; `targetDate` itself is synced as a secondary Notion date field.
- **A-004**: The "Inbox" project is a virtual concept — tasks without a project relation (or with a project named "Inbox") are grouped here. The app does not create an "Inbox" project in Notion.
- **A-005**: The app targets iPhone-only. Mac Catalyst compatibility is a future consideration, not in scope for this spec.
- **A-006**: The minimum deployment target is iOS 17.
- **A-007**: The Apple Developer Team ID is GN4UMU6766 and bundle identifier follows the pattern com.kaungzinye.finally.
- **A-008**: The Notion API version used is 2022-06-28 or the latest stable version at time of development.
- **A-009**: ~~Natural language parsing for task input (e.g., "buy groceries tomorrow p1") is a nice-to-have, not required for MVP.~~ **Implemented**: `TaskTitleParser` extracts due dates, priority (p1–p4 / urgent/high/medium/low), @project mentions, and #tag mentions from inline task input. The inline creator auto-populates chips and the clean title strips detected tokens on submit.
- **A-010**: The token exchange step of OAuth requires a server-side component (to protect the client_secret). This will be handled via a lightweight backend or serverless function.
- **A-011**: The Tasks database includes a self-relation or native parent-child field that can represent subtasks as real child pages in the same database, and the app should mirror that Notion hierarchy rather than inventing a parallel subtask system.
- **A-012**: The redesigned reminder model replaces exact absolute-date reminders in the primary UX; legacy absolute reminders, if any, must be migrated or retired explicitly.

## Scope Boundaries

**In Scope**:
- Notion OAuth connection and data sync
- Todoist-style task views (Inbox, Today, Upcoming, Browse/Projects)
- Board view (Kanban) for tasks grouped by status with drag-and-drop between columns
- Inline task creation with chip-based field selection
- Natural language date/priority/@project/#tag parsing in the inline task creator
- Task editing and completion
- Deadline planning with primary `dueDate` and secondary `targetDate`
- Subtasks / nested task hierarchies that mirror Notion subtasks plus local reminder metadata
- Per-task custom staggered local push notifications driven by anchored reminder metadata plus optional explicit-date reminders
- Recurring task due date advancement on completion (including custom recurrence rules)
- Database schema validation with actionable error messages
- Dark/light mode with system preference support
- Setup guide for Notion database requirements
- Home screen widgets (small, medium, large) with task checkboxes and add button
- iPhone-only, iOS 17+

**Out of Scope**:
- iPad-specific layouts or Mac Catalyst optimization
- Notion database creation (user must have existing databases)
- Real-time collaboration or multi-user features
- File attachments or rich text editing in task descriptions
- Reminder sync to Notion (all reminder metadata remains local)
- Calendar grid/month view
- Watch complications
- Offline task creation (offline mode is read-only with cached data)

## Implementation Notes (current-code incompatibilities to resolve)

- **SchemaValidator**: The "Status" property is required by name (case-insensitive). When a database has no "Status"-named property but has another `status`-type property, the validator reports an error rather than silently remapping — users must rename or the validator will flag it.
- **Reminder model redesign**: Current code stores reminders as individual `ReminderItem` records with both interval and explicit-date support. The planned model preserves that product behavior conceptually while allowing storage to evolve toward task-level local reminder metadata.
- **Target-date redesign**: Current code reasons mostly from `dueDate` plus some start-date support. The planned model removes `startDate`, promotes `targetDate` to the optional secondary synced date, and treats `dueDate` as the primary UI date.
- **Subtask migration**: Current code still supports local-only subtasks. The planned model promotes subtasks to real Notion child pages in the Tasks database after an explicit one-time user-confirmed migration, and the app's hierarchy should mirror Notion's hierarchy directly.
- **Sync resilience (Part H)**: Status schema refresh silently falls back to current mappings if `retrieveDatabase` fails, preventing schema-fetch errors from aborting sync. Dirty tasks are never deleted during `fullSync`. Each task is saved individually after a successful push.
- **NLP parsing**: `TaskTitleParser` handles "tomorrow", "next week", "p1"/"urgent", @project mentions, and #tags. Chips auto-populate and the clean title (without detected tokens) is stored on submit.

---

## Part I: Notion Platform 2026 Integration

**Added**: 2026-06-03
**Motivation**: Notion's May 2026 Developer Platform launch introduced four capabilities that directly benefit Finally: (1) Webhooks via Workers for push-based sync, replacing the current 90-second poll timer; (2) Notion Workers as a serverless runtime that can replace the Vercel OAuth relay; (3) the Markdown API for reading task page bodies without traversing block trees; (4) relaxed any-member OAuth that removes the Workspace Owner requirement from onboarding.

---

### User Story 9 — Webhook-Driven Sync (Priority: P2)

Instead of polling Notion every 90 seconds, the app receives real-time change notifications when tasks or projects are modified in Notion. A Notion Worker registers a webhook listener on the user's databases and relays change events to the app via a silent APNs push or a background URL session, triggering an incremental sync only when there is actually something new.

**Why this priority**: The current 90-second foreground timer and BGAppRefreshTask are coarse and battery-wasteful. Webhook-driven sync means changes made in Notion on desktop appear in the app within seconds, which is the core promise of a two-way task manager.

**Independent Test**: Edit a task title directly in Notion → verify the updated title appears in the app within 10 seconds without manually pulling to refresh.

**Acceptance Scenarios**:

1. **Given** the user has connected their Notion workspace, **When** the app sets up sync for the first time, **Then** it deploys a Notion Worker that registers a webhook on the Tasks and Projects databases.
2. **Given** a task is created or updated directly in Notion, **When** the webhook fires, **Then** the Worker delivers a change notification to the app's registered endpoint within 5 seconds.
3. **Given** the app's endpoint receives a webhook payload, **When** the app is in the foreground, **Then** it runs an incremental sync scoped to the changed page IDs and updates the relevant SwiftData records.
4. **Given** the app is in the background, **When** a webhook arrives, **Then** the app processes the change via a background URL session (no APNs dependency) and updates local data; the user sees fresh data when they next open the app.
5. **Given** the webhook endpoint is temporarily unreachable (app uninstalled, endpoint changed), **When** the next foreground sync runs, **Then** the app re-registers the webhook with the current endpoint.
6. **Given** the user is offline, **When** multiple webhook events accumulate, **Then** on reconnect the app performs a single incremental sync rather than replaying each event individually.
7. **Given** the Worker receives a burst of rapid edits to the same task, **When** delivering notifications, **Then** the Worker debounces to at most one delivery per task per 3 seconds to avoid redundant syncs.

---

### User Story 10 — Workers-Hosted OAuth Relay (Priority: P3)

The current `vercel-notion-auth/` serverless function is migrated to a Notion Worker, eliminating the Vercel dependency. The Worker is deployed using the Notion CLI (`ntn workers deploy`) and lives inside the user's Notion workspace context, simplifying credential management and reducing infrastructure surface area.

**Why this priority**: The Vercel function is a pure infrastructure concern. Moving it to Workers doesn't change any user-facing behavior, but it removes an external deployment dependency and aligns with Notion's recommended developer infrastructure. P3 because Vercel continues to work until migrated.

**Independent Test**: Remove Vercel deployment → configure Worker endpoint in Constants.swift → complete full OAuth flow → verify token exchange succeeds via Worker.

**Acceptance Scenarios**:

1. **Given** a Notion Worker is deployed as the token exchange endpoint, **When** the app initiates OAuth and receives the auth code, **Then** it sends the code to the Worker URL instead of the Vercel URL and receives the same `{ access_token, workspace_id, workspace_name, bot_id }` response shape.
2. **Given** the Worker endpoint is configured in `Constants.swift`, **When** the app builds, **Then** the only change visible to the rest of the codebase is the base URL constant — `NotionAuthService` requires no other modifications.
3. **Given** the Worker is deployed, **When** `NOTION_CLIENT_ID` and `NOTION_CLIENT_SECRET` are set as Worker environment variables via `ntn env set`, **Then** no secrets appear in source code or Constants.swift.
4. **Given** the token exchange Worker receives an invalid or expired auth code, **When** it calls the Notion OAuth endpoint, **Then** it returns a structured error response matching the same error contract the Vercel function used, so `NotionAuthService` error handling is unchanged.

---

### User Story 11 — Markdown Body for Task Notes (Priority: P3)

The task detail view gains a read/write notes field backed by the Notion page body, rendered using the Markdown API. Instead of traversing Notion's block tree (which requires multiple API calls for nested content), the app fetches the page body as a Markdown string in a single call and displays it in a lightweight in-app viewer/editor.

**Why this priority**: Many Notion task pages have rich notes in the page body. Currently the app ignores page body content entirely. The Markdown API makes fetching and editing that content straightforward — one GET for read, one PATCH for write.

**Independent Test**: Open a task that has body text in Notion → verify the notes field in TaskDetailView shows the content → edit the notes → verify the updated body appears in Notion.

**Acceptance Scenarios**:

1. **Given** the user opens a task detail view, **When** the task has body content in Notion, **Then** a "Notes" section renders the Markdown content below the task fields.
2. **Given** the user taps "Edit Notes", **When** the editor opens, **Then** it shows the raw Markdown text in an editable `TextEditor`.
3. **Given** the user saves edited notes, **When** the save completes, **Then** the Markdown is written back to the Notion page body via the Markdown API and `isDirty` is cleared.
4. **Given** a task has no body content, **When** the task detail view loads, **Then** the Notes section shows an empty state "Add notes…" placeholder.
5. **Given** the app is offline, **When** the user edits notes, **Then** the edit is cached locally as a dirty markdown string and pushed to Notion on next successful sync.
6. **Given** the Markdown API response includes images or unsupported rich-text blocks, **When** rendered, **Then** those blocks are omitted gracefully (no crash) and a "View in Notion" link is shown.

---

### User Story 12 — Any-Member OAuth (Priority: P2)

Previously, only Notion Workspace Owners could create integrations that appear in the OAuth consent screen. With the any-member OAuth change in the Notion Developer Platform, Finally's public integration is now available to any workspace member. The app updates its onboarding copy and removes the "Workspace Owner required" warning, and validates that the granted permissions match expectations rather than relying on owner-level access assumptions.

**Why this priority**: This is a silent blocking issue for non-owner users that likely causes onboarding drop-off. Removing the friction is high-value, low-effort.

**Independent Test**: Log in with a Notion account that is a Member (not Owner) in a workspace → complete OAuth → verify databases are accessible and tasks sync correctly.

**Acceptance Scenarios**:

1. **Given** the user is a workspace Member (not Owner), **When** they tap "Connect to Notion" and complete OAuth, **Then** the integration connects successfully and the app proceeds to database selection without error.
2. **Given** the onboarding screen previously showed a "Workspace Owner required" note, **When** Part I ships, **Then** that copy is removed or updated to reflect that any workspace member can connect.
3. **Given** a member user selects a database they can read but not write, **When** the app attempts to create or update a task, **Then** the app detects the permission error, shows a clear message ("You don't have edit access to this database"), and disables write operations gracefully rather than failing silently.
4. **Given** the user has access to multiple workspaces, **When** they complete OAuth, **Then** the workspace name shown in Settings reflects the workspace they authorized (unchanged behavior, but verified with non-owner credentials).

---

### Functional Requirements (Part I additions)

- **FR-046**: System MUST register a Notion Worker webhook on the user's Tasks and Projects databases upon first sync setup and re-register if the endpoint becomes stale.
- **FR-047**: The webhook Worker MUST debounce rapid page edits to at most one delivery per page per 3 seconds.
- **FR-048**: Webhook-triggered sync MUST be scoped to changed page IDs only (incremental, not full resync).
- **FR-049**: The OAuth token exchange endpoint MUST be configurable via a single `Constants.swift` value so migration from Vercel to Workers requires no changes beyond that constant.
- **FR-050**: Task notes (Notion page body) MUST be fetched as Markdown via the Markdown API in a single request.
- **FR-051**: Notes edits MUST be stored locally when offline and pushed on next successful sync (same `isDirty` pattern as task fields).
- **FR-052**: The onboarding flow MUST NOT require or assume Workspace Owner status.
- **FR-053**: When a member-level user lacks write permission on a database, the app MUST detect the 403 and show a clear, non-crashing permission error.

---

### Assumptions (Part I)

- **A-013**: Notion Workers supports environment variables for secrets (`NOTION_CLIENT_ID`, `NOTION_CLIENT_SECRET`) configured via `ntn env set`, never committed to source.
- **A-014**: The Markdown API endpoint (`GET /v1/pages/{id}/markdown`) returns the page body as a single Markdown string. The app treats this as opaque text — it does not parse or re-render Notion-specific constructs.
- **A-015**: Webhook delivery from the Worker to the iOS app uses a background `URLSession` `dataTask` with a registered endpoint URL (stored in `UserSession`). APNs is not required for webhook-triggered background sync.
- **A-016**: Notion's any-member OAuth change is backward-compatible; existing owner-authorized sessions continue to work unchanged.
- **A-017**: Workers free beta runs through August 11, 2026, after which Workers consume Notion credits on Business/Enterprise plans. The OAuth relay Worker makes only one outbound call per OAuth session, so credit usage is negligible.

---

### Scope Boundaries (Part I)

**In Scope**:
- Notion Worker for webhook relay (debounced, scoped to changed page IDs)
- Notion Worker replacing the Vercel OAuth token exchange function
- Markdown API read/write for task page body in TaskDetailView
- Removal of Workspace Owner onboarding requirement and copy update
- Graceful 403 handling for member-level write permission errors

**Out of Scope**:
- Notion CLI usage from the iOS app itself (CLI is a developer/deployment tool only)
- External Agents API or Agent SDK (JS/TS only; no Swift bindings)
- Real-time collaborative editing of task notes (single-user editing, last-write-wins)
- Webhook delivery to APNs (background URLSession is sufficient and simpler)
- Workers for any purpose other than OAuth relay and webhook dispatch
