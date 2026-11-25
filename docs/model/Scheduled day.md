# Scheduled day

The day the user hopes to work on a task. It is an intention, not a promise. The interface labels it "Scheduled".

## Fields

- Date only

## Rules

- A task scheduled for today appears in [[Today]].
- Once the day passes with the task still open, it becomes a [[Missed scheduled day]].
- A scheduled day never sends a notification of its own.
- A scheduled day falls on or before its task's [[Deadline]] day. Rescheduling past the deadline asks to move the deadline too: "Move both" moves it to the new day at its own time of day, and Cancel changes nothing.
- The personal agent sets scheduled days freely within that limit.
