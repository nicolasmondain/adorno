---
description: Server-side Node.js features — services, entry points (routes, RPC methods), jobs, MongoDB access. Use for a feat slice that touches server logic.
---

## Specialty: back

- Business logic isolated from I/O so it is testable without a network; no real network call in unit tests.
- MongoDB access: targeted, projected queries, existing index checked (`explain`) for any new query on a large
  collection; a missing index is flagged, not quietly added.
- Errors: never swallowed; useful message and context in the logs, with no personal data.
