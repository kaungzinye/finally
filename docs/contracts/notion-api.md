# Contract: Notion API Integration

**Date**: 2026-03-13

## API Base

- **Base URL**: `https://api.notion.com/v1`
- **Version Header**: `Notion-Version: 2022-06-28`
- **Auth Header**: `Authorization: Bearer {access_token}`

## Endpoints Used

### OAuth Token Exchange (via Vercel proxy)

```
POST /api/notion/token   (Vercel serverless function)

Request:
{
  "code": "string"          // Authorization code from OAuth callback
}

Response (200):
{
  "access_token": "ntn_...",
  "workspace_id": "string",
  "workspace_name": "string",
  "bot_id": "string"
}

Response (400):
{
  "error": "invalid_grant" | "invalid_request",
  "message": "string"
}
```

### Retrieve Database (Schema Validation)

```
GET /v1/databases/{database_id}

Response (200):
{
  "id": "string",
  "title": [{ "plain_text": "string" }],
  "properties": {
    "{property_name}": {
      "id": "string",
      "type": "title" | "status" | "date" | "select" | "multi_select" | "relation" | ...,
      // Type-specific config (options, groups, etc.)
    }
  }
}
```

### Query Database (Fetch Tasks/Projects)

```
POST /v1/databases/{database_id}/query

Request:
{
  "filter": {                          // Optional
    "timestamp": "last_edited_time",   // For incremental sync
    "last_edited_time": {
      "on_or_after": "2026-03-13T00:00:00Z"
    }
  },
  "sorts": [
    { "property": "Due Date", "direction": "ascending" }
  ],
  "page_size": 100,
  "start_cursor": "string"            // For pagination
}

Response (200):
{
  "results": [
    {
      "id": "page-uuid",
      "last_edited_time": "2026-03-13T12:00:00Z",
      "properties": { ... }
    }
  ],
  "has_more": true | false,
  "next_cursor": "string" | null
}
```

### Create Page (Create Task)

```
POST /v1/pages

Request:
{
  "parent": { "database_id": "{tasks_database_id}" },
  "properties": {
    "Name": { "title": [{ "text": { "content": "Task title" } }] },
    "Status": { "status": { "name": "Not started" } },
    "Due Date": { "date": { "start": "2026-03-15" } },
    "Priority": { "select": { "name": "High" } },
    "Tags": { "multi_select": [{ "name": "Tag1" }, { "name": "Tag2" }] },
    "Project": { "relation": [{ "id": "project-page-id" }] },
    "Recurrence": { "select": { "name": "Weekly" } }
  }
}
```

### Update Page (Edit Task / Complete Recurring Task)

```
PATCH /v1/pages/{page_id}

Request:
{
  "properties": {
    "Status": { "status": { "name": "Not started" } },
    "Due Date": { "date": { "start": "2026-03-20" } }
  }
}
```

## Error Handling

| HTTP Status | Meaning | App Behavior |
|-------------|---------|-------------|
| 200 | Success | Process response |
| 400 | Bad request | Log error, show user-friendly message |
| 401 | Unauthorized (token revoked) | Clear session, prompt re-authentication |
| 404 | Database/page not found | Show error, suggest re-connecting databases |
| 409 | Conflict | Retry with fresh data |
| 429 | Rate limited | Read `Retry-After`, retry with exponential backoff, show "Syncing..." |
| 5xx | Server error | Retry with backoff, show "Notion is unavailable" after 3 failures |
