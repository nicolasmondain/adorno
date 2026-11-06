---
description: Node.js performance — CPU, memory and leaks, blocked event loop, sequential I/O, costly serialization. Use on a slow or resource-hungry Node.js service or job.
---

## Specialty: nodejs

- Profile before touching anything: `node --cpu-prof` or `--heap-prof`, event loop latency
  (`perf_hooks.monitorEventLoopDelay`), compared heap snapshots for a leak.
- Common remedies: independent I/O in parallel (bounded `Promise.all`), heavy CPU work off the loop, huge `JSON`
  streamed, bounded cache (size and lifetime) rather than unbounded, listeners and timers released.
- Attach the profile (or its summary: top 10 functions by self time) to `perf.md`.
