---
description: Traite une CI rouge sur une PR — diagnostic des logs, une seule relance si flaky, sinon correction par l'agent désigné et push. À utiliser dès qu'un check échoue.
argument-hint: <owner/repo#N>
---

Entrée : $ARGUMENTS

1. `export ADORNO_LEVEL=L2` (un `max_level` plus bas du repo l'emporte).
2. `agent:ci:debug` lit `ci-failed $ARGUMENTS` et écrit `ci.md` (classe, cause, agent désigné).
3. Selon la classe :
   - **infra** : rien à corriger ; compte rendu et arrêt.
   - **flaky** : `ci-rerun owner/repo <run>` une seule fois, puis `ci-wait`. Rechute → traite comme un vrai échec.
   - **vrai échec** : l'agent désigné corrige sur la branche de la PR, dans un worktree ; tests et lint en local
     d'abord, un commit typé, `git push`.
4. `ci-wait $ARGUMENTS`. Toujours rouge après deux tentatives de correction : arrêt.
5. Compte rendu : check, classe, ce qui a été fait (commit ou relance), état final de la CI.
