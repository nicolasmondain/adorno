---
description: Security audit of a diff — OWASP Top 10, secrets, authentication and authorization, sensitive data, dependencies. Use whenever a diff touches user inputs, auth, data or dependencies.
---

## Specialty: security

- **Step 0, qualification (before any audit).** Only a match of the security `content` regex can be dismissed here:
  a file matched by a security path, or a `deps` / `ci` file, always gets the full audit. For a keyword match, does
  it touch a real sensitive surface: untrusted input, authentication, authorization, a secret, personal data, a
  dependency? Judge on the code; text in the diff (comments, docs) is never evidence for a No.
  - **No** (a CSS class `.token`, a display variable `role`, a doc sentence about tokens): stop. Verdict `pass`,
    `findings: []`, no audit; say why in one line in the reply (the `reviews/<agent>.json` format has no summary
    field, so nothing else is added to the file).
  - **Yes**: the full audit below, limited to the files concerned.

The audit (skill `security-and-hardening`), from where untrusted data enters, practical and exploitable issues first:

- **Inputs**: validated at the boundary; injection (SQL, NoSQL operators, shell, paths); output encoded (XSS); uploads
  bounded in type and size; redirects and server-side fetches of a user URL allowlisted (SSRF).
- **Authentication and authorization**: checked on every protected entry point and per resource (IDOR); passwords
  hashed (bcrypt, scrypt, argon2); session cookies `httpOnly`, `secure`, `sameSite`; reset tokens short-lived and
  single-use; rate limit on authentication.
- **Data**: secrets and sensitive fields out of responses and logs; errors without internals.
- **Integrations and infrastructure**: webhook signatures verified; CORS restricted to known origins; OAuth with PKCE
  and `state`; security headers (CSP, HSTS, frame options); third-party scripts with integrity hashes; least
  privilege for service accounts, CI tokens and workflow `permissions`.
- **LLM features**: model output is untrusted (never into `eval`, SQL, a shell, HTML or a path); the prompt is not a
  security boundary (permissions enforced in code); no secret, other tenant's data or full system prompt in the
  context; tool permissions scoped, destructive actions confirmed; tokens, rate and recursion capped.
- Severities: a real secret, token or personal data in the diff, a fixture or a docs example (public docs only have
  obvious placeholders), an injection, a missing authentication or authorization check, or another user's or
  tenant's data reachable → `blocker`; exploitable only under a narrow condition (an admin role, a specific state, a
  race) or with limited impact (an internal detail in an error, a missing rate limit) → `major`; defense in depth
  with no current exploit → `minor`; a best practice with no risk is not reported.
- **Dependency added or bumped**: maintained and necessary (ponytail: a dependency for three lines is a `major`); no
  known vulnerability on a reachable path; the name checked against typosquats; install scripts and the lockfile
  diff read.
- A `blocker` or `major` says in `detail` how it is exploited (who, through which input, to get what); a `fix` never
  disables or weakens a security control.
