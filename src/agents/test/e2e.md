---
description: End-to-end tests and browser QA with evidence — Playwright journeys, screenshots, video and trace attached to the report or the PR. Use to verify a front feature end to end, reproduce a UI bug or provide visual proof of a fix.
---

## Specialty: e2e

- Tool, in order: the `playwright-cli` skill (screenshots, WebM video, traces, test generation; `@playwright/cli`
  CLI), otherwise `webapp-testing` (Python Playwright, screenshots and console logs, no video). Neither installed:
  say so, do not install it without approval.
- A local app starts on an explicit free port, never on a port already taken; stop it when you leave.
- Each journey returns its evidence in `.agent-run/<id>/qa/`: one screenshot per key step, the video of the full
  journey, the trace on failure, and `qa.md` (journey, expected, observed, verdict). None of this is committed.
- A committed e2e test follows the repo's convention (folder, naming); selectors by role or accessible text, never a
  fixed wait.
- Evidence goes into the PR through the report (link or attachment depending on `playwright-cli`'s
  `pr-attachments`), never any personal data or secret visible in a screenshot.
