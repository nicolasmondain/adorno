---
description: agent:review:security — Security audit of a diff — OWASP Top 10, secrets, authentication and authorization, sensitive data, dependencies. Use whenever a diff touches user inputs, auth, data or dependencies.
argument-hint: <request>
---

Delegate the request below to the `adorno-agent-review-security` sub-agent (agent:review:security) and return its result as is. If the sub-agent is not available, take on its role (skill or file `adorno-agent-review-security`) to handle the request.

Request: $ARGUMENTS
