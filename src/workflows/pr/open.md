---
description: Opens the PR of a ready branch — review gate first (area specialists + your agent), then title and description in English following your template, reviewers from the registry. No PR while a 🔴 or a 🟠 is unresolved or unaccepted.
args: "<owner/repo> <branch> [.agent-run folder]"
uses:
  skills: [adorno-github, adorno-commit, adorno-profile, adorno-voice]
  agents: [agent:core:triage, agent:adorno, agent:review:code, agent:review:ponytail, agent:review:front, agent:review:back, agent:review:mongodb, agent:review:api, agent:review:security, agent:review:tests]
---

Input: {{args}}

**Run** — before anything else: `adorno-github/scripts/run-begin --workflow workflow:pr:open --mode auto --level L3 --repo owner/repo`; keep `id` and `dir` (the run folder). Called by another workflow that already opened its own: reuse it. Always, even after a failure: `run-end <id>`. With no open run, the scripts refuse any write.

1. **Local checks**, in the clone where the branch lives: name matches `branch_pattern`, up to date with the base
   (`git fetch` then `git diff origin/<base>...HEAD`: the real scope), every commit in Conventional Commits format,
   tests, lint and typecheck green. A failure: stop and report.
2. **Review gate** (situation 1 of `agent:adorno`): `pr-areas owner/repo` on this diff → reviewers; they
   review in parallel, read-only; `agent:adorno` rechecks and delivers its verdict. **No PR while a 🔴 or a 🟠 is unresolved or explicitly accepted by
   the user**; remaining 🟡 and ❓ go in the description (`Impact / Risks`, Verification).
3. `agent:adorno` writes in English, in your voice (skill `adorno-voice`), with the repo's PR skill if `repo-conf` gives one (`pr_skill`):
   - the title in Conventional Commit format for the main change;
   - the description following `process.md` § Pull requests: What / How / mermaid / Verification, `How to test` opened
     by the commands actually run and their result, link to the issue (`Fixes #n`). No real data.
4. **Checkpoint 2** if `gates` contains `open_pr`: show the title, description and gate verdict, wait for the
   "yes".
5. `adorno-github/scripts/git-push owner/repo <branch>` (never a direct `git push`), then `pr-open owner/repo <branch> "<title>" <file> --draft`: draft until
   CI is green (`process.md`), registry reviewers without the author.
6. Return the PR URL and suggest `workflow:pr:watch owner/repo#N`.
