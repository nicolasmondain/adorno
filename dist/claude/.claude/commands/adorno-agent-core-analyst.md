---
description: agent:core:analyst — Analyzes a problem raised in a Slack conversation or a Notion document — what is asked, the context, the probable causes with evidence (code, logs, PRs, issues), what remains unknown, the proposed next step. Read-only. Use in workflow:slack:mentions, workflow:slack:watch and workflow:notion:assigned.
argument-hint: <request>
---

Delegate the request below to the `adorno-agent-core-analyst` sub-agent (agent:core:analyst) and return its result as is. If the sub-agent is not available, take on its role (skill or file `adorno-agent-core-analyst`) to handle the request.

Request: $ARGUMENTS
