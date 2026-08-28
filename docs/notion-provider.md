# Provider Specification: Notion

## Problem Statement

People whose tasks live in their own Notion need Finally to present and edit those tasks with zero infrastructure, without copying them into another authoritative task store. Notion mode is the app's front door. Notion workspaces vary in schema and permissions, so the adapter must validate and map each workspace explicitly.

## Solution

The Notion provider authenticates through OAuth, lets the user select task and project databases, validates their schemas, maps Notion pages to Finally's canonical task model, and synchronizes changes in both directions. Notion remains authoritative for tasks in this workspace. Finally stores a local cache and device-only delivery state while preserving provider identifiers and synchronization metadata.

## User Stories

1. As a Notion user, I want to connect through OAuth, so that I do not paste an integration secret into the app.
2. As a Notion user, I want to select the databases shared with Finally, so that the integration accesses only intended content.
3. As a Notion user, I want Finally to remember the authorized workspace securely, so that I do not authenticate on every launch.
4. As a Notion user, I want the app to validate required properties, so that mapping errors surface before synchronization.
5. As a Notion user, I want to map ambiguous properties, so that custom database names remain supported.
6. As a Notion user, I want project relations to appear as Finally projects, so that organization remains consistent.
7. As a Notion user, I want native parent-child relations to appear as Finally subtasks, so that both interfaces show the same hierarchy.
8. As a Notion user, I want Finally edits to update the corresponding Notion page, so that Notion collaborators see current state.
9. As a Notion user, I want direct Notion edits to update Finally, so that the iPhone cache does not drift.
10. As a Notion user, I want incremental synchronization, so that routine refreshes remain efficient.
11. As a Notion user, I want a full reconciliation path, so that deletion and missed-change recovery remain correct.
12. As a Notion user, I want dirty local edits protected during a pull, so that remote refresh does not discard unfinished phone work.
13. As a Notion user, I want clear read-versus-write permission errors, so that restricted databases fail safely.
14. As a workspace member, I want onboarding to reflect the permissions Notion actually grants, so that the app does not assume owner access.
15. As a user, I want revoked authorization detected, so that the app prompts me to reconnect.
16. As a user, I want paginated databases synchronized completely, so that large workspaces do not omit tasks.
17. As a user, I want provider rate limits retried with bounded backoff, so that transient throttling does not lose edits.
18. As a user, I want a setup guide for the required Notion schema, so that I can repair unsupported databases.
19. As a user, I want task page notes available when the provider supports a stable body-content API, so that task context is not hidden.
20. As a user, I want provider changes to reach the app promptly, so that collaboration does not depend solely on manual refresh.

## Implementation Decisions

- Notion tasks remain in a separate workspace and never synchronize automatically into Finally Server tasks.
- The adapter maps Notion title, status, date, select, multi-select, and relation properties to canonical Finally fields.
- `plannedDay` maps to a dedicated Notion date property. `deadline` maps to a separate Notion date property.
- Priority maps to a select property, labels map to a multi-select property, projects map to the Projects database relation, and subtasks map to a native parent-child relation.
- Provider recurrence properties encode the recurrence rule while Finally applies the canonical recurrence behavior.
- Reminder rules synchronize through Finally's device-support layer because Notion does not provide the required anchored-reminder model.
- OAuth access tokens remain in Keychain on the phone. Client secrets remain in a server-side token-exchange component.
- The adapter detects schema by property type and requests an explicit choice when multiple properties are plausible.
- The provider stores page IDs, last-edited timestamps, property mappings, sync cursors, and dirty-state metadata.
- Incremental pulls do not infer remote deletion. Full reconciliation determines deletion after protecting dirty local records.
- A permission failure distinguishes missing access, read-only access, revoked authorization, and rate limiting.
- Webhook or event-driven synchronization remains an optimization over a correct pull-based reconciliation path.

## Testing Decisions

- The highest provider seam is the adapter contract exercised against a mock Notion API client and an in-memory local store.
- Contract tests cover schema validation, property mapping, pagination, create, update, completion, recurrence, deletion reconciliation, permissions, rate limiting, and dirty-record protection.
- End-to-end tests use a dedicated Notion workspace only when credentials are explicitly configured.
- Tests assert canonical task results and outbound provider payloads rather than private mapper methods.
- Existing backend data-flow, Notion data-shape, schema-validator, mapping-integration, and E2E round-trip tests provide prior art.

## Out of Scope

- Automatic copying between Notion mode workspaces and Finally Server
- Hermes holding Notion mode credentials or ranking Notion mode tasks
- Creating a user's Notion databases automatically
- Treating a Notion mode workspace as the store for work sessions or the Daily Focus
- The Notion surface, which belongs to Finally Server and syncs server tasks into a dedicated Notion database
- Provider-specific behavior in shared SwiftUI views
- Real-time collaborative editing inside Finally

## Further Notes

The provider implementation can evolve from polling to webhook-triggered refresh without changing the canonical task interface. Deployment choices for the token exchange and webhook relay remain provider infrastructure and do not define Finally's product model.
