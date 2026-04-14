# Data Model: Finally

**Date**: 2026-03-13
**Updated**: 2026-03-18
**Feature**: 001-notion-task-app

## Entity Relationship Diagram

```
┌──────────────────────┐
│     UserSession       │
│──────────────────────│
│ id: UUID (PK)         │
│ accessToken: String   │
│ workspaceId: String   │
│ workspaceName: String │
│ tasksDatabaseId: Str  │
│ projectsDatabaseId: S │
│ propertyMappings: JSON│
│ lastFullSyncAt: Date? │
│ createdAt: Date       │
└──────────────────────┘

┌──────────────────────┐         ┌──────────────────────┐
│     ProjectItem       │◄────┐  │     ReminderItem      │
│──────────────────────│     │  │──────────────────────│
│ notionPageId: String  │     │  │ id: UUID (PK)         │
│ title: String         │     │  │ intervalSeconds: Int   │
│ iconEmoji: String?    │     │  │ absoluteDate: Date?    │
│ lastEditedTime: Date? │     │  │ label: String          │
│ lastSyncedAt: Date?   │     │  │ notificationId: String │
└──────────────────────┘     │  │ isScheduled: Bool      │
        │                     │  └──────────────────────┘
        │ 1:N                 │           │
        ▼                     │           │ N:1
┌──────────────────────┐     │           │
│      TaskItem         │─────┘           │
│──────────────────────│◄─────────────────┘
│ notionPageId: String  │
│ title: String         │
│ status: TaskStatus    │
│ dueDate: Date?        │
│ startDate: Date?      │
│ priority: TaskPriority?│
│ tags: [String]        │
│ tagColors: [String]   │
│ recurrence: Recurrence│
│ customRecurrenceJSON: String? │
│ lastEditedTime: Date? │
│ lastSyncedAt: Date?   │
│ isDirty: Bool         │
│ isDeleted: Bool       │
│ isLocalOnly: Bool     │
│ parentId: String?     │
│ suggestedDate: Date?  │
│ sortIndex: Int        │
└──────────────────────┘
```

## Entities

### TaskItem

The primary entity representing a task synced from Notion.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| notionPageId | String | Notion | Unique sync key. Notion page UUID. |
| title | String | Notion | From the `title` property. |
| status | TaskStatus | Notion | Enum: `.notStarted`, `.inProgress`, `.done`. Mapped from Notion `status` property groups. |
| dueDate | Date? | Notion | From the primary `date` property used as due date. Nil if no due date set. |
| startDate | Date? | Notion | Optional start date for the task’s active work window, when available. |
| priority | TaskPriority? | Notion | Enum: `.urgent`, `.high`, `.medium`, `.low`. From Notion `select` property. Nil if no priority. |
| tags | [String] | Notion | Array of tag names from Notion `multi_select` property. |
| tagColors | [String] | Notion | Parallel array of Notion color names for each tag (for UI chips and Kanban board). |
| recurrence | Recurrence | Notion | Enum: `.none`, `.daily`, `.weekly`, `.monthly`, `.yearly`, `.custom`. From Notion `select` property. |
| customRecurrenceJSON | String? | Local | JSON-encoded custom recurrence rule when `recurrence == .custom`. |
| lastEditedTime | Date? | Notion | `last_edited_time` from Notion for conflict detection. |
| lastSyncedAt | Date? | Local | Timestamp of last successful sync for this entity. |
| isDirty | Bool | Local | True when local changes haven't been pushed to Notion. |
| isDeleted | Bool | Local | Soft-delete flag for optimistic deletion before sync confirms. |
| isLocalOnly | Bool | Local | True when the task has not yet been created in Notion (local draft). |
| parentId | String? | Notion/Local | Notion page ID of parent task for subtasks; nil for top-level tasks. |
| suggestedDate | Date? | Local | Suggested date used to surface subtasks in Today/Upcoming views. |
| sortIndex | Int | Local | Ordering index used to sort subtasks under a parent. |
| project | ProjectItem? | Notion | Relationship. From Notion `relation` property. Nil = Inbox. |
| parent | TaskItem? | Local | Relationship to parent task entity (when this is a subtask). |
| subtasks | [TaskItem] | Local | Inverse relationship for nested task hierarchies. |
| reminders | [ReminderItem] | Local | Relationship (cascade delete). Local-only, not synced to Notion. |

**State transitions for status:**
- Not Started → In Progress → Done
- Done → Not Started (when recurring task completes and due date advances)

**Validation rules:**
- `notionPageId` must be non-empty and unique
- `title` must be non-empty
- `dueDate` is required for reminders to be schedulable
- When `recurrence != .none` and task is completed: advance `dueDate`, reset `status` to `.notStarted`

### ProjectItem

A grouping entity for tasks, synced from Notion.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| notionPageId | String | Notion | Unique sync key. Notion page UUID. |
| title | String | Notion | From the `title` property. |
| iconEmoji | String? | Notion | Emoji from the Notion page icon (if set). Displayed next to project name in pickers and browse view. |
| lastEditedTime | Date? | Notion | For sync conflict detection. |
| lastSyncedAt | Date? | Local | Timestamp of last successful sync. |
| tasks | [TaskItem] | Derived | Inverse relationship. All tasks linked to this project. |

**Note:** A virtual "Inbox" project is not stored in the database. Tasks with `project == nil` are displayed under "Inbox" in the UI.

### ReminderItem

A locally-stored notification schedule tied to a task. Never synced to Notion (FR-021).

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| id | UUID | Local | Auto-generated primary key. |
| intervalSeconds | Int | Local | Seconds before due date to fire. E.g., 3600 = 1 hour before. **0 when `absoluteDate` is set.** |
| absoluteDate | Date? | Local | If set, the reminder fires at this exact date/time (not relative to due date). Used for custom-date reminders. |
| label | String | Local | Human-readable label: "30 minutes before", "1 day before", or a formatted absolute date string. |
| notificationId | String | Local | `UNNotificationRequest` identifier. Format: `"task-{notionPageId}-reminder-{intervalSeconds}"` for interval reminders, `"task-{notionPageId}-reminder-abs-{unixTimestamp}"` for absolute reminders. |
| isScheduled | Bool | Local | Whether this reminder is currently in the iOS notification queue (may be false if beyond the 60-notification limit). |
| task | TaskItem? | Local | Parent relationship. |

**Computed `fireDate`:**
- If `absoluteDate != nil` → `absoluteDate`
- Else → `task.dueDate - intervalSeconds`

**Validation rules:**
- `task` must have a non-nil `dueDate` for interval-based reminders to be schedulable
- `fireDate` must be in the future for the reminder to be scheduled
- Absolute-date reminders can fire even if the task has no due date

### UserSession

Authentication and configuration state. Stored in Keychain (token) and UserDefaults/SwiftData (metadata).

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| id | UUID | Local | Auto-generated. |
| accessToken | String | Notion OAuth | Stored in Keychain, NOT in SwiftData. |
| workspaceId | String | Notion OAuth | From token exchange response. |
| workspaceName | String | Notion OAuth | Display name for connected workspace. |
| tasksDatabaseId | String | User selection | Notion database ID for Tasks. |
| projectsDatabaseId | String | User selection | Notion database ID for Projects. |
| propertyMappings | PropertyMappings | User/auto | Maps Notion property names to app fields (e.g., which date property is "due date"). |
| lastFullSyncAt | Date? | Local | When the last full (non-incremental) sync was performed. |
| createdAt | Date | Local | When the session was established. |

**Note:** `accessToken` is stored separately in the Keychain via the Security framework. The `UserSession` entity in SwiftData holds everything except the token.

## Enums

### TaskStatus
```
.notStarted  → maps to Notion status group "To-do"
.inProgress  → maps to Notion status group "In progress"
.done        → maps to Notion status group "Complete"
```

### TaskPriority
```
.urgent  → color: red    → maps to Notion select option "Urgent"
.high    → color: orange → maps to Notion select option "High"
.medium  → color: blue   → maps to Notion select option "Medium"
.low     → color: default → maps to Notion select option "Low"
```

### Recurrence
```
.none    → no recurrence
.daily   → advance due date by 1 day
.weekly  → advance due date by 7 days
.monthly → advance due date by 1 month (calendar-aware)
.yearly  → advance due date by 1 year
.custom  → advance due date according to a stored RecurrenceRule (JSON-backed)
```

## Property Mappings

The app detects Notion database properties by **type**, not name. When ambiguity exists (e.g., multiple `date` properties), the user is prompted to map them.

### Required Tasks Database Properties

| App Field | Notion Property Type | Detection Strategy |
|-----------|---------------------|--------------------|
| Name | `title` | Guaranteed to exist (one per database) |
| Status | `status` | Find the `status` type property; map options to groups |
| Due Date | `date` | If one `date` property exists, auto-map. If multiple, prompt user. |

### Optional Tasks Database Properties

| App Field | Notion Property Type | Detection Strategy |
|-----------|---------------------|--------------------|
| Priority | `select` | Look for a `select` with options containing "High"/"Medium"/"Low" or "Urgent"/"P1"/etc. |
| Tags | `multi_select` | Look for any `multi_select` property. If multiple, prompt user. |
| Project | `relation` | Look for a `relation` pointing to the Projects database. |
| Recurrence | `select` | Look for a `select` with options containing "Daily"/"Weekly"/"Monthly"/"Yearly". If not found, offer to create it. |

### Required Projects Database Properties

| App Field | Notion Property Type | Detection Strategy |
|-----------|---------------------|--------------------|
| Name | `title` | Guaranteed to exist |
