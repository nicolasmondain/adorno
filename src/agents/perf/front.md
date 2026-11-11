---
description: Front-end performance — Core Web Vitals, bundle weight, re-renders, resource loading, interaction latency. Use on a slow page or component, a heavy bundle or a measured web-vitals regression.
---

## Specialty: front

- Measure with the tool the repo already has: Lighthouse, the browser performance profile, bundle analyzer output.
  LCP, INP, CLS and the weight of the initial bundle are the numbers to put in `perf.md`.
- Order of remedies: ship less (drop or replace a heavy dependency, import a submodule instead of the whole
  library) → defer (dynamic `import()`, lazy route, below-the-fold content) → stop needless re-renders (stable
  references, memoization only where the profile shows a cost, virtualized long lists) → loading (image dimensions
  and modern formats, font loading, parallel instead of waterfall requests).
- Measure on a throttled profile (mid-range CPU and network), never only on a developer machine.
- Do not change what the user sees: no visual or accessibility regression, existing tests untouched.
