---
name: adorno-github
description: Scripts déterministes pour tout ce qui touche GitHub — lister ses PRs et les reviews qu'on attend de soi, préparer un workspace dédié par PR, classer un diff par zone de code, lire et publier des reviews, répondre et résoudre, relancer, suivre la CI, ouvrir une PR. À utiliser dès qu'un agent ou un workflow doit lire ou écrire sur GitHub ; ne jamais appeler `gh` en écriture à la main.
---

# adorno-github

Tout accès à GitHub passe par les scripts de `scripts/` (chemin relatif à ce fichier). Ils lisent le registre
`repos.json` (généré depuis `repos.yaml` du kit), refusent un repo non enregistré, appliquent les niveaux de droits
et rendent du JSON sur stdout ; les messages vont sur stderr. Prérequis : `gh` authentifié et `jq`.

## Scripts

| Script | Fait | Niveau |
| --- | --- | --- |
| `repo-conf owner/repo` | réglages fusionnés du repo (base, commandes, politique de threads…) | L0 |
| `pr-status [owner/repo]` | toutes tes PRs ouvertes : review, CI, threads, `blocker` | L0 |
| `pr-review-requested [owner/repo]` | PRs où ta review est demandée (directe ou par équipe), `reviewedHead` | L0 |
| `pr-feedback-fetch owner/repo#N` | threads, commentaires et résumés de review à traiter (`needsReply`, `bot`), CI | L0 |
| `pr-workspace owner/repo#N` | workspace dédié sous `~/.adorno` (clone à part, worktree au commit de tête) | L0 * |
| `pr-workspace --clean` | supprime les workspaces des PRs fermées | L0 * |
| `pr-areas owner/repo FICHIER_DIFF` | zones de code touchées (front, back, mongodb…) et relecteurs à appeler | L0 |
| `pr-diff owner/repo#N` | métadonnées + diff sauvegardé dans un fichier | L0 |
| `issue-fetch owner/repo#N` | issue + commentaires | L0 |
| `pr-merged owner/repo [--since 14d] [--author LOGIN] [--pr N]` | PRs mergées (les tiennes par défaut) : commit de merge, fichiers, rapport d'impact déjà posté ou non | L0 |
| `pr-deploys owner/repo#N` | quand le merge a atteint chaque environnement (déploiements GitHub) ; `source: none` sans déploiements | L0 |
| `ci-wait owner/repo#N [secondes]` | attend la fin des checks (requis seulement si configurés) | L0 |
| `ci-failed owner/repo#N [lignes]` | runs en échec sur le dernier commit + fin des logs dans des fichiers | L0 |
| `ci-rerun owner/repo RUN_ID` | relance les jobs en échec, une seule fois par run | L2 |
| `run-begin --workflow ID --mode report\|draft\|pending\|comment\|auto --level Lx --repo owner/repo… [--deny a,b] [--ttl 2h]` | ouvre une exécution pour les repos nommés : ce qu'elle a le droit d'écrire, son dossier ; `report`/`draft` forcent la simulation | — |
| `run-end ID` | clôt l'exécution (à faire toujours, même après un échec) | — |
| `git-push owner/repo [BRANCHE] [--dir CHEMIN]` | pousse une branche sans PR : jamais en force, jamais la base, nom conforme à `branch_pattern` | L2 |
| `pr-push owner/repo#N` | pousse les commits du workspace sur la branche de ta PR, jamais en force | L2 |
| `pr-reply owner/repo#N THREAD_ID FICHIER` | répond dans un thread (`-` = stdin) | L3 |
| `pr-resolve owner/repo#N THREAD_ID` | résout un thread si `resolve_threads: author` et que tu es l'auteur | L3 |
| `pr-comment owner/repo#N FICHIER` | commentaire dans la conversation de la PR (`-` = stdin) | L3 |
| `pr-review-submit owner/repo#N FICHIER_JSON` | publie une review avec commentaires en ligne ; `APPROVE` seulement si `allow_approve` | L3 |
| `pr-rerequest owner/repo#N [login…]` | redemande une review (défaut : ceux qui ont déjà relu) | L3 |
| `pr-open owner/repo BRANCHE "type(scope): titre" FICHIER [--draft]` | ouvre la PR, demande les relecteurs du registre | L3 |

\* Écrit seulement sous `~/.adorno` (aucune variable ne le déplace), jamais dans tes copies de travail ni sur GitHub.

## Règles

- **Droits** : chaque script d'écriture vérifie le `max_level` du repo, ses `permissions.deny`, et l'exécution
  active (`run-begin` : niveau, actions refusées, repos couverts). Sans exécution active : L0, toute écriture est
  refusée. Une exécution ne vaut que pour les repos qu'elle nomme ; deux exécutions sur un même repo (deux sessions) :
  la plus stricte s'applique, et le script le signale. `ADORNO_LEVEL` peut seulement **abaisser** le niveau.
- **Simulation** : une exécution en mode `report` ou `draft`, ou `ADORNO_DRY_RUN=1`, fait afficher aux scripts
  d'écriture ce qu'ils publieraient, sans rien publier.
- **Pousser** : `git-push owner/repo <branche>` (sans PR) ou `pr-push owner/repo#N` ; jamais `git push` direct.
- **Langue** : les textes publiés sur GitHub (réponses, descriptions de PR) sont dans `reply_language` du repo
  (`en` par défaut), quelle que soit la langue de la conversation.
- **Fichiers de travail** : chaque script a son propre dossier temporaire, lisible par toi seul (`~/.adorno/tmp/<pid>`, purgé après un jour) ; les livrables vont dans le dossier d'exécution que rend `run-begin`.
- **Workspaces** : un par PR, `~/.adorno/workspaces/<owner>__<repo>/pr-<N>`, détaché au commit de tête. `.agent-run/`
  y est exclu de git. `pr-workspace` refuse de déplacer un workspace qui contient du travail non poussé.
- **Signature** : si `reply_footer` est défini pour le repo, il est ajouté à tout texte publié.

## Codes de sortie

| Code | Sens | Que faire |
| --- | --- | --- |
| 0 | succès | — |
| 1 | échec (ou CI rouge pour `ci-wait`) | lire stderr |
| 2 | mauvais usage | corriger les arguments |
| 3 | repo déclaré nulle part (`local/adorno.yaml` : `repos`, `workspaces`) | s'arrêter et le signaler, ne jamais contourner |
| 4 | refusé par la politique du repo | s'arrêter et le signaler |
| 5 | niveau de droits insuffisant | s'arrêter et demander l'élargissement à l'utilisateur |
| 6 | délai dépassé (`ci-wait`) | relancer plus tard ou rendre compte |
