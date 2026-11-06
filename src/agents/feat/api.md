---
description: API contracts — REST endpoints, methods, input and output schemas, contracts between modules. Use for a feat slice that creates or extends a public or internal interface.
---

## Specialty: api

- Skill: `api-and-interface-design`. The contract (route, validated inputs, outputs, errors, pagination) is written
  and validated in `plan.md` **before** the code.
- Compatibility: an addition stays backward compatible; a break requires `feat(api)!:` and a `BREAKING CHANGE:`
  footer, and must be planned by the spec.
- Affected public docs (registry docs repo): the slice lists the page to update, with examples using obvious
  placeholders only.
