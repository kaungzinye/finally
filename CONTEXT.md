# Finally domain context

Finally is a task system that protects attention, with an agent living in it. Input is precise, the daily view stays small.

## Language

### Modes

**Notion mode**: A workspace whose tasks live in the user's own Notion. The front door for new users, working with zero infrastructure.

**Server mode**: A workspace whose tasks live on Finally Server. The power path, and the mode Hermes operates in.

### Tasks and dates

**Task**: An outcome or obligation managed by one authoritative task provider.

**Planned day**: An optional date-only intention describing when the user hopes to work on a task.
_Avoid_: target date

**Deadline**: An optional date or date-time constraint describing when a task must be complete. Deadlines are facts the user states, never values the system invents.
_Avoid_: due date

**Suggested date**: A locally computed date for a subtask, derived from its parent's planned window. A manual override replaces the computed value.

**Recurring obligation**: A task whose outcome repeats and retains one stable task identity across cycles.
_Avoid_: recurring task

**Cycle**: One completed instance of a recurring obligation. Cycle history is the append-only record of finished cycles, kept as completion evidence.

### Providers and sync

**Task provider**: A system that owns tasks for one workspace. Finally Server and Notion are the two task providers.

**Provider adapter**: The app-side implementation of the task-provider contract for one provider.

**Finally Server**: The self-hosted authoritative task provider, derived from Vikunja, exposing Finally's canonical task model.

**Notion provider**: The adapter for Notion mode, where tasks remain authoritative in Notion.

**Provider workspace**: One independently synchronized task collection. Tasks do not copy automatically between provider workspaces.
_Avoid_: workspace (bare), session

**Notion surface**: A Notion database kept in two-way sync with a server workspace so its tasks can be seen and edited on desktop. The server stays authoritative, and Notion edits enter as patches under the same conflict rules as any other client.
_Avoid_: Notion mirror, Notion projection

**Dirty edit**: A local phone edit not yet durably synced to its provider. Dirty edits survive pulls and recoverable network failures.

**Stale write**: A patch submitted against an outdated revision. The server rejects it rather than merging blindly.

### Hermes and planning

**Hermes**: The conversational agent the user texts in natural language. It holds the user's context, captures tasks from rambling, extracts real deadlines when the words contain them, proposes Daily Focus and schedules when prompted, and edits tasks through the server API. It never delivers reminders and never holds Notion workspace credentials.
_Avoid_: automation agent, planning agent, automation client, chat integration

**Daily Focus**: The few tasks picked for one day, bounded by the focus limit. It starts proposed, by Hermes or by hand, and the user confirms it in the morning. Server mode stores it on the server, Notion mode stores it on the phone.
_Avoid_: Daily Plan, focus proposal, focus list, focus set

**Focus limit**: The configured bound on Daily Focus size, one to five tasks, defaulting to three.

**Displacement**: An urgent task entering Daily Focus by replacing an existing pick the user chooses. Daily Focus never grows past its limit.

**Replanning**: The explicit end-of-day decision for an unfinished focus task: keep, break down, schedule, defer, or drop.

### Calendar

**Derived scheduling constraint**: The only durable artifact Finally Server keeps from reading a calendar. Raw event content stays out of storage.

**Calendar publication**: Idempotent publication of work sessions and deadline markers to two dedicated Google calendars named Work Sessions and Deadlines.
_Avoid_: calendar projection

**Work session**: A timed reservation linked to a task, published as a busy calendar event it references by publication identity. A task has zero or more work sessions.

**Deadline marker**: A transparent Google Calendar event showing a deadline without blocking availability.
_Avoid_: calendar marker

### Reminders and notifications

**Reminder rule**: Canonical notification intent stored with the task and replicated to each iPhone for offline scheduling.

**Anchored reminder**: A reminder rule resolved relative to a task's planned day or deadline. It moves when its anchor moves.

**Exact reminder**: A reminder rule with a fixed timestamp independent of task dates.
_Avoid_: explicit-date reminder

**Moment**: One of the five occasions the phone speaks: a work session starts, a real deadline approaches, the morning Daily Focus confirmation, the evening replanning prompt, and the persistent Live Activity showing the current work session.

### Views

**Inbox**: The virtual view of tasks that belong to no project.

**Board**: The column view grouping tasks by status.
_Avoid_: kanban

## Invariants

- One provider owns each task, and one workspace belongs to one mode.
- Provider workspaces remain separate even when a Daily Focus references tasks from more than one provider.
- Planned days, deadlines, Daily Focus picks, and work sessions remain distinct concepts.
- Deadlines are facts. Hermes proposes planned days and work sessions freely and never invents a deadline.
- Only work sessions block calendar availability.
- Calendar routines never become tasks, and task recurrence never becomes a recurring calendar event.
- The iPhone schedules reminder notifications locally so synchronized reminders fire offline.
- Finally iOS is the preferred human editing interface. Explicit phone changes win same-field conflicts against any other client while unrelated changes remain intact.
- The server stays authoritative for a server workspace even when a Notion surface displays and edits it.
- Unfinished Daily Focus tasks end the day in explicit replanning, never silent rollover.
- Urgent additions displace an existing focus pick instead of expanding Daily Focus.
- Execution views surface actionable subtasks ahead of non-actionable parents.
- Moving a work session leaves the task deadline unchanged, and completing one leaves the task open.
- Notifications are core and free.
