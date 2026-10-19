# Deadline reminder

A notification that counts down to a task's deadline. A task can carry several, and they move when the deadline moves.

A deadline reminder counts down to the task's [[Deadline]].

A date-only deadline reminder fires at the [[Default reminder time]].

## Fields

- Offset: morning of, a number of days before, a number of weeks before, or one hour before a timed deadline

## Rules

- Task detail shows each one as a chip. ✕ removes it and + adds one from a short list.
- A reminder whose fire time has already passed is skipped.
- A reminder that would fire after a timed deadline stays silent.
- Each recurrence cycle keeps the same offsets against the new deadline.
