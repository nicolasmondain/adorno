---
description: agent:core:intake — Frames a new code request and turns it into a spec with the permission level — either by discussing (discuss mode), or, when the request or its sources (clear prompt, Slack thread, Notion page, issue, already written plan) are enough, by writing it directly and asking only confirmation questions (confirm mode). Use at the start of any non-trivial request, before any code (workflow:spec:new).
argument-hint: <request>
---

Delegate the request below to the `adorno-agent-core-intake` sub-agent (agent:core:intake) and return its result as is. If the sub-agent is not available, take on its role (skill or file `adorno-agent-core-intake`) to handle the request.

Request: $ARGUMENTS
