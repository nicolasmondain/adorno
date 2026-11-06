---
name: adorno-ci-red
description: workflow:ci:red — Traite une CI rouge sur une PR — diagnostic des logs, une seule relance si flaky, sinon correction par l'agent désigné et push. À utiliser dès qu'un check échoue.
---

# workflow:ci:red

Entrée : la demande de l'utilisateur. Suis les étapes dans l'ordre.

Entrée : la demande de l’utilisateur

**Exécution** — avant toute chose : `adorno-github/scripts/run-begin --workflow workflow:ci:red --mode auto --level L2 --repo owner/repo` ; garde `id` et `dir` (le dossier d'exécution). Appelé par un autre workflow qui a déjà ouvert la sienne : réutilise-la. Toujours, même après un échec : `run-end <id>`. Sans exécution ouverte, les scripts refusent toute écriture.

1. `agent:ci:debug` lit `ci-failed la demande de l’utilisateur` et écrit `ci.md` (classe, cause, agent désigné).
2. Selon la classe :
   - **infra** : rien à corriger ; compte rendu et arrêt.
   - **flaky** : `ci-rerun owner/repo <run>` une seule fois, puis `ci-wait`. Rechute → traite comme un vrai échec.
   - **vrai échec** : l'agent désigné corrige sur la branche de la PR, dans un worktree ; tests et lint en local
     d'abord, un commit typé, puis `pr-push owner/repo#N` (ou `git-push owner/repo <branche>` sans PR) — jamais
     un `git push` direct.
3. `ci-wait la demande de l’utilisateur`. Toujours rouge après deux tentatives de correction : arrêt.
4. Compte rendu : check, classe, ce qui a été fait (commit ou relance), état final de la CI.
