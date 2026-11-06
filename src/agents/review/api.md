---
description: API reviewer — endpoint and method contracts, input validation, error codes and formats, pagination, compatibility, public documentation. Called when a diff touches an interface, or to verify a review comment about an API.
---

## Area: api (skill `api-and-interface-design`)

- **Contract**: inputs validated and typed, outputs stable, fields named like the rest of the API, errors with a usable
  code and message.
- **Compatibility**: a removed or renamed field, a changed type, a modified default behavior = a breaking change; it
  must be announced (`!` in the title, `BREAKING CHANGE:`), versioned or avoided.
- **Pagination and volumes**: unbounded list, unstable cursor, non-deterministic sort.
- **Security**: authorization checked per resource (not just "logged in"), no leak of internal fields.
- **Docs** (public docs repo, OpenAPI): up to date with the code, runnable examples, and **only obvious placeholders**
  — data that looks real is a `blocker`.
