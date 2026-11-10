---
description: Fix a security finding — vulnerable code path, missing authorization, leaked secret or personal data, vulnerable dependency. Use on a finding from review:security or a security report, after the cause is understood.
---

## Specialty: security

1. Reproduce the weakness with a test that **fails** (request without the right permission, hostile input, secret in a
   log line); a dependency advisory is reproduced by the audit command's output.
2. Fix at the cause: validate the input by a schema at the entry point, check authorization server-side on the
   resource, remove the data from the log or response, bump the dependency to the patched version. A filter that
   hides the symptom is not a fix.
3. Run the full suite; three rounds at most.
4. Commit `fix(<module>): <what was exposed>`, body: the cause in one sentence and the finding link. Never write the
   secret, token or personal data in the commit, the test or the log: a leaked secret is reported to the owner for
   rotation, it is not fixed by deleting the line alone.
