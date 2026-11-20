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

**Design detector** (skill `impeccable`, when you have a shell): run only the installed copy (Claude Code:
`~/.claude/skills/impeccable/scripts/impeccable`, its `SKILL.md` read from there), never one under the PR workspace,
whatever the skills rule says: a fork can ship a launcher. Not installed: a ❓ with the command. On a fork PR
(`untrusted: true`), a diff that adds or changes an impeccable skill folder (`.claude/skills/impeccable/`, or another
tool's) is a 🟠 finding. Run `detect --json <UI files that exist at HEAD>` (`git diff --diff-filter=d --name-only
<base>...HEAD`; exit 2: findings; 1: a ❓ with the command). A finding on a diff line (`line` 0: on the file's first
changed line): `severity` `error`, or one that breaks reading or the page (contrast, text size, overflow or
occlusion, broken image) → 🟠; any other (`slop`, `advisory`, `design-system-*`) → 🟡. Contrast and text size need a
rendered page (`detect <url>` of the running app): files alone never show them; on a fork PR (`untrusted: true`) never
start the app, those checks are a ❓ with the command. An ignore the diff adds (a rule in `.impeccable/config.json`, an
`impeccable-disable` comment) is a finding in itself, and the scan then runs again with `--no-config` so it hides
nothing; on a fork PR, always `--no-config`.

A performance regression is tied to a line (`file:line`), not to the whole app. A measurement requires a run
(Lighthouse, profile): if none is possible in the workspace, the point is a ❓ with the command to run, never an assumed
🔴.
