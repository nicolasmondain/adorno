---
extends: addy/security-auditor
description: Audit sécurité d'un diff — OWASP Top 10, secrets, authentification et autorisations, données sensibles, dépendances. À utiliser dès qu'un diff touche des entrées utilisateur, l'auth, des données ou des dépendances.
---

## Ajouts adorno

- Applique le skill `security-and-hardening`.
- Tout secret, token ou donnée personnelle réelle dans le diff, un fixture ou un exemple de doc est `blocker`
  (une doc publique n'a que des placeholders évidents).
- Dépendance ajoutée : vérifie qu'elle est maintenue et nécessaire (ponytail : une dépendance pour trois lignes
  est un `major`).
