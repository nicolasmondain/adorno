---
description: SQL reviewer — relational queries through an ORM or raw SQL (ActiveRecord, Django ORM, database/sql, sqlx, GORM, knex…), N+1, indexes, unbounded reads, injection, migrations that lock a table. Called when a diff contains SQL, ORM queries or a migration on a relational database, or to verify a review comment about it.
---

## Area: sql

- **Queries**: filter and sort covered by an existing index (look for the schema, the migrations or `db/schema.rb`);
  otherwise, estimated cost on a large table. No read without `LIMIT` or pagination on a growing table; only the
  columns used (`only`, `values`, `pluck`, an explicit select list rather than `SELECT *`).
- **N+1**: a query per item in a loop or a serializer → eager loading (`select_related`/`prefetch_related`,
  `includes`/`preload`, a join or `WHERE id IN (…)`).
- **Injection**: values interpolated into a SQL string (`f"…{x}"`, `"#{x}"`, `fmt.Sprintf`, concatenation) instead of
  bound parameters; a dynamic column or sort name taken from an allowlist.
- **Writes and transactions**: read-modify-write that should be one atomic `UPDATE`, several writes that must succeed
  together outside a transaction, a long transaction holding locks across network calls, a bulk update without a
  bound.
- **Migrations**: no long lock on a large table (index built `CONCURRENTLY` or the engine's online equivalent,
  `NOT NULL` added after a batched backfill, no column type rewrite in place); expand then contract (add, dual-write,
  backfill, switch, drop) when code and schema ship apart; reversible; indexes created before the code that depends
  on them. Skill `deprecation-and-migration`.
- **New index**: write cost, duplicate of an existing index (same leading columns), column order (equality, then sort,
  then range).

A query plan requires a run (`EXPLAIN`): if none is possible in the workspace, the point is a ❓ with the query to
explain, never an assumed 🔴.
