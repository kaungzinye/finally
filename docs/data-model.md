# Data Model: Finally

**Date**: 2026-03-13
**Feature**: 001-notion-task-app

## Entity Relationship Diagram

```
┌──────────────────────┐
│     UserSession       │
│──────────────────────│
│ id: UUID (PK)         │
│ workspaceId: String   │
│ workspaceName: String │
│ providerRaw: String   │
│ serverBaseURL: String?│
│ serverProjectID: Int? │
│ isSelected: Bool      │
│ tasksDatabaseId: Str  │
│ projectsDatabaseId: S │
│ propertyMappings: JSON│
│ lastFullSyncAt: Date? │
│ createdAt: Date       │
└──────────────────────┘

┌──────────────────────┐
│     ProjectItem       │
│──────────────────────│
│ notionPageId: String  │
│ providerWorkspaceId:  │
│ title: String         │
│ iconEmoji: String?    │
│ lastEditedTime: Date? │
│ lastSyncedAt: Date?   │
└──────────────────────┘
        │ 1:N
        ▼
┌──────────────────────────────────────────────┐
│                  TaskItem                    │
│──────────────────────────────────────────────│
│ externalTaskID: String                       │
│ providerWorkspaceId: String?                 │
│ title: String                                │
│ status: TaskStatus                           │
│ dueDate: Date?                               │
│ targetDate: Date?                            │
│ remindersJSON: String?                       │
│ priority: TaskPriority?                      │
│ tags: [String]                               │
│ tagColors: [String]                          │
│ recurrence: Recurrence                       │
│ customRecurrenceJSON: String?                │
│ lastEditedTime: Date?                        │
│ lastSyncedAt: Date?                          │
│ isDirty: Bool                                │
│ isDeleted: Bool                              │
│ parentId: String?                            │
│ sortIndex: Int                               │
│ suggestedDateOverride: Date?                 │
└──────────────────────────────────────────────┘
        ▲                          │
        │ parent-child             │ N:1
        └──────────────────────────┘
```

## Entities

### TaskItem

The canonical task entity synced by a task provider. Subtasks are also `TaskItem` records; they are distinguished by having a `parentId`.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| externalTaskID | String | Provider | Sync key inside the owning provider workspace. |
| providerWorkspaceId | String? | Provider session | Owning workspace used for every local query and mutation. |
| title | String | Notion | From the `title` property. |
| status | TaskStatus | Notion | Enum: `.notStarted`, `.inProgress`, `.done`. |
| dueDate | Date? | Notion | Official deadline synced to Notion `Due`. This is the primary task date in the app. |
| targetDate | Date? | Notion | Optional earlier planning date synced to a secondary Notion date field such as `Target`. |
| remindersJSON | String? | Local | JSON array of anchored reminders stored on-device. |
| priority | TaskPriority? | Notion | Enum: `.urgent`, `.high`, `.medium`, `.low`. |
| tags | [String] | Notion | Array of tag names from the `multi_select` property. |
| tagColors | [String] | Notion | Parallel array of Notion color names for tag rendering. |
| recurrence | Recurrence | Notion | Enum: `.none`, `.daily`, `.weekly`, `.monthly`, `.yearly`, `.custom`. |
| customRecurrenceJSON | String? | Local | JSON-encoded custom recurrence rule when `recurrence == .custom`. |
| lastEditedTime | Date? | Notion | `last_edited_time` from Notion for conflict detection. |
| lastSyncedAt | Date? | Local | Timestamp of last successful sync. |
| isDirty | Bool | Local | True when local changes have not yet been pushed to the provider. |
| isDeleted | Bool | Local | Soft-delete flag for optimistic deletion before sync confirms. |
| parentId | String? | Notion | Parent task page ID for subtasks. Nil for top-level tasks. |
| sortIndex | Int | Local | Ordering index for subtasks under the same parent. |
| suggestedDateOverride | Date? | Local | Manual override of the subtask's computed suggested date. |
| project | ProjectItem? | Notion | Relationship to the owning project. Nil = Inbox. |
| parent | TaskItem? | Notion | Parent relationship for subtasks. |
| subtasks | [TaskItem] | Derived | Inverse relationship of child tasks. |

**Computed values:**
- `effectiveSuggestedDate = suggestedDateOverride ?? computedFromParentWindow`

**Validation rules:**
- `externalTaskID` must be non-empty and unique inside its provider workspace
- `providerWorkspaceId` identifies the owning connected workspace
- `title` must be non-empty
- `dueDate` is the primary planning date
- `targetDate`, when set, must be strictly earlier than `dueDate`
- Subtasks are real Notion pages; they must not rely on an `isLocalOnly` subtask mode in the redesigned model

### ProjectItem

A grouping entity for tasks, synced from Notion.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| notionPageId | String | Notion | Unique sync key. Notion page UUID. |
| providerWorkspaceId | String? | Provider session | Owning workspace used to scope project browsing and selection. |
| title | String | Notion | From the `title` property. |
| iconEmoji | String? | Notion | Emoji from the Notion page icon, if set. |
| lastEditedTime | Date? | Notion | For sync conflict detection. |
| lastSyncedAt | Date? | Local | Timestamp of last successful sync. |
| tasks | [TaskItem] | Derived | Inverse relationship. All tasks linked to this project. |

**Note:** A virtual "Inbox" project is not stored in the database. Tasks with `project == nil` are displayed under "Inbox" in the UI.

### ReminderOffset

A local-only anchored reminder descriptor stored inside `TaskItem.remindersJSON`.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| anchor | ReminderAnchor | Local | One of `target` or `due`. |
| value | Int | Local | Positive integer value for the offset amount. |
| unit | ReminderOffsetUnit | Local | One of `minutes`, `hours`, `days`, `weeks`, `months`. |
| direction | ReminderOffsetDirection | Local | `before` or `after`. |

**Scheduling semantics:**
- `anchor = target` → resolve from `targetDate`
- `anchor = due` → resolve from `dueDate`

**Validation rules:**
- `minutes` → `1...59`
- `hours` → `1...23`
- `days` → `1...30`
- `weeks` → `1...51`
- `months` → `1...11`
- `years` is not supported; use months instead

**Storage note:**
- Quick presets such as "1 week before target" are convenience constructors only. They serialize to the same `ReminderOffset` structure as custom reminder entries.

### ExplicitDateReminder

A local-only exact-time reminder descriptor that also lives inside `TaskItem.remindersJSON`.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| dateTime | Date | Local | Fires at this exact date/time. |

**Semantics:**
- Does not use `targetDate` or `dueDate` as an anchor
- Remains fixed even if task dates change
- Allows reminders to exist even when the task has no `dueDate`

### UserSession

Authentication and configuration state. SwiftData stores workspace metadata; Keychain stores one credential per workspace.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| id | UUID | Local | Auto-generated. |
| workspaceId | String | Provider | Stable local scope for provider data. |
| workspaceName | String | Provider/user | Display name for the connected workspace. |
| providerRaw | String | Provider | Selects the adapter for this workspace. |
| serverBaseURL | String? | Finally Server | HTTPS server origin. |
| serverProjectID | Int64? | Finally Server | Writable project selected from authenticated discovery. |
| isSelected | Bool | Local | Identifies the workspace shown throughout the app. |
| tasksDatabaseId | String | User selection | Notion database ID for Tasks. |
| projectsDatabaseId | String | User selection | Notion database ID for Projects. |
| propertyMappings | PropertyMappings | User/auto | Maps Notion property names to app fields. |
| lastFullSyncAt | Date? | Local | When the last full sync was performed. |
| createdAt | Date | Local | When the session was established. |

Finally Server authentication validates HTTPS before sending a password or token. The app authenticates, lists writable projects, requires an explicit selection, and stores the resulting token under the selected workspace identifier.

## Enums

### TaskStatus
```
.notStarted  → maps to Notion status group "To-do"
.inProgress  → maps to Notion status group "In progress"
.done        → maps to Notion status group "Complete"
```

### TaskPriority
```
.urgent  → color: red
.high    → color: orange
.medium  → color: blue
.low     → color: default
```

### Recurrence
```
.none    → no recurrence
.daily   → advance due date by 1 day
.weekly  → advance due date by 7 days
.monthly → advance due date by 1 month
.yearly  → advance due date by 1 year
.custom  → advance due date according to stored recurrence JSON
```

### ReminderOffsetUnit
```
.minutes
.hours
.days
.weeks
.months
```

### ReminderOffsetDirection
```
.before
.after
```

### ReminderAnchor
```
.target
.due
```

## Subtask Scheduling

Default suggested dates for subtasks are computed from the parent task window:

- If parent has a `targetDate`, the app works backward from `targetDate`
- Otherwise it works backward from `dueDate`
- Later subtasks land closer to the chosen planning date, earlier subtasks are spaced earlier by subtask order
- Any subtask may override its computed date via `suggestedDateOverride`

## Recurrence + Deadline Behavior

- Recurrence and reminders are separate concerns
- A recurring task keeps its recurrence rule, anchored reminders, and target date as reusable metadata
- When the task rolls into the next cycle, the same reminders are re-applied to the new dates using their explicit anchors
- In the app model, recurrence creates a new logical cycle; in the Notion model, the same parent and subtask pages persist and reset state rather than duplicating pages

## Property Mappings

The app detects Notion database properties by **type**, not name, unless a specific named property is required by product policy.

### Required Tasks Database Properties

| App Field | Notion Property Type | Detection Strategy |
|-----------|---------------------|--------------------|
| Name | `title` | Guaranteed to exist |
| Status | `status` | Required for task state |
| Due | `date` | Used as the official deadline field |
| Target | `date` | Used as the optional earlier planning field |
| Parent Task | `relation` / parent-child | Required for real Notion-backed subtasks in the redesigned model |

### Optional Tasks Database Properties

| App Field | Notion Property Type | Detection Strategy |
|-----------|---------------------|--------------------|
| Priority | `select` | Match known priority values |
| Tags | `multi_select` | Any tag collection property |
| Project | `relation` | Relation to the Projects database |
| Recurrence | `select` | Match daily / weekly / monthly / yearly / custom semantics |

## Sync Layer

The sync contract is intentionally simpler than the app planning model:

- Notion `Due` <-> app `dueDate`
- Notion `Target` <-> app `targetDate`
- Local only:
  - `remindersJSON`
  - `sortIndex`
  - `suggestedDateOverride`

Subtasks in the app should mirror Notion subtasks directly:

- every app subtask is a real Notion child page
- the app should not maintain a parallel subtask-only hierarchy that differs from Notion
- local metadata may enrich planning, but Notion remains the structural source of truth

### Required Projects Database Properties

| App Field | Notion Property Type | Detection Strategy |
|-----------|---------------------|--------------------|
| Name | `title` | Guaranteed to exist |
