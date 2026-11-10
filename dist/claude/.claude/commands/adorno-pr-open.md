---
description: Opens the PR of a ready branch, without asking — title and description in English following your template, in your voice, reviewers from the registry. Ready for review when the review loop of workflow:pr:ship left nothing 🔴 or 🟠, draft otherwise. Default pr_skill of workflow:pr:ship.
argument-hint: <owner/repo> <branch> [.agent-run folder]
---

Input: $ARGUMENTS

**Run** — reuse the run of `workflow:pr:ship`. Called alone, not by it: run `workflow:pr:ship $ARGUMENTS` instead,
which commits, reviews and fixes the branch, then comes back here.

No checkpoint: the PR opens without waiting for a "yes" (running the workflow is the request).

1. **Local checks**, in the clone where the branch lives: name matches `branch_pattern`, up to date with the base
   (`git fetch` then `git diff origin/<base>...HEAD`: the real scope), every commit in Conventional Commits format,
   tests, lint and typecheck green. A failure: stop and report.
2. **The verdict** of the review loop (`workflow:pr:ship` step 4, in the run's `reviews/`): clean → the PR goes out
   ready for review; a 🔴 or 🟠 still open after the cap → as draft, those points first in the description.
3. `agent:adorno` writes in English, in your voice (skill `adorno-voice`):
   - the title in Conventional Commit format for the main change;
   - the description following `process.md` § Pull requests: What / How / mermaid / Verification, `How to test` opened
     by the commands actually run and their result, link to the issue (`Fixes #n`), what the review loop fixed, the
     🟡 and ❓ left (`Impact / Risks`). No real data.
4. `adorno-github/scripts/git-push owner/repo <branch>` (never a direct `git push`), then `pr-open owner/repo <branch>
   "<title>" <file>` (`--draft` only when the verdict is not clean): registry reviewers without the author.
5. With an `.agent-run` folder: `adorno-notion-sync pr_opened <folder> owner/repo --pr-url <PR URL>` (the Notion page
   used as the spec gets the repo's `notion_spec.pr_opened` properties; a Notion failure is reported, the PR stays).
6. Return the PR URL, ready or draft, and suggest `workflow:pr:watch owner/repo#N`.
