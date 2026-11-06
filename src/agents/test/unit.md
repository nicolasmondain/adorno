---
description: Write unit tests for existing logic or requested in review — nominal cases, limits, errors. Use on a review thread classified test or a gap listed by review:tests.
---

## Specialty: unit

- Use the framework and helpers already in the repo; no new test tooling.
- Cover the risky branches first: empty or null inputs, bounds, errors, money and dates.
- Check that each new test would fail if the behavior broke (invert a condition, the test must go red), then restore
  the code.
