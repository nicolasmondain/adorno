---
description: Scope a code request with the intake agent until you validate — by discussing (discuss), or from an already clear prompt, a Slack thread, a Notion page, an issue or a written plan, asking only the confirmation questions (confirm). First step of any non-trivial feature or fix.
args: "<the request, and/or Slack, Notion, GitHub links, a plan file> [owner/repo] [--mode discuss|confirm]"
uses:
  skills: [adorno-inputs, adorno-github]
  agents: [agent:core:intake]
---

Request: {{args}}

Three ways to pass a request, which can be mixed:

| You give | Example | Default mode |
| --- | --- | --- |
| an idea to build | `campaign CSV export? on acme/app` | `discuss`: the agent challenges, one question at a time |
| an already clear prompt | criteria, expected behavior, target files | `confirm`: spec written right away, then your confirmations |
| links that detail the implementation | a Slack thread, a Notion page, `acme/app#42`, `docs/plan.md` | `confirm` |

`--mode` forces one or the other. In `confirm`, answer "ok" to accept all the default answers, or correct the ones
that are off; "let's discuss" switches back to `discuss`.

1. **Repo and folder** — the target repo: given, read from the sources (issue, PR), or the current clone. It must be
   declared (`repo-conf` answers); otherwise, first offer `workflow:repo:onboard`. Create the run folder
   `.agent-run/<date>-<slug>/` in the repo (and add `.agent-run/` to `.git/info/exclude`).
2. **Sources** — `adorno-inputs/scripts/input-refs "{{args}}" > <run folder>/refs.json`. Links or a file: read each with its connector and
   write `source.md` (skill `adorno-inputs`). A connector is missing or a page is unreadable: say which, and ask to
   connect it or paste the content; never guess what a link says.
3. **Mode** — `--mode` if given. Otherwise `confirm` if `source.md` exists or if the request already says what to do
   and how to verify it (expected behavior, scope, at least one testable criterion); `discuss` otherwise. Announce
   the chosen mode in one line, with how to change it.
4. **Scope** — delegate to `agent:core:intake` with the request, `source.md` and the mode: in `discuss`, the
   conversation; in `confirm`, the spec right away then its numbered confirmations. It writes `spec.md` (with its
   Sources and, if there is one, the Provided plan).
5. **Checkpoint 1** — present the spec summary and wait for an explicit "yes", or corrections (the agent updates the
   spec and asks again). Nothing else starts before.
6. Return the path of the run folder and the next command: `workflow:feature:build <folder>`, or
   `workflow:issue:fix <folder>` for a fix.
