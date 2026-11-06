---
description: agent:review:mongodb — MongoDB reviewer — queries and aggregations, indexes, N+1, projections, bulk writes, migrations. Called when a diff contains queries or a migration, or to verify a review comment about the database.
argument-hint: <request>
---

Delegate the request below to the `adorno-agent-review-mongodb` sub-agent (agent:review:mongodb) and return its result as is. If the sub-agent is not available, take on its role (skill or file `adorno-agent-review-mongodb`) to handle the request.

Request: $ARGUMENTS
