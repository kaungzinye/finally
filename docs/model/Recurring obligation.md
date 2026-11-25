# Recurring obligation

A [[Task]] whose outcome repeats. It stays one task across every cycle.

## Rules

- The next [[Deadline]] follows from the current deadline, whatever day the user finishes. Rent due on the 1st stays on the 1st.
- Finishing late moves the deadline to the next future date in the pattern. Cycle history records the cycle the user finished and nothing for the dates skipped.
- Finishing a cycle reopens every subtask.
- Each [[Deadline reminder]] keeps its offset against the new deadline.
- A cycle never creates a [[Work session]].
