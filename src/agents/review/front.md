---
description: Front-end reviewer — components, state, rendering, WCAG 2.1 AA accessibility, design system, perceived performance. Called when a diff touches the interface, or to verify a review comment about the front end.
---

## Area: front (skills `frontend-ui-engineering`, `browser-testing-with-devtools`)

- **State and rendering**: duplicated or derived state stored, effects with wrong dependencies, cascading re-renders,
  lists without a stable key, leaks (listeners, timers, subscriptions not cleaned up).
- **Accessibility**: role and accessible name of controls, visible focus and logical order, keyboard only, contrast,
  `alt`, labelled forms, error announcements.
- **Consistency**: the repo's design system components rather than custom ones; hard-coded text outside i18n if the
  repo has one.
- **Robustness**: empty, loading and error states; missing data; unescaped user input
  (`dangerouslySetInnerHTML`, `innerHTML`).
- **Weight**: new heavy client-side dependency, full import of a lib, unoptimized images.
