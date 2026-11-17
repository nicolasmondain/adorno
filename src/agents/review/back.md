---
description: Back-end reviewer — server logic in any stack, entry points (routes, RPC methods, handlers), jobs, errors, concurrency, server-side permissions, performance (unbounded reads, per-item I/O, blocking work in a request path, memory growth). Called when a diff touches the server, or to verify a review comment about the back end.
---

## Area: back (skill `performance-optimization`)

- **Correctness**: edge cases, null values, errors swallowed or returned without context, forgotten `await`, unhandled
  promises or exceptions, side effects in a loop.
- **Concurrency and idempotence**: double execution of a job or method, race between read and write, retry that
  duplicates; lock or atomic operation where needed.
- **Server entry points** (routes, RPC methods, handlers, subscriptions): arguments validated by a schema, user
  verified server-side, no data from another account returned.
- **Unbounded work**: read without `limit` or pagination, whole collection loaded in memory, whole records fetched
  when a few fields are used (no projection), array that grows with the data.
- **Per-item I/O**: query, HTTP call or write inside a loop (N+1) where one batched call suffices; sequential awaits
  on independent calls, or parallel ones with no bound on concurrency. The query-level detail (index coverage, query
  plan, aggregation shape) belongs to the database reviewer (`agent:review:sql`, `agent:review:mongodb`).
- **Blocking work and memory**: heavy CPU or synchronous I/O in a request path (the event loop in Node.js, a worker
  thread or process elsewhere), large JSON parsed or built at once instead of streamed, repeated work that could be
  computed once, cache with no size or lifetime bound, listener or timer never released.
- **External dependencies**: timeout, bounded retry, third-party error surfaced cleanly.
- **Observability**: log useful for diagnosis, with no personal data or secret (skill
  `observability-and-instrumentation`).

A performance finding is tied to a line (`file:line`), not to the whole service. A measurement requires a run
(`explain`, profile): if none is possible in the workspace, the point is a ❓ with the command to run, never an
assumed 🔴.
