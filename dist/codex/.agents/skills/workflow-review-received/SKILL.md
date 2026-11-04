---
name: workflow-review-received
description: workflow:review:received — Passe sur toutes tes PRs ouvertes (ou une seule) — chaque commentaire, thread ou résumé de review sans réponse est vérifié par le spécialiste du sujet dans un workspace dédié, corrigé si besoin, puis ton agent répond dans ta voix et résout. Modes report, draft (défaut), auto.
---

# workflow:review:received

Entrée : la demande de l'utilisateur. Suis les étapes dans l'ordre.

Entrée : la demande de l’utilisateur — sans argument : **toutes** tes PRs ouvertes dans les repos enregistrés.

| Mode | Fait | Niveau | Publie |
| --- | --- | --- | --- |
| `report` | étapes 1 à 4 et 9 : ce qui attend une réponse, avec l'avis vérifié des spécialistes | L0 | rien |
| `draft` (défaut) | + corrections commitées dans le workspace, réponses rédigées (`GH_OPS_DRY_RUN=1`) | L2, sans push | rien : les commits restent dans le workspace |
| `auto` | tout : push, réponses, résolutions, relance des relecteurs | L3 | oui, sauf ce que `adorno-profile` range dans « à valider » |

Exporte `ADORNO_LEVEL` selon le mode ; un `max_level` plus bas du repo l'emporte.

1. **Cibler** — sans argument : `pr-status`, puis `pr-feedback-fetch` sur chaque PR `registered` ; garde celles dont
   `needsReplyCount > 0` ou dont la CI est rouge. Les PRs sont indépendantes : traite-les **en parallèle**, par lots de
   `max_parallel`.
2. **Workspace** — `pr-workspace owner/repo#N` (refusé s'il reste du travail non poussé d'un passage précédent :
   termine-le ou jette-le d'abord). Dossier d'exécution : `<workspace>/.agent-run/feedback-<date>/`, avec
   `feedback.json`.
3. **Trier** — `agent:core:triage` classe chaque élément où `needsReply` est vrai (thread, commentaire général,
   résumé de review) : catégorie (`fix`, `nit`, `test`, `question`, `disagree`, `scope`, `done`), **zone** (déduite
   du fichier visé avec `pr-areas` sur le diff de la PR, ou du sujet du commentaire), spécialiste(s) à consulter,
   agent correcteur pressenti → `triage.json`. Les commentaires de bots ne demandent pas de réponse ; leurs constats
   sont vérifiés comme les autres quand ils visent du code (relecteur IA).
4. **Vérifier ce qui est dit** — pour chaque élément qui affirme quelque chose sur le code (tout sauf `done`), le ou
   les spécialistes de sa zone en mode **consultation**, en parallèle : le relecteur a-t-il raison ? preuve à l'appui
   (code lu, commande lancée dans le workspace) → `consult/<élément>-<agent>.json`.
5. **Décider** — `agent:adorno`, situation 3 : charge la zone (règles du repo, profil, `repo-conf` du repo), lit triage et avis, consulte un autre spécialiste si un avis ne tient pas, et statue
   **confirmé / refusé / reporté** pour chaque élément. Un collègue : pas de preuve contre lui → confirmé. Un bot : pas
   reproduit → refusé. Reporté : la tranche suivante de la pile, nommée.
6. **Corriger** (modes `draft` et `auto`) — dans le workspace, chaque correction par l'agent désigné (`fix:patch`,
   `refactor:simplify`, `test:unit`, ou l'agent de la famille du sujet) : un commit typé par élément, message qui cite
   le commentaire, tests et lint du repo verts, trois tours au plus. Puis `review:code` et `review:ponytail` sur les
   seuls nouveaux commits ; un `blocker` → retour à la correction, deux fois au plus.
7. **Publier** (mode `auto`) — `pr-push owner/repo#N` (jamais forcé). Puis `agent:adorno` écrit chaque réponse
   en anglais dans ta voix, avec le SHA du commit, et publie : `pr-reply` (thread) ou `pr-comment` (commentaire
   général, résumé de review). Il résout (`pr-resolve`) les threads réglés ; il laisse ouverts ceux où il pose une
   question ou conteste, et garde en brouillon tout ce qui est « à valider ».
8. **Relancer** — `pr-rerequest owner/repo#N` pour chaque relecteur dont tous les points sont traités ;
   `ci-wait owner/repo#N`, et `workflow:ci:red` si la CI rougit (deux tentatives au plus).
9. **Rendre compte** — `status.md` par PR et, en réponse, un tableau : PR, élément, ce que disait le relecteur, verdict
   vérifié (raison / en partie / tort / pas clair), action, réponse publiée ou en brouillon. **En tête : ce qui attend
   ta décision.** En `draft`, la commande pour tout publier : `workflow:review:received owner/repo#N --mode auto`.
