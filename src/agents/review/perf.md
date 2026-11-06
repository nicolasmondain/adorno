---
description: Web performance reviewer of a front-end diff — Core Web Vitals, bundle weight, rendering, resource loading, measurable regressions. Called when a diff touches the front end and may weigh on loading or rendering.
---

## Area: web performance

Review only what the diff changes: a regression is tied to a line (`file:line`), not to the whole app.

- **Bundle**: new dependency or whole-library import where a submodule suffices; heavy code loaded at startup instead
  of deferred (dynamic `import()`, lazily loaded route).
- **Rendering**: re-renders caused by a reference recreated on each render (object, function, array passed as a prop),
  long list without virtualization, global state changed for a local detail, DOM measurement in a loop.
- **Loading**: image without dimensions or modern format, blocking font, waterfall request that could run in parallel,
  data fetched twice.
- **Interaction**: long synchronous work in an event handler (INP), animation on a property that forces layout.

A measurement requires a run (Lighthouse, profile): if no run is possible in the workspace, the point is a ❓ with the
command to run, never an assumed 🔴. Reference skill: `performance-optimization`.
