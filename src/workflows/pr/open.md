---
description: Opens the PR of a ready branch, without asking — title and description in English following your template, in your voice, reviewers from the registry. Ready for review when the review loop of workflow:pr:ship left nothing 🔴 or 🟠, draft otherwise. Default pr_skill of workflow:pr:ship.
args: "<owner/repo> <branch> [.agent-run folder]"
uses:
  skills: [adorno-github, adorno-profile, adorno-voice, adorno-notion-sync]
  agents: [agent:adorno]
  workflows: [workflow:pr:ship]
model: balanced
---

Input: {{args}}

**Run** — reuse the run of `workflow:pr:ship`. Called alone, not by it: run `workflow:pr:ship {{args}}` instead,
which commits, reviews and fixes the branch, then comes back here.

No checkpoint: the PR opens without waiting for a "yes" (running the workflow is the request).

1. **Local checks**, in the clone where the branch lives: name matches `branch_pattern`, up to date with the base
   (`git fetch` then `git diff origin/<base>...HEAD > <run>/branch.diff`: the real scope, kept in the run folder,
   never committed), every commit in Conventional Commits format,
   tests, lint and typecheck green. A failure: stop and report.
2. **The verdict** of the review loop (`workflow:pr:ship` step 4, in the run's `reviews/`) and **the proof** (step 5,
   the run's `qa/`): clean and the proof complete → the PR goes out ready for review; a 🔴 or 🟠 still open after
   the cap, or a proof missing → as draft, those points first in the description.
3. `agent:adorno` writes in English, in your voice (skill `adorno-voice`):
   - the title in Conventional Commit format for the main change;
   - the description following `process.md` § Pull requests: What / How / mermaid / Verification, `How to test` opened
     by the commands actually run and their result, link to the issue (`Fixes #n`, `Fixes owner/repo#n` from another
     repo), what the review loop fixed, the 🟡 and ❓ left and the ponytail notes of the run's `status.md` (lite:
     the smaller option, ultra: the pushback) (`Impact / Risks`). No real data;
   - in `Impact / Risks`: what the deploy needs (a new environment variable or setting, a migration and when to run
     it) and why a plain revert would not be safe (data the change writes, a migration that does not roll back), only
     when present: a safe revert goes unsaid; the signals to watch once deployed (what `workflow:pr:impact` will
     measure) whenever the change touches a runtime path (route, job, query, UI). Otherwise nothing written;
   - a `## Shortcuts` section, after `Impact / Risks`: the shortcuts this branch leaves in the code, from
     `adorno-github/scripts/pr-shortcuts <run>/branch.diff` (only the lines the diff adds), one line per marker,
     `` - `file:line` — <the limit> · upgrade: <the trigger> ``, taken from the comment; a marker that names no
     trigger is tagged `no-trigger` (skill `ponytail-debt`). The match is textual: a hit that is not a comment in the
     code (inside a string, a test fixture, prose) is not a marker and is dropped. No marker: no section;
   - a `## Behavior preserved` section, before `## Sources`, only when the run has `qa/refactor-gate.json`
     (`workflow:feature:refactor`): the characterization tests added (the `test:` commits), the gate's proof that no
     existing test changed or was lost (its `ok`, `report` and `tests`), and the before/after table of
     `measures.md`;
   - a `## Sources` section, before `## Proof`: one line per Notion page, doc (`url`) and Slack thread of the run's
     `refs.json`, in the request's order, its title from `source.md` § Sources
     (`- [Notion · Export CSV](https://www.notion.so/…)`), the URL copied verbatim from `refs.json`. A doc link is
     never published when it carries a credential (a token, key, signature, password or session in its query, or
     `user:pass@`), when the link itself grants access (a share link), or when its host is localhost, a private IP or
     an internal-only domain. Its line keeps the title, `(link withheld: <reason>)`, and the URL goes to `--withhold`.
     Notion pages and Slack threads are always linked. No `refs.json` in the run: no `## Sources`;
   - a `## Proof` section: each command of `qa/tests.log` with its result line (passed / failed counts) and, in a
     `<details>` block, its first 30 failing lines (`… N more in qa/tests.log` beyond), checked for secrets like the
     media — never the whole log (a body stops at 65,536 characters); each
     screenshot or video of `qa/` cleared by `workflow:pr:ship` step 5, referenced inline
     (`![what it shows](./qa/x.png)`; the body file written in the run folder, so the path resolves; a reference gh
     cannot match is still uploaded, appended at the end).
4. `adorno-github/scripts/git-push owner/repo <branch>` (never a direct `git push`), then `pr-open owner/repo <branch>
   "<title>" <file> [--draft] [--refs <run>/refs.json [--withhold <url>]…] --attach <run>/qa/<media>…` (`--draft`
   only when the verdict is not clean or a proof is missing; `--refs` whenever the run has a `refs.json`: a missing
   source (or one not written as `[title](url)`) is refused with exit 2, add it to the body, or withhold it under the
   step 3 rule, and call again; one
   `--attach` per screenshot or video, 50 at most): registry reviewers without the author.
5. With an `.agent-run` folder: `adorno-notion-sync pr_opened <folder> owner/repo --pr-url <PR URL>` (the Notion page
   used as the spec gets the repo's `notion_spec.pr_opened` properties; a Notion failure is reported, the PR stays).
6. Return the PR URL, ready or draft, and suggest `workflow:pr:watch owner/repo#N`.
