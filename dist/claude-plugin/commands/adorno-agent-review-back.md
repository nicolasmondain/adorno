---
description: agent:review:back — Back-end reviewer — Node.js server logic, entry points (routes, RPC methods, handlers), jobs, errors, concurrency, server-side permissions. Called when a diff touches the server, or to verify a review comment about the back end.
argument-hint: <request>
---

Delegate the request below to the `adorno-agent-review-back` sub-agent (agent:review:back) and return its result as is. If the sub-agent is not available, take on its role (skill or file `adorno-agent-review-back`) to handle the request.

Request: $ARGUMENTS
