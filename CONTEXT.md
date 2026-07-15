# Finally domain context

Finally protects attention while providing one native task experience across separate task providers.

## Glossary

- **Task**: An outcome or obligation managed by one authoritative task provider.
- **Task provider**: A system that owns tasks for one workspace. Finally Server and Notion are separate task providers.
- **Finally Server**: The self-hosted authoritative task provider for automation clients and Finally iOS. It derives from Vikunja and exposes Finally's canonical task model.
- **Notion provider**: The adapter for collaborative tasks that remain authoritative in Notion.
- **Provider workspace**: One independently synchronized task collection. Tasks do not copy automatically between provider workspaces.
- **Planning projection**: Minimal read-only metadata published from a provider so the planning layer can rank a task without receiving mutation authority for its source workspace.
- **Planned day**: An optional date-only intention describing when the user hopes to work on a task.
- **Deadline**: An optional date or date-time constraint describing when a task must be complete.
- **Daily Plan**: The confirmed task selection for one day. Its configured focus limit is one to five tasks and defaults to three.
- **Daily Focus**: The tasks selected by a Daily Plan. It is provider-neutral and does not change task dates.
- **Work session**: A timed reservation linked to a task. A task has zero or more work sessions.
- **Recurring obligation**: A task whose outcome repeats and retains one stable task identity across cycle history.
- **Reminder rule**: Canonical notification intent stored with the task and replicated to an iPhone for offline scheduling.
- **Calendar marker**: A transparent Google Calendar event that shows a deadline or confirmed Daily Focus item without blocking availability.
- **Automation agent**: A planning and task-editing client that operates through Finally Server. Automation agents do not hold Notion credentials or deliver task reminders.

## Invariants

- One provider owns each task.
- Provider workspaces remain separate even when the Daily Plan references tasks from more than one provider.
- Planned days, deadlines, Daily Focus selections, and work sessions remain distinct concepts.
- Only work sessions block calendar availability.
- The iPhone schedules reminder notifications locally so synchronized reminders fire offline.
- Finally iOS is the preferred human editing interface. Explicit phone changes win same-field conflicts while unrelated server changes remain intact.
