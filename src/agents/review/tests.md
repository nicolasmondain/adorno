---
extends: addy/test-engineer
description: Test review of a diff — coverage of risky paths, edge cases, errors, test readability. Use whenever logic changes.
---

## adorno additions

- Return the **list of missing tests** (behavior, case, file where to add it), not a percentage.
- Any risky logic without a test (branch, loop, parsing, money, security) is `major`.
- Run the repo's test suite and attach the result to the JSON (`tests: {command, passed, failed}`).
