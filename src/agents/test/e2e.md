---
description: End-to-end tests and browser QA with evidence — Playwright journeys, screenshots, video and trace attached to the report or the PR, terminal recordings for a path with no interface. Use to verify a front feature end to end, reproduce a UI bug, or record the before/after or final videos that justify a fix, a refactor or a feature.
---

## Specialty: e2e

- Tool, in order: the `playwright-cli` skill (screenshots, WebM video, traces, test generation; `@playwright/cli`
  CLI), otherwise `webapp-testing` (Python Playwright, screenshots and console logs, no video). Neither installed:
  say so, do not install it without approval.
- Browser drivers (`playwright-cli`, a repo's `cdp.mjs`…): one literal call per step (`node <abs path> <port> <cmd> …`),
  the port and target ids copied from the previous output, never stored in a shell variable used as program.
- A local app starts on an explicit free port, never on a port already taken; stop it when you leave.
- Each journey returns its evidence in `.agent-run/<id>/qa/`: one screenshot per key step, the video of the full
  journey, the trace on failure, and `qa.md` (journey, expected, observed, verdict). None of this is committed.
- A committed e2e test follows the repo's convention (folder, naming); selectors by role or accessible text, never a
  fixed wait.
- Journeys run on local or seeded data, never a real account: no personal data or secret may be visible. The
  evidence reaches the PR through `workflow:pr:ship` (step 5: checked, then `pr-open` / `pr-edit --attach`), never
  `gh … --attach` by hand as `playwright-cli`'s `pr-attachments` shows it: the guard refuses it.

### Journeys

- A journey recorded for the visual justification (`workflow:pr:ship` step 5) is written once in `qa/journeys.md`
  before its first recording: `## <journey>` (kebab-case id), the user path step by step, the seeded data, what is
  expected. Never changed after a `before-` recording: the `after-` replays it step for step, with the same data,
  viewport and speed, so that the two videos compare.
- One file per journey and moment: `qa/before-<journey>.<ext>`, `qa/after-<journey>.<ext>`,
  `qa/feature-<journey>.<ext>`, with a line per recording in `qa.md` (commit SHA, what it shows, verdict). A bug's
  `before-` shows the error on screen (the message, the wrong value, the stack in the console pane): a recording
  where it does not show is not kept. An `after-` where the error still shows (a fix), or whose result differs from
  its `before-` (a refactor), is not kept either: the recording is missing (`workflow:pr:ship` step 5).

### No interface

- A path with no screen (an API route, a CLI, a job) is recorded in a terminal: the call a user or a client makes and
  its answer, a short pause after each. Tool, in order: `vhs` (the tape in `qa/<journey>.tape`, output `.webm`), then
  `asciinema rec` + `agg` (`.gif`). Neither installed: say so, do not install it without approval; the recording is
  missing.
- The terminal shows the command and its output only: no environment dump, credentials in variables set off camera,
  an `Authorization` or cookie header never printed.
