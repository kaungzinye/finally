# Daily Focus loop

Daily Focus is one record for a calendar day. Its `confirmed` field represents the user's confirmation. The phone presents unconfirmed records for review and editing, and confirmed records as Current and Next. A picked parent presents its first unfinished subtask during execution.

Finally Server stores the record at `GET` and `PUT /api/v2/finally/projects/{project_id}/daily-focus/{yyyy-MM-dd}`. The authenticated client needs access to the project. The phone and Hermes use the same endpoint and task references. Notion mode stores Daily Focus on the phone.

When the user prompts Hermes to propose tomorrow's Daily Focus, Hermes reads the existing record and the project's open tasks, chooses up to the record's focus limit, and writes an unconfirmed record. The request uses this shape:

```json
{
  "picks": [
    {
      "provider": "finally-server",
      "workspace_id": "provider-workspace-identity",
      "external_task_id": "17"
    }
  ],
  "confirmed": false,
  "focus_limit": 3
}
```

Hermes uses the provider workspace identity configured for the phone's server connection. It preserves an existing confirmed record for the user's explicit review. Picks reference tasks; selecting and confirming them leaves task dates fixed. A proposal runs when the user prompts Hermes. The record's calendar date comes from the user's local calendar.

The phone confirms by writing the same project and day with `confirmed: true`. Reordering and editing preserve pick identity. A full Daily Focus accepts an urgent task through a replacement the user chooses, including a reference to an unavailable task. The focus limit remains one to five. Each day retains its limit; Settings supplies the limit for newly created days.

Replanning keeps each unfinished pick visible until the user decides. Keep places it in a later day's unconfirmed Daily Focus, with explicit displacement if that day is full. Break down requires an unfinished subtask and removes the parent pick after the user finishes that decision. Schedule sets a date-only planned day. Defer clears the planned day. Drop removes the focus pick and keeps the task and its dates. Task deadlines stay fixed through these decisions.

The phone saves all changed Daily Focus days together before attempting server writes. Failed writes leave dirty edits on the phone; the Daily Focus error banner retries all dirty days. Schedule and Defer also enter the task provider's dirty-edit pipeline and refresh local reminders.

`DailyFocusTests` exercises displacement, all replanning decisions, and date preservation. `DailyFocusServiceTests` exercises prompted writes through a mock API, confirmation on the same record, and offline recovery across both days. `maestro/daily-focus-demo.yaml` exercises the seeded phone flow.

The server route is in the server repository's `feat/ux-daily-focus` branch, commit `7867f8851`. Deployment of that route, Hermes account configuration, and the phone-priority concurrent edit contract in issue #15 are integration dependencies. The automated prompted-write test uses a mock API; a live Hermes conversation requires verification against the deployed server.
