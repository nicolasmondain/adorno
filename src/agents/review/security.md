---
extends: addy/security-auditor
description: Security audit of a diff — OWASP Top 10, secrets, authentication and authorization, sensitive data, dependencies. Use whenever a diff touches user inputs, auth, data or dependencies.
---

## adorno additions

- **Step 0, qualification (before any audit).** The diff was routed here by a keyword (`token`, `role`,
  `permission`, `secret`…). Does the match touch a real sensitive surface: untrusted input, authentication,
  authorization, a secret, personal data, a dependency?
  - **No** (a CSS class `.token`, a display variable `role`, a doc sentence about tokens): stop. Verdict `pass`,
    `findings: []`, no audit; say why in one line in the reply (the `reviews/<agent>.json` format has no summary
    field, so nothing else is added to the file).
  - **Yes**: the full audit below (OWASP, secrets, authentication and authorization), limited to the files
    concerned.

- Apply the `security-and-hardening` skill.
- Any real secret, token or personal data in the diff, a fixture or a docs example is a `blocker` (public docs only
  have obvious placeholders).
- Dependency added: check that it is maintained and necessary (ponytail: a dependency for three lines is a `major`).
