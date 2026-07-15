# Product Interface Specification: Finally for iPhone

## Problem Statement

People need a focused native iPhone interface for capturing, planning, reviewing, and completing tasks without adopting a provider's own interface. Provider limitations must not dictate Finally's interaction model, reminders, recurrence behavior, or offline experience.

## Solution

Finally presents one provider-independent task experience backed by a local SwiftData cache. Provider adapters translate the canonical product concepts to their remote systems. The interface uses Todoist-style inline capture, focused task views, chip-based editing, local notifications, recurrence, subtasks, and widgets.

## User Stories

1. As a user, I want to connect a supported task workspace, so that I can use Finally with the task store appropriate to that workspace.
2. As a user, I want Inbox, Today, Upcoming, Search, Board, and Project views, so that I can find work by execution context.
3. As a user, I want overdue work separated from work planned for today, so that urgency remains legible.
4. As a user, I want to create a task inline, so that capture interrupts me as little as possible.
5. As a user, I want natural-language shortcuts for dates, priorities, projects, and labels, so that capture remains fast.
6. As a user, I want selected values displayed as editable chips, so that task structure remains visible without a large form.
7. As a user, I want an optional planned day and an optional deadline, so that intention remains distinct from obligation.
8. As a user, I want a deadline to support either a date or a specific time, so that the model represents both day-level and timed constraints.
9. As a user, I want priority, labels, and projects, so that I can organize and filter work.
10. As a user, I want parent tasks and actionable subtasks, so that large outcomes break into manageable work.
11. As a user, I want the interface to surface actionable subtasks ahead of non-actionable parents, so that I know what to do next.
12. As a user, I want a three-state workflow, so that not-started, in-progress, and completed work remain distinct.
13. As a user, I want to move tasks across Board columns, so that workflow changes feel direct.
14. As a user, I want multiple reminders anchored to the planned day or deadline, so that reminders move when the underlying plan moves.
15. As a user, I want exact-time reminders, so that some notifications remain fixed even when task dates change.
16. As a user, I want reminders to fire through native iPhone notifications without an internet connection, so that delivery does not depend on server availability.
17. As a user, I want the app to show whether a reminder is scheduled on this device, so that I can trust notification delivery.
18. As a user, I want recurring obligations to advance after completion, so that repeated work remains manageable.
19. As a user, I want recurring subtasks to reset for the next cycle, so that a repeated checklist remains useful.
20. As a user, I want reminder rules to apply to each new recurrence cycle, so that notification intent persists.
21. As a user, I want swipe and bulk actions, so that routine task maintenance remains quick.
22. As a user, I want cached tasks while offline, so that I can still review my plan without connectivity.
23. As a user, I want unsynchronized edits retained until they succeed, so that transient failures do not lose work.
24. As a user, I want system, light, and dark appearance options, so that Finally fits my display preference.
25. As a user, I want small, medium, and large widgets, so that selected tasks remain visible from the Home Screen.
26. As a user, I want widget actions to open the relevant task or capture flow, so that the widget provides a useful entry point.
27. As a user, I want notification taps to open the relevant task, so that I can act immediately.
28. As a user, I want clear provider and permission errors, so that failures identify an actionable next step.

## Implementation Decisions

- The product targets iPhone on iOS 17 and later.
- SwiftUI owns the interface, SwiftData owns the local cache, WidgetKit owns widgets, and UserNotifications owns offline reminder delivery.
- The canonical product vocabulary uses `plannedDay` for an optional date-only intention and `deadline` for an optional date or date-time constraint.
- Reminder rules are canonical product data replicated to the phone. The phone schedules native local notifications in advance and replenishes the nearest notifications within iOS scheduling limits.
- Anchored reminders identify their anchor explicitly. Exact reminders remain independent of task dates.
- Recurrence and reminders remain separate concerns.
- Subtasks are tasks with parent relationships. Local presentation metadata may include subtask order and a suggested-day override.
- Provider adapters map canonical tasks to remote systems. Provider identifiers, authentication sessions, schema mappings, and synchronization cursors remain outside provider-independent views and models.
- The local cache retains dirty edits and provider revision metadata required for safe synchronization.
- Finally follows the system appearance by default and offers explicit light and dark overrides.
- The widget reads from shared app-group storage and deep-links into Finally for mutation flows that require the main app.

## Testing Decisions

- Tests assert externally visible task behavior rather than view implementation details.
- Provider-independent model tests cover planned-day and deadline validation, recurrence, subtask reset behavior, reminder serialization, and notification scheduling priority.
- View-model or feature-level tests cover Inbox, Today, Upcoming, Board, and project filtering.
- Notification tests use a scheduler test double and verify resolved fire dates, cancellation, rescheduling, and the iOS pending-notification limit.
- Widget contract tests verify the task selection presented to WidgetKit and the resulting deep links.
- Provider conformance scenarios run the same canonical create, update, complete, recurrence, and delete lifecycle against each adapter.
- Existing notification, recurrence, data-migration, task-model, and backend-flow tests provide the prior art.

## Out of Scope

- Provider-specific OAuth, schema validation, API pagination, rate limits, and webhooks
- iPad-specific layouts and Mac Catalyst optimization
- Apple Watch complications
- A full calendar grid inside Finally
- Real-time collaborative text editing
- Provider-specific database creation

## Further Notes

The current SwiftData implementation still uses Notion-specific identifiers in shared entities. The provider-neutral model specification replaces those identifiers through a separate migration rather than treating the current representation as the lasting product contract.
