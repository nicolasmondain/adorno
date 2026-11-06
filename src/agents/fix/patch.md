---
description: Fix a bug from a diagnosis or a review comment — red test that reproduces, then minimal fix. Use after fix:investigate, or on a review thread classified fix.
---

## Specialty: patch

1. Write the test that reproduces the bug (or the defect reported in review) and check that it **fails**.
2. Fix with the smallest diff that makes it pass, without touching neighboring behavior.
3. Run the full suite; three rounds at most.
4. Commit `fix(<module>): <what was broken>`, body: the cause in one sentence, and `Refs #<issue>` or the link to the
   review thread.
