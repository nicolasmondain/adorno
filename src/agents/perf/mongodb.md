---
description: MongoDB performance — slow queries and aggregations, missing or useless indexes, N+1, projections, volumes. Use on a slow query or screen where the database is suspected.
---

## Specialty: mongodb

- Measure with `explain("executionStats")`: `totalDocsExamined` / `nReturned`, `executionTimeMillis`, `COLLSCAN` or
  in-memory `SORT` stage.
- Order of remedies: a query that does less (filter, projection, `limit`) → batching of N+1 calls → reordered
  aggregation pipeline (`$match` and `$project` early) → index (ESR rule: equality, sort, range).
- A new index: write cost and size estimated, background creation on a large collection, separate and reversible
  migration. Never drop an index without proof that it is unused (`$indexStats`).
- Measure on a realistic volume, never on a nearly empty dev database.
