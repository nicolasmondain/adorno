---
description: agent:review:ponytail — Ponytail review of a diff — excess code, avoidable dependencies, missing tests on risky logic, what was skipped. Use alongside review:code on every diff; also audits a whole repo or a scope of it, read-only (workflow:repo:audit).
argument-hint: <request>
disable-model-invocation: true
---

Delegate the request below to the `adorno-agent-review-ponytail` sub-agent (agent:review:ponytail) and return its result as is. If the sub-agent is not available, take on its role (skill or file `adorno-agent-review-ponytail`) to handle the request.

Request: $ARGUMENTS
