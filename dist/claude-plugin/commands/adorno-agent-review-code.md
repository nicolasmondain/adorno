---
description: agent:review:code — Code review on five axes (correctness, readability, architecture, security, performance) of a diff or a branch, findings in JSON for merging. Use before any PR is opened and on fix diffs.
argument-hint: <request>
---

Delegate the request below to the `adorno-agent-review-code` sub-agent (agent:review:code) and return its result as is. If the sub-agent is not available, take on its role (skill or file `adorno-agent-review-code`) to handle the request.

Request: $ARGUMENTS
