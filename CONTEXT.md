# Finally domain context

Finally protects attention while providing one native task experience across separate task providers.

## Language

### Tasks and dates

**Task**: An outcome or obligation managed by one authoritative task provider.

**Planned day**: An optional date-only intention describing when the user hopes to work on a task.
_Avoid_: target date, targetDate

**Deadline**: An optional date or date-time constraint describing when a task must be complete.
_Avoid_: due date, dueDate

**Suggested date**: A locally computed date for a subtask, derived from its parent's planned window. A manual override replaces the computed value.

**Recurring obligation**: A task whose outcome repeats and retains one stable task identity across cycles.
_Avoid_: recurring task

**Cycle**: One completed instance of a recurring obligation. Cycle history is the append-only record of finished cycles, kept as completion evidence.

### Providers and sync

**Task provider**: A system that owns tasks for one workspace. Finally Server and Notion are the two task providers.

**Provider adapter**: The app-side implementation of the task-provider contract for one provider.

**Finally Server**: The self-hosted authoritative task provider for automation clients and Finally iOS. It derives from Vikunja and exposes Finally's canonical task model.

**Notion provider**: The adapter for collaborative tasks that remain authoritative in Notion.

**Provider workspace**: One independently synchronized task collection. Tasks do not copy automatically between provider workspaces.
_Avoid_: workspace (bare), session

**Dirty edit**: A local phone edit not yet durably synced to its provider. Dirty edits survive pulls and recoverable network failures.

**Stale write**: An automation patch submitted against an outdated revision. The server rejects it rather than merging blindly.

### Planning and focus

**Planning projection**: Minimal read-only metadata published from a provider so the planning layer can rank a task without receiving mutation authority for its source workspace.

**Daily Plan**: The dated record of one day's focus selection, holding its ordered task references, focus limit, and confirmation state.

**Daily Focus**: The tasks selected by a Daily Plan. It is provider-neutral and does not change task dates.
_Avoid_: focus list, focus set

**Focus limit**: The configured bound on Daily Focus size, one to five tasks, defaulting to three.

**Focus proposal**: The automation agent's evening proposal of the next day's Daily Focus, which the user confirms in the morning.

**Displacement**: An urgent task entering Daily Focus by replacing an existing selection the user chooses. Daily Focus never grows past its limit.

**Replanning**: The explicit end-of-day decision for an unfinished focus task: keep, break down, schedule, defer, or drop.

**Automation agent**: A planning and task-editing client that operates through Finally Server. Automation agents do not hold Notion credentials or deliver task reminders.
_Avoid_: planning agent, automation client, Hermes

**Chat integration**: An optional conversational surface for manual task edits through the server API. It plans nothing autonomously and delivers no reminders.

### Calendar

**Derived scheduling constraint**: The only durable artifact Finally Server keeps from reading a calendar. Raw event content stays out of storage.

**Calendar publication**: Idempotent publication of work sessions, deadline markers, and Daily Focus markers to three dedicated Google calendars named Work Sessions, Deadlines, and Daily Focus.
_Avoid_: calendar projection

**Work session**: A timed reservation linked to a task, published as a busy calendar event. A task has zero or more work sessions.

**Calendar marker**: A transparent Google Calendar event showing a deadline (deadline marker) or a confirmed Daily Focus item (focus marker) without blocking availability.

### Reminders

**Reminder rule**: Canonical notification intent stored with the task and replicated to each iPhone for offline scheduling.

**Anchored reminder**: A reminder rule resolved relative to a task's planned day or deadline. It moves when its anchor moves.

**Exact reminder**: A reminder rule with a fixed timestamp independent of task dates.
_Avoid_: explicit-date reminder

### Views

**Inbox**: The virtual view of tasks that belong to no project.

**Board**: The column view grouping tasks by status.
_Avoid_: kanban

## Invariants

- One provider owns each task.
- Provider workspaces remain separate even when the Daily Plan references tasks from more than one provider.
- Planned days, deadlines, Daily Focus selections, and work sessions remain distinct concepts.
- Only work sessions block calendar availability.
- The iPhone schedules reminder notifications locally so synchronized reminders fire offline.
- Finally iOS is the preferred human editing interface. Explicit phone changes win same-field conflicts while unrelated server changes remain intact.
- Unfinished Daily Focus tasks end the day in explicit replanning, never silent rollover.
- Urgent additions displace an existing focus task instead of expanding Daily Focus.
- Execution views surface actionable subtasks ahead of non-actionable parents.
- Moving a work session leaves the task deadline unchanged, and completing one leaves the task open.
