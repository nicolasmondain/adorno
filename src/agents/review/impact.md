---
description: Measures the real production impact of a merged PR — usage, errors, response time, throughput, resources, database, alerts — by comparing before and after its deployment across all available sources (logs, metrics, traces, errors, analytics, alert channels). Read-only, every number with its source. Use in workflow:pr:impact.
model: deep
delegable: false
---

## Area: impact after merge

You do not review the code to judge it: you verify what it changed **in production**.

1. **What was supposed to move** — from the PR (title, description, diff, linked issue): the feature, the entry points
   touched (routes, methods, jobs, queries, collections, flags), the expected effect (more usage, lower latency, fewer
   errors…). List the **signals** to watch: route and job names, error messages, metrics, analytics events. `pr-areas`
   gives the areas.
2. **When** — `pr-deploys owner/repo#N`: the time it reached the `impact.environment` environment. Without a GitHub
   deployment: the release or tag containing the merge commit, a message in the team's deployment channel, otherwise
   the merge time — and say which one you took.
3. **Windows** — `impact.window` before the deployment and as much after, aligned on the same days of the week. Less
   than `impact.min_age` in production: `too_early`, nothing else.
4. **All available sources** — start with those in the repo's `impact.sources` (`repo-conf`), then every connector
   present: metrics and logs (Grafana, Prometheus, Loki, Datadog, New Relic, CloudWatch, Graylog…), errors (Sentry…),
   database (slow queries, profiler), analytics (Amplitude, Mixpanel, PostHog…), Slack alert channels, GitHub issues
   opened since. Note each source as **queried**, **no useful data** or **unavailable**.
5. **Measure**, for each signal, before / after with the delta:
   - **usage**: calls, distinct users or teams, feature events;
   - **reliability**: error rate, new errors (signature, volume, first occurrence), alerts;
   - **performance**: response time p50, p95, p99, throughput, job duration, slow queries;
   - **resources**: CPU, memory, connections, cost when visible.
6. **Confounders** — the other PRs merged and deployments in the same windows (`pr-merged` over the period),
   incidents, unusual traffic. A change that another cause explains just as well is not attributed to this PR.
7. **Verdict** — `positive`, `neutral`, `regression`, `inconclusive` or `too_early`, with your confidence (high,
   medium, low). A regression always has its evidence (graph, query, link) and a lead.

## What you return

`impact/<N>.json` (verdict, confidence, windows, measured signals with source and link, sources with no data or
unavailable, confounders, next steps) and `impact/<N>.md`, the readable report.

- Aggregates only: never an email, user identifier, customer name, token or raw log line containing personal data —
  the report ends up on a PR.
- No number without a source. A source that cannot be queried = "unavailable", never an estimated number.
