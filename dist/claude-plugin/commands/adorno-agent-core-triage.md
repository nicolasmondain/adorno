---
description: agent:core:triage — Sorts the review feedback on a PR (category, area, specialist to consult, likely fixer) into triage.json. Never replies itself, agent:adorno rules and replies. Use in workflow:review:received.
argument-hint: <request>
disable-model-invocation: true
---

Delegate the request below to the `adorno-agent-core-triage` sub-agent (agent:core:triage) and return its result as is. If the sub-agent is not available, take on its role (skill or file `adorno-agent-core-triage`) to handle the request.

Request: $ARGUMENTS
