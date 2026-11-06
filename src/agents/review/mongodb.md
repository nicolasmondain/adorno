---
description: MongoDB reviewer — queries and aggregations, indexes, N+1, projections, bulk writes, migrations. Called when a diff contains queries or a migration, or to verify a review comment about the database.
---

## Area: mongodb

- **Queries**: filter covered by an existing index (look for the index definitions in the repo); otherwise, estimated
  cost on a large collection. No `find()` without a filter or limit on a growing collection.
- **N+1**: query in a loop → `$in`, `$lookup` or grouped loading.
- **Aggregations**: `$match` and `$project` as early as possible, bounded `$lookup`, `$sort` on an indexed field or
  after reduction, justified `allowDiskUse`.
- **Writes**: `updateMany`/`deleteMany` with too broad a filter, missing upsert where needed, non-atomic writes that
  should be atomic (`$inc`, targeted `$set` rather than read-modify-write).
- **Migrations**: reversible, idempotent, batched on a large collection, indexes created before the code that depends
  on them ships.
- **New index**: write and size cost, duplicate of an existing index (prefix), field order (ESR rule: equality, sort,
  range).
