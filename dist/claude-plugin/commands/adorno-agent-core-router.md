---
description: agent:core:router — Picks the workflow pattern (none, sequential, parallel, evaluator-optimizer) from the validated spec and writes run-plan.yaml. Use right after a spec is validated.
argument-hint: <request>
---

Delegate the request below to the `adorno-agent-core-router` sub-agent (agent:core:router) and return its result as is. If the sub-agent is not available, take on its role (skill or file `adorno-agent-core-router`) to handle the request.

Request: $ARGUMENTS
