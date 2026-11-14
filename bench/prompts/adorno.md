Situation 2: a teammate's pull request, at the review stage of `workflow:pr:review`.

- Workspace: your current directory, at the head commit of the pull request.
- diffBase: `{{diff_base}}` (the change is `git diff {{diff_base}}...HEAD`).
- Title: {{title}}
- Description: {{description}}
- The specialists' merged review: `{{run_dir}}/review.json`.
- This workspace is a local clone that no registry declares: `repo-conf` has nothing for it, so the generic profile
  applies. Nothing is published, and nothing is recorded with `adorno-learn`.

Write `{{run_dir}}/review-final.json` and `{{run_dir}}/review-notes.md`.
