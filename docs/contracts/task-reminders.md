# Task reminder rules

Finally Server persists `deadline_has_time` and `reminder_rules` on each task. Conditional task writes synchronize these fields alongside the task revision. Deadline precision shares the `due_date` field's conflict ownership, and a phone deadline edit sends `due_date` and `deadline_has_time` together. Reminder rules have their own field ownership.

## Rule shapes

Every rule has a canonical hyphenated UUID, unique within its task. There are two kinds.

A deadline reminder counts down to the task's deadline:

```json
{ "id": "…", "kind": "deadline", "offset": "morningOf" }
{ "id": "…", "kind": "deadline", "offset": "daysBefore", "value": 1 }
{ "id": "…", "kind": "deadline", "offset": "weeksBefore", "value": 1 }
{ "id": "…", "kind": "deadline", "offset": "hourBefore" }
```

`daysBefore` takes a `value` from 1 to 30. `weeksBefore` takes a `value` from 1 to 12. `morningOf` and `hourBefore` carry no `value`. A task holds at most one deadline rule with the same offset and value. Exact rules may share an instant, since each has its own UUID.

An exact reminder fires once at a fixed instant:

```json
{ "id": "…", "kind": "exact", "at": "2026-10-20T15:00:00.000Z" }
```

`at` is an RFC3339 timestamp. Exact timestamps preserve fractional seconds. Clearing rules uses `reminder_rules: []`. The server rejects any other kind, offset, out-of-range value, a `value` on `morningOf` or `hourBefore`, an `at` on a deadline rule, and duplicate rules.

Scheduled days never carry reminders.

## Resolution on the phone

The phone stores synchronized rules in SwiftData and resolves them locally against the task's current deadline:

- `morningOf` fires on the deadline's calendar day at the default reminder time.
- `daysBefore` fires `value` calendar days before the deadline's day, at the default reminder time.
- `weeksBefore` fires `7 × value` calendar days before the deadline's day, at the default reminder time.
- `hourBefore` fires one hour before a timed deadline. It stays inert while the deadline has no time.
- A deadline rule whose fire time falls after a timed deadline stays inert, so `morningOf` never fires for an 08:00 deadline with a 09:00 default reminder time.
- `exact` fires at `at` whatever happens to the task's dates.

A deadline at 17:00 on Friday with a 09:00 default reminder time gets `morningOf` at 09:00 Friday, `daysBefore 1` at 09:00 Thursday, and `hourBefore` at 16:00 Friday. Deadline reminders without a deadline stay inert. Fire times in the past are skipped. Day-level resolution uses the local calendar, and the phone schedules resolved instants with explicit UTC components, so a timezone change keeps exact instants and recalculates day-level ones.

New deadlines receive the default deadline reminders configured on the phone when the deadline goes from empty to set. A deadline gaining a time receives the one-hour default, and clearing a deadline drops its deadline rules. The defaults are phone settings and never travel to the server.

## Reconciliation

Reconciliation runs at launch, foreground entry, timezone changes, provider synchronization, and local reminder/task edits. It cancels orphaned requests, excludes completed/deleted/unavailable tasks, and schedules the earliest future reminders. Request identity includes provider workspace, task, and rule UUID. Notification taps open the matching task in its provider workspace.

The pending queue reserves requests belonging to other app moments and schedules at most 60 task reminders within the phone's 64-request budget. Deferred rules remain persisted and refill when reconciliation runs. Saved rules, pending-limit status, denied permission, quiet permission, and scheduling failures remain distinct, and the app displays recovery actions. Scheduled reminders fire through iOS while the app and server are offline, subject to the phone's notification settings.

## Tests

`DeadlineReminderTests` covers phone resolution, default application, chip edits across deadline moves, and recurrence cycles. `DefaultDeadlineRemindersTests` covers the Settings list. `ServerReminderRuleTests` covers the wire shapes, validation, identity, and fresh-context scheduling. `ReminderReconciliationTests` covers pending budgets, relaunch refill, authorization, failures, orphan cancellation, completion, and timezone changes. `ServerReminderSyncTests` covers provider synchronization and dirty edits. Server route tests cover persistence, narrow patches, deadline precision conflicts, empty arrays, and every rejected shape.
