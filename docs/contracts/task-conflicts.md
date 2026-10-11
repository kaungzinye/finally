# Task conflicts

Issue #15 defines phone-priority task writes. Finally Server task reads and lists expose `revision`.

`PUT /api/v2/finally/tasks/{id}` accepts a narrow patch:

```json
{
  "base_revision": 7,
  "client": "phone",
  "fields": { "due_date": "2026-10-20T18:00:00Z" }
}
```

The supported fields are `title`, `done`, `start_date`, `due_date`, and `priority`. Omitted fields retain accepted values. Null clears a date. Title, completion, and priority require values. Priority ranges from zero to four.

An API write whose submitted field changed after its base revision receives HTTP 409 with `current` and `conflicting_fields`. Unrelated fields merge. An explicit phone edit wins a same-field API change; a concurrent phone edit requires review. The server claims each revision and applies its fields in one transaction.

Completion and reopening use `done: true` and `done: false` in the same patch as any other edits. The completion action and deletion require `base_revision` and `client` query parameters. Deletion requires the exact accepted revision for every client. A deleted task returns HTTP 404. Revisioned tasks use the Finally conditional endpoints for canonical changes; inherited task updates, deletes, and done-bucket changes enforce that rule. The conditional PUT owns the partial-write contract, and its generated AutoPatch route is disabled.

The phone persists the accepted snapshot and its revision, submits changed fields, and preserves edits made during an awaited push. Pulls preserve dirty edits. A conflict review shows the phone intent and accepted state. The user keeps phone edits or accepts server state. A remotely deleted task finishes a pending phone deletion; a saved phone edit offers discard or creation as a new task.

`PhonePriorityConflictTests`, the server `TestFinallyPhonePriorityConflicts`, and `TestFinallyTaskBucketProtectsCompletion` verify these rules.
