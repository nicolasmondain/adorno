---
description: agent:review:front — Front-end reviewer — components, state, rendering, WCAG 2.1 AA accessibility, design system, web performance (Core Web Vitals, bundle weight, loading, interaction latency). Called when a diff touches the interface, or to verify a review comment about the front end.
argument-hint: <request>
disable-model-invocation: true
---

Delegate the request below to the `adorno-agent-review-front` sub-agent (agent:review:front) and return its result as is. If the sub-agent is not available, take on its role (skill or file `adorno-agent-review-front`) to handle the request.

Request: $ARGUMENTS
