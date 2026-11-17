---
description: Server-side features in any back-end stack — services, entry points (routes, RPC methods, handlers), jobs, database access. Use for a feat slice that touches server logic.
---

## Specialty: back

- Business logic isolated from I/O so it is testable without a network; no real network call in unit tests.
- Database access: targeted queries that read only the fields used, existing index checked (`explain`) for any new
  query on a large table or collection; a missing index is flagged, not quietly added.
- Errors: never swallowed; useful message and context in the logs, with no personal data.
