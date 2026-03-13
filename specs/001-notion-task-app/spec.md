# Feature Specification: Finally — Notion Task App with Reminders

**Feature Branch**: `001-notion-task-app`
**Created**: 2026-03-13
**Status**: Draft
**Input**: User description: "Build a SwiftUI iOS app called Finally that connects to Notion via OAuth, reads from Tasks and Projects databases, has Todoist-like UI with inline task creation and chip-based fields, per-task custom staggered local push notifications, recurring task support, dark/light mode following system settings, and Notion database schema validation. iPhone-only, iOS 17+."

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

### User Story 2 - View Tasks in Todoist-style Views (Priority: P1)

A user sees their Notion tasks organized in familiar views: Inbox (tasks with no project or assigned to the Inbox project), Today (tasks due today + overdue), and Upcoming (tasks grouped by date into the future). They can tap into any Project to see its tasks. Navigation uses a bottom tab bar.

**Why this priority**: The core value proposition — seeing your Notion tasks in a clean, actionable mobile interface. Co-equal with OAuth since the app is useless without either.

**Independent Test**: Can be tested by connecting Notion and verifying tasks appear correctly grouped in each view. Delivers value by providing organized, at-a-glance task visibility.

**Acceptance Scenarios**:

1. **Given** the user has synced tasks, **When** they open the Today tab, **Then** they see overdue tasks in a separate section at the top, followed by tasks due today, sorted by priority.
2. **Given** the user has synced tasks, **When** they open the Upcoming tab, **Then** they see tasks grouped under date headers scrolling into the future.
3. **Given** the user taps a project in the Browse tab, **When** the project view loads, **Then** they see only tasks linked to that project.
4. **Given** the user has tasks with no project relation (or project set to "Inbox"), **When** they open the Inbox tab, **Then** those tasks appear here.
5. **Given** the user pulls down on any task list, **When** the refresh completes, **Then** the latest data from Notion is displayed.

---

### User Story 3 - Add and Edit Tasks Inline (Priority: P2)

A user adds a new task using an inline task creation bar at the bottom of any task list (Todoist-style). They type the task name and use quick-action buttons to set due date, priority, tags, project, and recurrence. Chosen values appear as tappable chips. The task is created in the Notion Tasks database.

**Why this priority**: Creating and editing tasks from mobile is essential for a task manager, but viewing existing tasks (P1) provides standalone value first.

**Independent Test**: Can be tested by tapping "+", entering a task name, setting fields via chips, and verifying the task appears in Notion and in the app's list.

**Acceptance Scenarios**:

1. **Given** the user is on any task list, **When** they tap the "+" button, **Then** an inline text field appears with a quick-action bar showing icons for: due date, priority, tags, project, and recurrence.
2. **Given** the user taps the calendar icon, **When** they pick a date, **Then** a chip showing the date appears below the text field. Tapping the chip re-opens the picker.
3. **Given** the user taps the priority icon, **When** they select a priority level (Urgent/High/Medium/Low), **Then** a colored chip appears (Urgent=red, High=orange, Medium=blue, Low=no color).
4. **Given** the user taps the tags icon, **When** they select one or more tags from the multi-select picker, **Then** tag chips appear. The picker shows existing tags from the Notion database.
5. **Given** the user taps the project icon, **When** they select a project, **Then** a project chip appears. Default is "Inbox" if unselected.
6. **Given** the user taps the recurrence icon, **When** they select a recurrence pattern (Daily/Weekly/Monthly/Yearly), **Then** a recurrence chip appears.
7. **Given** the user submits the task, **When** creation succeeds, **Then** the task appears in the appropriate view and is created as a page in the Notion Tasks database with all selected properties.
8. **Given** the user taps an existing task, **When** the detail view opens, **Then** all fields are displayed as tappable rows/chips that can be edited and synced back to Notion.

---

### User Story 4 - Set Custom Staggered Reminders per Task (Priority: P2)

A user sets multiple reminders for a task at custom intervals before its due date. For example, a task due Friday at 5pm might have reminders at 1 day before, 2 hours before, and 30 minutes before. Reminders are delivered as local push notifications even when the app is not open.

**Why this priority**: Reminders are the differentiating feature (it's in the app name). But it depends on tasks existing (P1) and being editable (P2 task creation).

**Independent Test**: Can be tested by setting 2-3 reminders on a task with a near-future due date and verifying notifications arrive at the correct times.

**Acceptance Scenarios**:

1. **Given** a task with a due date, **When** the user opens the task detail and taps "Reminders", **Then** they see a list of configured reminders and an "Add Reminder" button.
2. **Given** the user taps "Add Reminder", **When** they configure an interval (e.g., "1 day before", "2 hours before", "30 minutes before"), **Then** a local push notification is scheduled for that time relative to the due date.
3. **Given** a task has 3 reminders configured, **When** the due date changes, **Then** all 3 notifications are rescheduled relative to the new due date.
4. **Given** the app is not running in the foreground, **When** a reminder time arrives, **Then** the user receives a push notification showing the task name and how long until it's due.
5. **Given** the user taps a notification, **When** the app opens, **Then** it navigates directly to the relevant task's detail view.
6. **Given** the user marks a task as done, **When** the task completes, **Then** all pending reminders for that task are cancelled.

---

### User Story 5 - Complete Recurring Tasks (Priority: P3)

A user marks a recurring task as complete. Instead of creating a new row in Notion, the app updates the same task's due date to the next occurrence based on the recurrence pattern (Daily/Weekly/Monthly/Yearly) and resets the status to "Not Started".

**Why this priority**: Recurring tasks are a natural extension once basic task management works. P3 because it's not needed for first-use value.

**Independent Test**: Can be tested by creating a weekly recurring task due today, marking it complete, and verifying the due date advances by 7 days and status resets to "Not Started" in both the app and Notion.

**Acceptance Scenarios**:

1. **Given** a task with recurrence set to "Weekly" and due date of March 13, **When** the user marks it complete, **Then** the task's due date updates to March 20 and status resets to "Not Started" in Notion.
2. **Given** a task with recurrence set to "Monthly" and due date of March 15, **When** the user marks it complete, **Then** the due date updates to April 15.
3. **Given** a task with recurrence set to "Yearly", **When** the user marks it complete, **Then** the due date advances by one year.
4. **Given** a task with recurrence set to "Daily", **When** the user marks it complete, **Then** the due date advances to tomorrow.
5. **Given** a recurring task with reminders, **When** the task is completed and due date advances, **Then** reminders are rescheduled relative to the new due date.
6. **Given** a task with no recurrence, **When** the user marks it complete, **Then** the status changes to "Done" and no date change occurs.

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
- What happens when a task's due date is in the past and has reminders? Reminders for past times are not scheduled; only future reminders are queued.
- What happens when the user has more than 100 tasks (Notion API pagination limit)? The app paginates through all results using cursor-based pagination.
- What happens when the user has no internet connection? The app shows cached data with a clear offline indicator and queues changes for sync when connectivity returns.
- What happens when a recurring task's due date is already past when completed? The due date advances to the next future occurrence (skipping past dates).
- What happens when the Notion API rate limit is hit? The app respects rate limit headers and shows a non-blocking "Syncing..." indicator.
- What happens when iOS revokes notification permissions? The app detects this and shows a prompt in Settings to re-enable notifications, with a deep link to iOS Settings.
- What happens when there are more than 64 scheduled local notifications (iOS limit)? The app prioritizes notifications for the soonest tasks and re-schedules as earlier notifications fire.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST authenticate users via Notion OAuth (public integration flow) and securely store the access token.
- **FR-002**: System MUST validate connected Notion databases against a minimum required schema (Tasks: title + status + date properties; Projects: title property).
- **FR-003**: System MUST detect database properties by type (not just name) and allow user mapping when multiple properties of the same type exist.
- **FR-004**: System MUST display tasks in four primary views: Inbox, Today (due today + overdue), Upcoming (grouped by date), and per-Project views.
- **FR-005**: System MUST provide a bottom tab bar with tabs for: Inbox, Today, Upcoming, Search/Filters, and Browse (projects list).
- **FR-006**: System MUST support inline task creation with a quick-action bar containing buttons for: due date, priority, tags, project, and recurrence.
- **FR-007**: System MUST display selected task field values as tappable colored chips (not traditional form fields).
- **FR-008**: Users MUST be able to create, edit, and complete tasks, with all changes synced to the Notion Tasks database.
- **FR-009**: System MUST support per-task custom staggered local push notifications — multiple reminders per task at user-defined intervals before the due date.
- **FR-010**: System MUST cancel pending reminders when a task is completed or deleted, and reschedule reminders when a task's due date changes.
- **FR-011**: System MUST handle recurring tasks by updating the existing task's due date to the next occurrence (based on Daily/Weekly/Monthly/Yearly pattern) and resetting status to "Not Started" upon completion — no new rows created.
- **FR-012**: System MUST follow the iOS system appearance setting (light/dark mode) by default, with an in-app override option (System/Light/Dark).
- **FR-013**: System MUST support swipe gestures on tasks: swipe right to complete, swipe left for more actions (reschedule, delete).
- **FR-014**: System MUST paginate through all Notion API results using cursor-based pagination.
- **FR-015**: System MUST handle offline state gracefully by displaying cached data and showing an offline indicator.
- **FR-016**: System MUST respect the iOS 64 scheduled notification limit by prioritizing nearest due tasks and re-scheduling as slots become available.
- **FR-017**: System MUST provide a "Database Setup Guide" accessible from Settings explaining the minimum Notion database requirements.
- **FR-018**: System MUST support pull-to-refresh on all task list views.
- **FR-019**: System MUST navigate to the relevant task detail view when a notification is tapped.
- **FR-020**: System MUST support iOS 17 and later, iPhone-only.
- **FR-021**: Reminder intervals MUST be stored locally on-device since Notion has no native reminder-interval property.
- **FR-022**: System MUST display task priority using color coding: Urgent=red, High=orange, Medium=blue, Low=default/no color.
- **FR-023**: System MUST provide home screen widgets in all three iOS sizes (small, medium, large) showing a list of upcoming tasks with checkboxes to complete tasks directly from the widget.
- **FR-024**: All widget sizes MUST include a "+" button in the bottom-right corner that opens the app to the task creation flow.
- **FR-025**: Widget task completion MUST sync to Notion (marking done or advancing recurring task due date) and trigger a widget refresh.

### Key Entities

- **Task**: A unit of work synced from Notion. Key attributes: name (title), status (Not Started / In Progress / Done), due date, priority (Urgent / High / Medium / Low), tags (multiple), project (relation to a Project), recurrence pattern (None / Daily / Weekly / Monthly / Yearly), reminders (local, multiple per task with custom intervals).
- **Project**: A grouping of tasks, synced from Notion. Key attributes: name (title). A virtual "Inbox" project exists for unassigned tasks.
- **Reminder**: A locally-stored notification schedule tied to a task. Key attributes: task reference, interval before due date (e.g., "30 minutes", "1 day"), scheduled notification time (computed from task due date minus interval).
- **User Session**: The authenticated connection to Notion. Key attributes: access token, workspace info, selected database IDs, property mappings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can connect their Notion workspace and see their tasks within 60 seconds of first app launch.
- **SC-002**: Users can create a new task with name, due date, priority, and project in under 15 seconds using the inline creation flow.
- **SC-003**: 100% of scheduled reminders are delivered at the correct time (within 1-minute tolerance of the scheduled interval before due date).
- **SC-004**: Recurring task completion updates the due date in Notion within 5 seconds of marking complete, with no duplicate rows created.
- **SC-005**: The app correctly identifies and reports missing database properties for at least 95% of common Notion task database configurations.
- **SC-006**: The app displays correctly in both light and dark mode, matching the user's system preference with zero manual configuration.
- **SC-007**: All task views (Inbox, Today, Upcoming, Project) load within 3 seconds on a standard network connection.
- **SC-008**: The app supports at least 500 tasks across all views without noticeable performance degradation.

## Assumptions

- **A-001**: The app will be distributed as a Notion public integration, requiring the full OAuth flow (not internal integration tokens).
- **A-002**: Notion access tokens do not expire; the app does not need a refresh token flow. It handles revocation by detecting 401 responses.
- **A-003**: Reminder intervals are stored on-device only (not synced to Notion) since Notion databases don't have a native multi-reminder property.
- **A-004**: The "Inbox" project is a virtual concept — tasks without a project relation (or with a project named "Inbox") are grouped here. The app does not create an "Inbox" project in Notion.
- **A-005**: The app targets iPhone-only. Mac Catalyst compatibility is a future consideration, not in scope for this spec.
- **A-006**: The minimum deployment target is iOS 17.
- **A-007**: The Apple Developer Team ID is GN4UMU6766 and bundle identifier follows the pattern com.kaungzinye.finally.
- **A-008**: The Notion API version used is 2022-06-28 or the latest stable version at time of development.
- **A-009**: Natural language parsing for task input (e.g., "buy groceries tomorrow p1") is a nice-to-have, not required for MVP.
- **A-010**: The token exchange step of OAuth requires a server-side component (to protect the client_secret). This will be handled via a lightweight backend or serverless function.

## Scope Boundaries

**In Scope**:
- Notion OAuth connection and data sync
- Todoist-style task views (Inbox, Today, Upcoming, Browse/Projects)
- Inline task creation with chip-based field selection
- Task editing and completion
- Per-task custom staggered local push notifications
- Recurring task due date advancement on completion
- Database schema validation with actionable error messages
- Dark/light mode with system preference support
- Setup guide for Notion database requirements
- Home screen widgets (small, medium, large) with task checkboxes and add button
- iPhone-only, iOS 17+

**Out of Scope**:
- iPad-specific layouts or Mac Catalyst optimization
- Notion database creation (user must have existing databases)
- Real-time collaboration or multi-user features
- Subtasks or nested task hierarchies
- File attachments or rich text editing in task descriptions
- Natural language date/priority parsing
- Calendar grid/month view
- Watch complications
- Offline task creation (offline mode is read-only with cached data)
