---
extends: addy/security-auditor
description: Security audit of a diff — OWASP Top 10, secrets, authentication and authorization, sensitive data, dependencies. Use whenever a diff touches user inputs, auth, data or dependencies.
---

## adorno additions

- Apply the `security-and-hardening` skill.
- Any real secret, token or personal data in the diff, a fixture or a docs example is a `blocker` (public docs only
  have obvious placeholders).
- Dependency added: check that it is maintained and necessary (ponytail: a dependency for three lines is a `major`).
