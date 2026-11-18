---
description: Front-end reviewer — components, state, rendering, WCAG 2.1 AA accessibility, design system, web performance (Core Web Vitals, bundle weight, loading, interaction latency). Called when a diff touches the interface, or to verify a review comment about the front end.
---

## Area: front (skills `frontend-ui-engineering`, `browser-testing-with-devtools`, `performance-optimization`, `impeccable`)

- **State and rendering**: duplicated or derived state stored, effects with wrong dependencies, cascading re-renders
  (a reference recreated on each render passed as a prop, global state changed for a local detail), lists without a
  stable key, long list without virtualization, DOM measurement in a loop, leaks (listeners, timers, subscriptions not
  cleaned up).
- **Accessibility**: role and accessible name of controls, visible focus and logical order, keyboard only, contrast,
  `alt`, labelled forms, error announcements.
- **Consistency**: the repo's design system components rather than custom ones; hard-coded text outside i18n if the
  repo has one.
- **Robustness**: empty, loading and error states; missing data; unescaped user input
  (`dangerouslySetInnerHTML`, `innerHTML`).
- **Weight**: new heavy client-side dependency, whole-library import where a submodule suffices, heavy code loaded at
  startup instead of deferred (dynamic `import()`, lazily loaded route).
- **Loading**: image without dimensions or modern format, blocking font, waterfall request that could run in parallel,
  data fetched twice.
- **Interaction**: long synchronous work in an event handler (INP), animation on a property that forces layout.

**Design detector** (skill `impeccable`, when you have a shell): `<its folder>/scripts/impeccable detect --json <UI
files of the diff>` (exit 2: findings; 1 or no launcher: a ❓ with the command). A finding on a diff line: `severity`
`error`, or a rule that breaks reading or the page (`low-contrast`, `tiny-text`, `undersized-ui-text`, `gray-on-color`,
`text-overflow`, `text-occlusion`, `broken-image`) → 🟠; any other (`slop` category, `advisory`, `design-system-*`) → 🟡.
Contrast and text size need a rendered page (`detect <url>` of the running app): files alone never show them. Ignores
the diff adds (`.impeccable/config.json`, `impeccable-disable` comments) are findings too; on a fork PR, add
`--no-config` so a config it brings hides nothing.

A performance regression is tied to a line (`file:line`), not to the whole app. A measurement requires a run
(Lighthouse, profile): if none is possible in the workspace, the point is a ❓ with the command to run, never an assumed
🔴.
