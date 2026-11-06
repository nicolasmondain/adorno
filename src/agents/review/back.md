---
description: Back-end reviewer — Node.js server logic, entry points (routes, RPC methods, handlers), jobs, errors, concurrency, server-side permissions. Called when a diff touches the server, or to verify a review comment about the back end.
---

## Area: back

- **Correctness**: edge cases, null values, errors swallowed or returned without context, forgotten `await`, unhandled
  promises, side effects in a loop.
- **Concurrency and idempotence**: double execution of a job or method, race between read and write, retry that
  duplicates; lock or atomic operation where needed.
- **Server entry points** (routes, RPC methods, handlers, subscriptions): arguments validated by a schema, user
  verified server-side, no data from another account returned, no unbounded read.
- **External dependencies**: timeout, bounded retry, third-party error surfaced cleanly.
- **Observability**: log useful for diagnosis, with no personal data or secret (skill
  `observability-and-instrumentation`).
