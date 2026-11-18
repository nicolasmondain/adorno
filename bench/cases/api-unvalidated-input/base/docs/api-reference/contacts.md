# Contacts

The v1 API is public: customer integrations and the official SDKs depend on it.

## `GET /v1/contacts`

Lists the contacts of the account, newest first.

| Query parameter | Type | Description |
| --- | --- | --- |
| `limit` | integer | Page size, 50 by default, 200 at most. |

```json
{
  "items": [{ "_id": "con_1", "email": "ada@example.test", "createdAt": "2026-01-01T00:00:00.000Z" }],
  "total": 42
}
```

`total` is the number of contacts of the account, whatever the page size.
