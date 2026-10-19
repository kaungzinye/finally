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
- Status cycles on each tap of the status chip in task detail and on Board cards.
- A row shows one date. It shows the deadline when there is one, otherwise the scheduled day.
- Swiping Reschedule on a row moves the scheduled day, up to the deadline day. It never moves the deadline.
