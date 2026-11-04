---
description: État de toutes tes PRs ouvertes (ou d'un repo) — review, CI, threads non résolus, et ce qui bloque chacune. Lecture seule.
argument-hint: '[owner/repo]'
---

Entrée : $ARGUMENTS

1. `export ADORNO_LEVEL=L0`, puis `github-ops/scripts/pr-status $ARGUMENTS`.
2. Rends un tableau trié par urgence — `ci-red`, `changes-requested`, `unresolved-threads`, `conflicts`,
   `waiting-review`, `ci-running`, `draft`, `ready` — avec : PR (lien), titre, blocage, qui attend qui
   (`waitingOn`), dernière mise à jour.
3. Sous le tableau, une ligne par action utile, sous forme de commande prête à lancer
   (`workflow:review:received owner/repo#N`, `workflow:ci:red owner/repo#N`).
4. Les PRs de repos non enregistrés sont listées à part, sans action proposée.
