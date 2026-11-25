# Task

An outcome or obligation owned by one task provider. Every other concept here hangs off a task.

A task belongs to at most one [[Project]]. A task without one sits in the [[Inbox]].

A task may carry a [[Scheduled day]], the day the user hopes to work on it.

A task may carry a [[Deadline]], the day or time it must be done.

## Fields

- Title
- Status: Not started, In progress, Complete
- Priority: Urgent, High, Medium, Low, or none. The priority ring carries its color.
- Project, optional
- Scheduled day, optional, date only
- Deadline, optional, date or date and time
- Deadline reminders and exact reminders
- Recurrence, optional
- Subtasks, ordered. A subtask gets a suggested date spread across its parent's scheduled window.

## Rules

- Tapping the ring on a row completes the task in one tap.
- Task detail sets the status on a three-segment control. The status chip on a Board card cycles on each tap.
- A row shows one date. It shows the deadline when there is one, otherwise the scheduled day.
- Swiping Reschedule on a row moves the scheduled day. A day after the deadline asks to move both, and Cancel changes nothing.
