# Specification: Finally Server and the Focused Execution Loop

## Problem Statement

The current self-hosted task system stores agent-managed tasks in Vikunja, but the available mobile client does not provide the task model or interface required for reliable execution. Finally provides a stronger iPhone experience and richer planning concepts, but it is tied to Notion and cannot serve as a shared task system for automation clients.

Large daily task lists also create a harmful execution pattern: seeing more planned work than available capacity produces an immediate sense of being behind, which leads to avoiding the system instead of completing work. A useful system must protect attention, distinguish obligations from intentions and scheduled effort, preserve offline reminders, and still expose enough calendar context to make realistic plans.

The product also remains open source and customizable without making every installation redefine the meaning of a task. Finally therefore needs an opinionated canonical model, bounded customization, independently synchronized providers, and a self-hosted server that implements the model without compromising it to fit stock Vikunja behavior.

## Solution

Finally Server is a public, self-hosted task provider derived from Vikunja. It implements Finally's canonical task model as first-class server concepts and becomes the authoritative self-hosted task store shared by Finally iOS and authorized automation clients. It runs beside the existing Vikunja service during validation, receives a complete verified migration, and replaces Vikunja after cutover.

Finally iOS remains the primary human interface and supports separate Finally Server and Notion workspaces. Tasks never copy automatically between providers. A provider-neutral planning layer accepts minimal read-only projections from both providers and produces one Daily Plan with a bounded focus list. An authorized automation agent proposes up to three focus tasks in the evening, the user confirms in the morning, and urgent additions replace an existing focus task instead of expanding the list.

Finally Server reads multiple authorized Google Calendar accounts when planning and publishes confirmed work sessions, deadlines, and Daily Focus markers to three dedicated calendars. Work sessions reserve time; deadline and focus markers remain transparent. V1 treats Google Calendar as a visible execution plan rather than a second editing surface.

Finally Server stores canonical reminder rules, while each iPhone schedules a local replica so synchronized notifications fire without internet access. Automation clients edit tasks through the same server API but do not deliver reminders or hold Notion credentials.

## User Stories

1. As a user, I want Finally Server to preserve Finally's task model, so that the workflow does not shrink to the capabilities of a generic task server.
2. As a user, I want automation clients and Finally iOS to operate on the same tasks, so that conversational and direct edits remain consistent.
3. As a user, I want Finally Server to replace Vikunja only after validation, so that the cutover does not endanger current tasks.
4. As a user, I want every existing Vikunja project and task migrated, so that adopting Finally Server does not require starting over.
5. As a user, I want migration counts and representative records verified, so that I can trust the imported data.
6. As a user, I want original Vikunja identifiers retained as migration metadata, so that records remain traceable during rollback and diagnosis.
7. As a user, I want unsupported migration data reported explicitly, so that silent loss cannot occur.
8. As a user, I want current Vikunja backups retained through cutover, so that I can restore the previous service if validation fails.
9. As a user, I want self-hosted tasks to remain separate from collaborative Notion tasks, so that each workspace retains one authority.
10. As a user, I want Finally iOS to switch between Finally Server and Notion workspaces, so that one interface serves both contexts.
11. As a user, I want the same canonical task vocabulary in both workspaces, so that changing providers does not change how I think about tasks.
12. As a user, I want Notion fields mapped to canonical Finally concepts, so that collaborative tasks retain planned days, deadlines, priorities, projects, labels, recurrence, and subtasks where configured.
13. As a user, I want Finally Server concepts implemented natively, so that automation and other API clients can understand them without device-only guesses.
14. As a user, I want a task to have no required deadline, so that Inbox tasks and intentions do not receive invented urgency.
15. As a user, I want an optional planned day, so that I can express when I intend to work without claiming a hard obligation.
16. As a user, I want an optional date-only or timed deadline, so that the system represents real constraints accurately.
17. As a user, I want planned days and deadlines to remain distinct, so that changing an intention does not move an obligation.
18. As a user, I want three explicit task states, so that not-started, in-progress, and completed work remain distinct.
19. As a user, I want projects, labels, priorities, assignees, and task relations, so that migrated Vikunja organization remains useful.
20. As a user, I want subtasks to remain real tasks, so that hierarchy, reminders, and recurrence behavior remain consistent.
21. As a user, I want actionable subtasks surfaced ahead of non-actionable parents, so that the execution view presents concrete work.
22. As a user, I want a task to contain zero or more work sessions, so that complex tasks can receive several periods of protected time.
23. As a user, I want moving a work session to leave the task deadline unchanged, so that schedule changes do not rewrite obligations.
24. As a user, I want completing a work session to leave the task open, so that effort and outcome remain separate.
25. As a user, I want completing a task to remove or cancel future sessions, so that stale blocks do not remain on my calendar.
26. As a user, I want recurring obligations distinguished from recurring calendar routines, so that Finally does not duplicate the calendar's role.
27. As a user, I want one stable recurring task identity, so that the obligation remains recognizable across cycles.
28. As a user, I want each recurring cycle recorded in lightweight history, so that completion evidence is preserved.
29. As a user, I want recurrence to advance planned days and deadlines according to its rule, so that the next obligation appears correctly.
30. As a user, I want recurring subtasks reset according to policy, so that repeated checklists remain usable.
31. As a user, I want the planning agent to propose fresh work sessions for every recurrence cycle, so that old calendar slots do not repeat into conflicting schedules.
32. As a user, I want one Daily Plan shared across providers, so that my attention limit reflects all work rather than one database.
33. As a user, I want Daily Focus to reference tasks without changing their planned days or deadlines, so that selection remains a planning decision.
34. As a user, I want the default Daily Focus limit to be three, so that the execution surface does not overwhelm me.
35. As a user, I want a bounded focus-limit setting from one to five, so that the open-source product supports different capacities without an unlimited execution view.
36. As a user, I want focus-limit changes to remain deliberate, so that frequent configuration does not undermine the attention boundary.
37. As a user, I want a planning agent to propose tomorrow's focus tasks in the evening, so that capacity conflicts become visible before the day begins.
38. As a user, I want to confirm the proposal in the morning, so that current energy and changed commitments influence the final plan.
39. As a user, I want to accept, replace, or defer proposed tasks, so that automation supports rather than removes my agency.
40. As a user, I want one current task and at most two next tasks in the execution view, so that the backlog does not compete for attention.
41. As a user, I want the remaining backlog hidden from the execution view, so that stored obligations do not appear as simultaneous failures.
42. As a user, I want an urgent task to replace one focus task, so that urgency does not expand the attention limit.
43. As a user, I want the planning agent to ask which task moves out of focus, so that displacement remains explicit.
44. As a user, I want unfinished focus tasks deliberately replanned, so that automatic rollover does not create a growing overdue wall.
45. As a user, I want replanning to offer keep, break down, schedule, defer, or drop, so that an unfinished task produces a useful next decision.
46. As a user, I want Notion tasks eligible for Daily Focus, so that collaborative obligations compete honestly for limited attention.
47. As a user, I want Finally iOS to publish a minimal Notion planning projection, so that a planning agent can rank Notion tasks without Notion credentials.
48. As a user, I want automation clients prevented from editing source Notion tasks, so that the collaboration boundary remains intact.
49. As a user, I want edits to selected Notion tasks routed through Finally iOS, so that Notion remains authoritative.
50. As a user, I want the planning agent to read multiple authorized Google Calendar accounts, so that proposals account for my complete schedule.
51. As a user, I want the planning agent to understand event titles, descriptions, locations, attendees, recurrence, and response status, so that it can distinguish meetings, travel, focus time, and flexible holds.
52. As a user, I want full calendar content fetched when planning rather than copied permanently, so that scheduling context does not become a second archive.
53. As a user, I want Finally Server to store only durable synchronization metadata and derived constraints for existing events, so that backups and logs minimize copied calendar content.
54. As a user, I want the planning agent to suggest work-session slots, so that planning uses real free time.
55. As a user, I want to confirm every proposed session before publication, so that AI suggestions do not silently occupy my calendar.
56. As a user, I want only tasks that need protected attention to receive sessions, so that quick actions do not clutter the calendar.
57. As a user, I want Google Calendar to show confirmed work sessions, so that I can see the execution plan beside existing commitments.
58. As a user, I want genuine deadlines visible on Google Calendar, so that constraints remain visible while scheduling.
59. As a user, I want only confirmed Daily Focus tasks shown as planned-day markers, so that every intention does not become a calendar obligation.
60. As a user, I want Work Sessions, Deadlines, and Daily Focus on separate calendars, so that I can toggle the layers independently.
61. As a user, I want deadline and focus markers to remain transparent, so that they do not consume free/busy capacity.
62. As a user, I want work sessions to mark me busy, so that other scheduling tools respect protected time.
63. As a user, I want one chosen Google account to own the three calendars, so that work sessions and markers do not duplicate across accounts.
64. As a user, I want V1 calendar publication to flow from Finally Server to Google, so that I gain calendar visibility without unreliable two-way synchronization.
65. As a user, I want Google-side edits excluded from V1 synchronization, so that the first release has one clear editing authority.
66. As a user, I want Finally Server to own deterministic calendar publication, so that the planning agent remains a reasoning layer rather than a synchronization daemon.
67. As a user, I want task reminder rules stored on Finally Server, so that reminders survive reinstall and remain shared task state.
68. As a user, I want reminder rules replicated to my phone, so that the device can schedule them locally.
69. As a user, I want synchronized reminders to fire while offline, so that notifications do not depend on the server, Google, or an AI provider.
70. As a user, I want the app to prioritize and replenish the nearest pending notifications, so that it respects iOS scheduling limits.
71. As a user, I want exact reminders to remain fixed, so that changing a task date does not move an independent appointment with myself.
72. As a user, I want anchored reminders to move with their planned day or deadline, so that reminder intent remains meaningful.
73. As a user, I want chat integrations excluded from reminder delivery, so that messaging outages do not affect notification reliability.
74. As a user, I want a chat integration to remain an optional manual editing surface, so that conversational task management stays available.
75. As a user, I want the app to show reminder scheduling state for this iPhone, so that I know which notifications are ready to fire offline.
76. As a user, I want stale automation edits rejected, so that an AI action cannot silently overwrite a newer phone edit.
77. As a user, I want my explicit phone edit reapplied over the latest task revision, so that direct human intent has priority.
78. As a user, I want unrelated automation edits preserved when the phone wins one field, so that conflict handling does not discard valid work.
79. As a user, I want completion and deletion conflicts surfaced rather than resolved silently, so that destructive state remains trustworthy.
80. As a user, I want the inherited web client limited to read-only task viewing and administration, so that an incomplete UI cannot corrupt richer task semantics.
81. As an open-source user, I want Finally Server published under its inherited license, so that I can inspect, self-host, and modify it lawfully.
82. As an open-source contributor, I want provider and API contracts documented, so that additions do not depend on private knowledge.
83. As a maintainer, I want Finally iOS and Finally Server in separate repositories, so that their MIT and AGPL codebases remain independently maintainable.
84. As a maintainer, I want a versioned OpenAPI contract between repositories, so that generated Swift clients and server releases remain compatible.
85. As a maintainer, I want `main` as the sole long-lived product branch, so that current development has one clear base.
86. As a maintainer, I want product changes squash-merged, so that each commit describes one resulting behavior.
87. As a maintainer, I want upstream Vikunja synchronization represented by explicit merges, so that inherited history remains traceable.
88. As a maintainer, I want secrets and personal deployment data excluded from public repositories, so that open development does not expose private infrastructure.

## Implementation Decisions

- Finally's canonical model is opinionated. Bounded configuration covers focus limits, views, labels, priorities, field visibility, defaults, and provider mappings. Semantic alternatives remain distributions or forks rather than arbitrary runtime schemas.
- Finally Server lives in a separate public repository derived from Vikunja and inherits AGPL-3.0-or-later. Finally iOS remains in its MIT-licensed repository.
- Finally Server runs as a distinct service beside Vikunja during validation. It uses its own persistent data location, public HTTPS endpoint, service unit, and backup schedule. It replaces Vikunja after migration validation and cutover.
- The inherited Vikunja web client provides read-only task viewing and basic administration in V1. Finally iOS and authorized automation clients are the task-editing surfaces.
- Finally Server preserves Vikunja projects, permissions, labels, assignees, attachments, relations, comments, exports, and backup behavior where they remain compatible with the canonical model.
- The task model contains stable identity, title, description, status, optional planned day, optional deadline, priority, project, parent, subtask order, suggested-day override, labels, assignees, recurrence rule and policy, board placement, creator, timestamps, revision, and recoverable deletion state.
- `plannedDay` is a date-only intention. `deadline` is either date-only or timed. Neither field is required.
- Reminder rules, work sessions, recurrence-cycle history, relations, comments, and attachments are linked records rather than repeated scalar task fields.
- V1 does not add persistent effort estimates. The planning agent proposes a work-session duration when needed and the user confirms it.
- One task has zero or more work sessions. Each session stores stable identity, task reference, start, end, publication identity, and lifecycle timestamps.
- One recurring obligation retains one stable task identity. Completion closes a cycle, records cycle history, advances dates, resets state according to policy, and requests fresh scheduling proposals.
- Daily Focus belongs to a provider-neutral Daily Plan rather than a task field. A plan identifies its date, ordered selected task references, configured limit, and confirmation state.
- The focus limit defaults to three and supports values from one through five. The user's initial profile remains fixed at three for 30 days.
- The planning agent prepares the next-day proposal in the evening and requests morning confirmation. It considers deadlines, priority, dependencies, planned days, available calendar time, neglected work, and the read-only Notion planning projection.
- An urgent task enters Daily Focus only by replacing another selection. Unfinished tasks return to explicit replanning instead of automatic rollover.
- Notion and Finally Server remain separate authoritative providers. There is no automatic task copying or cross-provider synchronization.
- The Notion planning projection contains provider identity, task identity, title, status, planned day, deadline, priority, project name, and last-updated timestamp. It is read-only and is refreshed by Finally iOS.
- The planning agent may rank and schedule projected Notion tasks but may not mutate them. Finally iOS routes source edits through the Notion adapter.
- Finally Server owns Google OAuth credentials, calendar reads required for planning, and V1 calendar publication. Both authorized Google accounts permit read-only access to full event context with the user's consent.
- Existing event bodies and attendee details are fetched on demand and are not copied into backups, logs, embeddings, external notes, or permanent task storage. Durable state retains connection metadata, sync cursors, event identifiers required for publication, and derived scheduling constraints.
- One chosen Google account owns three secondary calendars named `Work Sessions`, `Deadlines`, and `Daily Focus`.
- Work Sessions contains confirmed timed sessions and marks them busy. Deadlines contains genuine deadline markers. Daily Focus contains markers only for confirmed focus selections. Deadline and focus markers remain transparent.
- V1 calendar synchronization is one-way from Finally Server to Google Calendar. Google-side drag, resize, deletion, push notifications, incremental reverse sync, and conflict repair belong to V2.
- Finally Server owns canonical reminder rules. Finally iOS replicates them and schedules native local notifications. Synchronized reminders fire offline. Server-side changes reach an offline phone after its next connection.
- Chat integrations are optional conversational surfaces for explicit task mutations. They are not notification-delivery channels.
- Every mutable server entity carries a revision or equivalent ETag. Automation clients submit narrow field patches. Stale automation writes fail. Finally iOS fetches the current revision and reapplies the explicit phone patch; the phone wins same-field conflicts while unrelated changes survive.
- Completion and deletion conflicts require explicit handling and never resolve silently.
- Migration imports all supported Vikunja data, retains legacy identifiers, reports unsupported records, verifies counts and sampled content, and preserves source dumps and a read-only source service until cutover acceptance.
- Finally Server publishes a versioned OpenAPI description. Finally iOS generates its server client from that contract.
- `main` is the only long-lived product branch in each repository. Product pull requests squash into `main`. Explicit merge commits synchronize upstream Vikunja releases into Finally Server.

## Testing Decisions

- Tests assert observable product and API behavior, not SwiftUI layout structure, private mapper functions, database table names, or inherited Vikunja internals.
- The highest acceptance seam executes one canonical lifecycle through a provider adapter and local store: create a task, set planned day and deadline, add an offline reminder, select it in a Daily Plan, confirm a work session, publish calendar artifacts, complete the task, and reconcile provider state.
- A provider conformance suite runs canonical create, read, update, complete, recurrence, delete, and conflict scenarios against Finally Server and the Notion adapter using deterministic provider doubles. Live provider E2E tests remain separately gated by credentials.
- Finally Server API acceptance tests run against a temporary real database and verify authentication, permissions, canonical fields, revisions, stale writes, Daily Plans, work sessions, recurrence cycles, reminder rules, exports, and recoverable deletion.
- Migration tests restore representative Vikunja dumps, run the migration, compare entity counts and relationships, inspect unsupported-data reports, and exercise rollback without touching production data.
- Daily Plan tests verify the configured one-to-five bound, default three-task behavior, ordered selections, cross-provider references, explicit replacement for urgent work, and absence of automatic rollover.
- Planning-agent contract tests verify evening proposals, morning confirmation, calendar-aware slot suggestions, explicit user approval, selective time blocking, and lack of source mutation for projected Notion tasks.
- Calendar adapter tests use a deterministic Google Calendar double and verify the three calendar names, busy versus transparent availability, event identity, idempotent publication, update and removal from server-side changes, two-account reads, and no reverse mutation in V1.
- Calendar privacy tests verify that raw descriptions, attendees, meeting links, and attachments do not enter durable task storage, logs, backups, embeddings, or notes.
- Reminder tests use a notification-scheduler double and verify anchored versus exact resolution, offline scheduling, cancellation, rescheduling, per-device status, and replenishment within the iOS pending-notification limit.
- Conflict tests cover stale automation patches, phone-wins same-field edits, preservation of unrelated fields, and explicit completion or deletion conflicts.
- Recurrence tests cover stable task identity, cycle history, planned-day and deadline advancement, subtask reset policy, reminder reuse, and absence of automatically recurring work sessions.
- Existing backend data-flow integration tests provide prior art for the highest iOS sync seam. Existing Notion mapping, notification, recurrence, task-model, data-migration, and E2E round-trip tests provide prior art for focused contracts.
- Release verification includes an iOS build, relevant simulator tests, server test suite, migration dry run, API compatibility check, backup verification, and a parallel-deployment smoke test through an automation client and Finally iOS.

## Out of Scope

- Automatic copying or bidirectional synchronization between Notion tasks and Finally Server tasks
- Automation clients holding Notion credentials or directly mutating Notion
- Full task editing in the inherited Vikunja web client
- A new Finally web interface
- Two-way Google Calendar editing, drag and resize synchronization, Google push channels, reverse incremental sync, or automatic calendar conflict repair
- Cal.com integration
- Automatic work-session placement without confirmation
- Persistent effort estimates, actual-versus-estimated analytics, or adaptive scheduling models
- Automatic recurring work-session series
- Deadline-overlay personalization beyond the three defined V1 calendars
- Chat-based reminder delivery
- iPad-specific Finally layouts, Mac Catalyst optimization, or Apple Watch complications
- Arbitrary user-defined task schemas or an in-process plugin runtime

## Further Notes

- Vikunja's normal REST task writes do not provide the stale-write behavior required here, although its CalDAV implementation demonstrates conditional writes. Finally Server adds revision-aware writes to the primary API.
- Vikunja already provides projects, labels, priorities, relations, reminders, recurrence, exports, API tokens, and webhooks. Finally Server extends this base with Finally's first-class semantics instead of recreating the entire service.
- Google Calendar supports read-only event access, secondary calendars, hidden event metadata, and direct event creation. V1 uses those capabilities without adding Cal.com as a third stateful system.
- The local specification package for the existing iOS application separates provider-independent product behavior from the Notion adapter contract. This specification owns the new provider-neutral planning and server behavior.
