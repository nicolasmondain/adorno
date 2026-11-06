---
description: Relit la PR d'un collègue dans un workspace dédié — relecteurs spécialisés choisis selon les zones de code touchées (front, back, mongodb, api, sécurité…), en parallèle, puis ton agent qui revérifie, tranche et rédige. Par défaut, une review en attente que tu relis et soumets toi-même.
argument-hint: <owner/repo#N> [--mode report|pending|auto]
---

Entrée : $ARGUMENTS

**Exécution** — avant toute chose : `adorno-github/scripts/run-begin --workflow workflow:pr:review --mode <mode> --level L3 --repo owner/repo` (`--deny submit` en mode `pending`) ; garde `id` et `dir` (le dossier d'exécution). Appelé par un autre workflow qui a déjà ouvert la sienne : réutilise-la. Toujours, même après un échec : `run-end <id>`. Sans exécution ouverte, les scripts refusent toute écriture.

| Mode | Ce qui part sur GitHub | Niveau |
| --- | --- | --- |
| `report` | rien : le rapport seul | L0 |
| `pending` (défaut) | une review **en attente**, visible de toi seul, que tu modifies et soumets | L3 |
| `auto` | la review soumise (`COMMENT` ou `REQUEST_CHANGES`, jamais `APPROVE` sauf `allow_approve`) | L3 |

Dossier d'exécution : `<workspace>/.agent-run/review-<date>/` (exclu de git par `pr-workspace`), passé à `run-begin
--dir` ; appelé par `review:requested`, un sous-dossier de son exécution.

1. **Préconditions** — `pr-review-requested owner/repo` (ou `pr-diff`) : PR fermée, repassée en brouillon, ou review en
   attente déjà ouverte par toi (`pendingReview`) → arrêt, et dis-le.
2. **Workspace** — `pr-workspace owner/repo#N` : clone dédié sous `~/.adorno`, au commit de tête, `diffBase`
   calculé (diff de la PR contre sa propre base, jamais le cumul d'une pile). Tes propres copies ne sont pas touchées.
3. **Contexte** — `pr-diff owner/repo#N` (description, fichiers, diff) ; issue liée si la description en cite une.
4. **Zones et relecteurs** — `pr-areas owner/repo <fichier de diff>` → zones touchées et `reviewers` (`always` + ceux de
   chaque zone, réglés dans `repos.yaml` et surchargeables dans `local/adorno.yaml`). Les fichiers en `other` vont à `review:code`.
5. **Vérifications locales** selon `commands.review_checks` : `none` par défaut (un point qui demande une exécution est
   un ❓, la CI tranche) ; `lint` : lint et typecheck seulement ; `full` : + install et tests. Sorties dans `checks.log`.
   Une PR venue d'un fork (`untrusted: true`) : jamais d'exécution, quel que soit le réglage.
6. **Spécialistes en parallèle** — tous les agents de `reviewers` dans le même tour, en mode revue, chacun avec le
   workspace, `diffBase`, la description, les fichiers de sa zone (tous pour `review:code`) → `reviews/<agent>.json`.
7. **Fusion** — `adorno-github/scripts/review-merge reviews/ > review.json` : toujours la même fusion (doublons, sévérité
   la plus haute, verdict le plus sévère) ; ne lis pas toi-même chaque avis, seulement `review.json` (`invalid` liste un
   avis mal formé : relance ce spécialiste une fois).
8. **Ta passe** — `agent:adorno`, situation 2, avec `review.json` et le workspace : charge la zone (règles du repo,
   profil, `repo-conf`), revérifie chaque point, garde ce que tu posterais (8 commentaires en ligne au plus), écrit
   `review-final.json` et `review-notes.md`. S'il rend des demandes `consult`, lance ces spécialistes sur leur
   question précise et rappelle-le avec leurs réponses (une fois).
9. **Publier** — `report` : rien. `pending` : `pr-review-submit owner/repo#N review-final.json` sans `event` → review en
   attente. `auto` : même script, avec l'`event` choisi. Rien qui vaille d'être posté → pas de review, et dis-le.
10. **Compte rendu** — périmètre, une ligne par point (sévérité, `file:line`, problème, conséquence, source), verdict,
    relecteurs et zones, points écartés et pourquoi, lien de la review.
