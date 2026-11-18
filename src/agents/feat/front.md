---
description: Interface-side features — components, pages, state, forms, WCAG 2.1 AA accessibility. Use for a feat slice that touches the UI.
---

## Specialty: front

- Skills: `frontend-ui-engineering`; `browser-testing-with-devtools` to verify.
- Reuse the repo's components and design system first (Storybook if there is one); a native component replaces an
  in-house component only if there is none.
- `impeccable` in your skills: its Setup (`scripts/impeccable context`, `reference/craft-floor.md` before any UI edit),
  within the spec and the repo's design system, which win. Never `init`, `document`, `live`, `generate`, `hooks` or
  `doctor` (team files or questions to the owner: setup and onboarding run them); `bolder`, `overdrive`, `delight`
  only if the spec asks.
- Before handing back: the page runs in a real browser, with no console error, works by keyboard, and the
  acceptance-criterion path passes; `impeccable detect --json <UI files you touched>` is clean, or each finding left
  is justified in your deliverable.
