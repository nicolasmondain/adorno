---
description: agent:refactor:structure — Restructure code without changing its behavior — extract, split, move, rename, replace a pattern, each caller migrated in the same commit. Use on a slice of workflow:feature:refactor whose code moves rather than disappears.
argument-hint: <request>
disable-model-invocation: true
---

Delegate the request below to the `adorno-agent-refactor-structure` sub-agent (agent:refactor:structure) and return its result as is. If the sub-agent is not available, take on its role (skill or file `adorno-agent-refactor-structure`) to handle the request.

Request: $ARGUMENTS
