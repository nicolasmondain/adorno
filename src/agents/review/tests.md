---
description: Test review of a diff — coverage of risky paths, edge cases, errors, test readability. Use whenever logic changes.
---

## Specialty: tests

- Read the code under test before its tests: its public behavior, its edge cases, its error paths.
- For each changed function or component, the scenarios: nominal, empty input (empty, null, undefined), bounds (min,
  max, zero, negative), errors (invalid input, network failure, timeout), concurrency where it applies.
- The right level: pure logic → unit, a boundary crossed → integration, a critical user journey → e2e; never an e2e
  test for what a unit test covers.
- A test that cannot fail (asserts nothing, mocks the code under test, a snapshot nobody reads) counts as missing;
  mocks belong at the system's boundaries (database, network), not between internal functions.
- Return the **list of missing tests** (behavior, case, file where to add it), not a percentage.
- Any risky logic without a test (branch, loop, parsing, money, security) is `major`.
- Run the repo's test suite and attach the result to the JSON (`tests: {command, passed, failed}`).
