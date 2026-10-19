# Scheduled day

The day the user hopes to work on a task. It is an intention, not a promise. The interface labels it "Scheduled".

## Fields

- Date only

## Rules

- A task scheduled for today appears in [[Today]].
- Once the day passes with the task still open, it becomes a [[Missed scheduled day]].
- A scheduled day never sends a notification of its own.
- A scheduled day falls on or before its task's [[Deadline]] day. Every way of setting one, including Reschedule, stops at the deadline day. Working on a task later means moving the deadline.
- The personal agent sets scheduled days freely within that limit.
