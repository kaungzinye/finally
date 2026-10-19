# Finally glossary

Finally is a task system that protects attention. It is the interface where the user and their personal agent organise tasks together. The agent captures and proposes, and the user reviews and decides. Input is precise, and the daily view stays small.

## Language

### Modes

**Notion mode**: A workspace whose tasks live in the user's own Notion. The front door for new users, working with zero infrastructure.

**Server mode**: A workspace whose tasks live on Finally Server. The power path, and the mode the personal agent operates in.

### Tasks and dates

**Task**: An outcome or obligation managed by one authoritative task provider.

**Scheduled day**: An optional date-only intention describing when the user hopes to work on a task. The interface labels it "Scheduled". Missing it carries no consequence beyond the task staying in Today.
_Avoid_: planned day, target date, do date

**Deadline**: An optional date or date-time constraint describing when a task must be complete. Deadlines are facts the user states, never values the system invents. Deadlines drive reminders.
_Avoid_: due date, due

**Overdue**: A task whose deadline has passed while it is still open. Only a missed deadline makes a task overdue, and the interface marks it in red.

**Missed scheduled day**: An open task whose scheduled day has passed. It stays in Today in muted text reading "from" its scheduled weekday, and it never turns red.

**Unscheduled**: An open task with neither a scheduled day nor a deadline.
_Avoid_: backlog

**Suggested date**: A locally computed date for a subtask, derived from its parent's scheduled window.

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

### Personal agent and planning

**Personal agent**: The conversational agent the user texts in natural language. It holds the user's context, captures tasks from rambling, extracts real deadlines when the words contain them, proposes Daily Focus and schedules when prompted, and edits tasks through the server API. It never delivers reminders and never holds Notion workspace credentials.
_Avoid_: Hermes, automation agent, planning agent, automation client, chat integration

**Today**: Everything on the user's plate for the current day: open tasks scheduled or due today, overdue tasks, and missed scheduled days. Today is what's scheduled. Daily Focus is what the user will actually do.

**Daily Focus**: The few tasks picked out of Today for one day, bounded by the focus limit. The interface calls it "3 things to do" (or the configured count). A list the personal agent proposes waits for the user's morning confirmation. A list the user picks by hand needs no confirmation, because picking is the commitment. Picking a task sets its scheduled day to today. Server mode stores it on the server, Notion mode stores it on the phone.
_Avoid_: Daily Plan, focus proposal, focus list, focus set, daily brief

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

**Deadline reminder**: A reminder rule resolved relative to a task's deadline: the morning of, a number of days or weeks before, or an hour before a timed deadline. It moves when the deadline moves. A task carries any number of them.
_Avoid_: anchored reminder

**Default deadline reminders**: The deadline reminders a task receives when its deadline goes from empty to set, configured in Settings. They default to the morning of, one day before, and one week before, plus one hour before for a timed deadline. A deadline gaining a time receives the one-hour default, and clearing a deadline drops its deadline reminders. The user edits them per task afterwards.

**Exact reminder**: A reminder rule with a fixed timestamp independent of task dates. The interface offers it as "Remind me at".
_Avoid_: explicit-date reminder

**Default reminder time**: The time of day at which date-level deadline reminders fire.

Continuous work toward a distant deadline gets its notifications from work sessions, not from extra reminder rules. A scheduled day never notifies on its own. It feeds Today and the morning Daily Focus notification.

**Moment**: One of the five occasions the phone speaks: a work session starts, a real deadline approaches, the morning Daily Focus confirmation, the evening replanning prompt, and the persistent Live Activity showing the current work session.

### Views

**Inbox**: The virtual view of tasks that belong to no project. Capture lands there when the user names no project, and the user sorts it later.

**Tasks**: The tab holding every task in the workspace: Inbox first, then each project limited to its nearest few tasks, with an Unscheduled filter, search, sort, and a switch between list and Board.
_Avoid_: Browse, explore

**Board**: The column view of Tasks grouping tasks by status: Not started, In progress, Complete.
_Avoid_: kanban

## Invariants

- One provider owns each task, and one workspace belongs to one mode.
- Provider workspaces remain separate even when a Daily Focus references tasks from more than one provider.
- Scheduled days, deadlines, Daily Focus picks, and work sessions remain distinct concepts.
- A scheduled day never falls after its deadline's day. Rescheduling stops at the deadline day and never moves the deadline.
- Deadlines are facts. The personal agent proposes scheduled days and work sessions freely and never invents a deadline.
- Today and every widget read the same definition of Today.
- Only a missed deadline is overdue. A missed scheduled day stays visible without alarm.
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
- Finally publishes calendar events with calendar reminders off. The phone is the only thing that notifies.
- Every task field has a reader. A field that no view, sort, notification, or agent reads stays out of the canonical model until something needs it.
