---
description: Analyse l'impact des PRs que tu as mergées sur un repo — depuis leur déploiement, utilisation, erreurs, temps de réponse, performance et ressources comparés avant / après dans toutes les sources disponibles — et poste le rapport en commentaire de chaque PR. Une PR déjà rapportée est sautée, une trop récente attend. Modes report ou comment (défaut).
args: "<owner/repo> [--since 14d] [--pr N] [--mode report|comment] [--refresh]"
uses:
  skills: [adorno-github, adorno-voice]
  agents: [agent:review:impact, agent:adorno]
model: balanced
---

Entrée : {{args}}

**Exécution** — avant toute chose : `adorno-github/scripts/run-begin --workflow workflow:pr:impact --mode <mode> --level L3 --deny push,reply,resolve,rerequest,review,submit,open_pr,ci_rerun --repo owner/repo` ; garde `id` et `dir` (le dossier d'exécution). Appelé par un autre workflow qui a déjà ouvert la sienne : réutilise-la. Toujours, même après un échec : `run-end <id>`. Sans exécution ouverte, les scripts refusent toute écriture.

| Mode | Fait | Niveau |
| --- | --- | --- |
| `report` | les rapports dans le dossier d'exécution, rien sur GitHub | L0 |
| `comment` (défaut) | + un commentaire par PR analysée | L3 (action `comment`) |

Réglages du repo : `adorno-github/scripts/repo-conf owner/repo` › `impact` (`window`, `min_age`, `environment`, `post`,
`sources`, `post_public`). `post: none` force le mode `report` ; sur un repo public, `pr-comment` refuse le rapport
tant que `post_public` n'est pas vrai (les chiffres de production restent chez toi). Dossier d'exécution : `~/.adorno/runs/pr-impact-<repo>-<date>/`.

1. **Lister** — `pr-merged owner/repo --since <période>` (14 jours par défaut ; `--pr N` pour une seule PR). Écarte, en
   le disant : celles déjà rapportées (`impactReported`, sauf `--refresh`), et celles arrivées en production depuis
   moins de `min_age` (`pr-deploys`) — elles seront prises au prochain passage.
2. **Annoncer** — la liste retenue, et les sources que tu vas interroger (connecteurs présents + `impact.sources`).
   Aucun connecteur d'observabilité : dis-le ; l'analyse se limite alors à GitHub et aux canaux d'alerte, et le
   verdict ne peut pas dépasser `inconclusive`.
3. **Mesurer** — `agent:review:impact` sur chaque PR → `impact/<N>.json` et `impact/<N>.md`. Les PRs sont
   indépendantes : en parallèle par lots de `max_parallel`.
4. **Rédiger** — `agent:adorno` relit chaque rapport (une affirmation sans source est retirée) et écrit le commentaire
   en anglais, dans ta voix :

   ```markdown
   <!-- adorno:impact -->
   ## Impact report — <verdict> (<confidence> confidence)
   Deployed to production <date> · compared <window> before / after · sources: <list>

   | Signal | Before | After | Δ | Source |
   | --- | --- | --- | --- | --- |
   | p95 `GET /api/teams` | 420 ms | 310 ms | −26 % | [Grafana](…) |

   **What changed**: …
   **Watch out**: … (regressions, new errors, with links)
   **Caveats**: other changes in the window, unavailable sources.
   ```

   `--refresh` sur une PR déjà rapportée : un commentaire « Impact report update » qui dit ce qui a changé depuis.
5. **Publier** (mode `comment`) — `pr-comment owner/repo#N <fichier>` pour chaque PR, après avoir vérifié qu'aucune
   donnée personnelle ni secret n'y figure. Une PR `regression` : le commentaire part aussi, et la régression est en
   tête de ton compte rendu.
6. **Rendre compte** — un tableau : PR (lien), verdict, signal principal, lien du commentaire ; puis les PRs écartées
   et pourquoi ; puis, pour chaque régression, la suite proposée (`workflow:issue:fix`, revert à décider par toi).
