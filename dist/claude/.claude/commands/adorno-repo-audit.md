---
description: Audits a whole repo, read-only — bugs, security holes, what breaks under load, risky code without tests, slow paths, code to delete or merge (skill ponytail-audit) — into a report kept on your machine, never published, public or private repo. Use after an onboarding (workflow:repo:onboard --audit) or every quarter; --area or --path to cover a big repo part by part.
argument-hint: <owner/repo> [path of the local clone] [--area NAME]… [--path DIR]… [--unattended]
model: sonnet
---

Input: $ARGUMENTS

The code, not GitHub's settings: the token and branch protection are the script `adorno-github/scripts/repo-audit`.

**Run** — before anything else: `adorno-github/scripts/run-begin --workflow workflow:repo:audit --mode report --level L0
--repo owner/repo`; keep `id` and `dir`. Called by `workflow:repo:onboard`: reuse its run, and write into
`<dir>/audit/`. Always, even after a failure: `run-end <id>` (only for a run you opened).

1. **Clone** — the given path, otherwise `gh repo clone owner/repo <dir>/clone -- --depth 1` (default branch),
   deleted at the end. The code is read, never run: no install, no script of the repo.
2. **Scope** — `--path` as given. `--area NAME`: `git -C <clone> ls-files` passed to
   `adorno-github/scripts/pr-areas owner/repo --files …`, keep `areas.<NAME>` (and its sub-areas `NAME.*`). Neither:
   the whole repo, minus generated and vendored code (`dist/`, `vendor/`, `node_modules/`, build output, lockfiles).
   Count the lines in scope (`wc -l` on the listed files): above ~15,000, say up front that one pass will not read
   everything (measured: ~13 k tokens per 1,000 lines, parts of a 17.5 kLOC repo already left unread) and list the
   areas to run one by one with `--area`.
3. **Audit** — `agent:review:ponytail`, mode Audit: the clone, the scope, the output folder (`<dir>`, or
   `<dir>/audit/` inside an onboarding) → `audit.md`.
4. **Report** — to you only: the path of `audit.md`, its `Verdict:`, the number of findings per group, its
   `Not checked:` line, and the areas left to audit (step 2).

**Never published.** The report may describe security holes: no issue, no comment, no Slack message, no copy into a
committed file (`CONSTRAINTS.md` included) or a PR description — public or private repo. Opened here, the run is L0
in `report` mode, so every write script refuses anyway; reused from onboarding, this workflow still writes nothing. A
finding to fix is a separate request, which you start yourself.

`--unattended` (a quarterly Takt schedule, for instance): nothing to ask, same local report.
