---
name: adorno-spec-new
description: workflow:spec:new — Cadre une demande de code avec l'agent d'accueil jusqu'à ta validation — en discutant (discuss), ou à partir d'un prompt déjà clair, d'un fil Slack, d'une page Notion, d'une issue ou d'un plan rédigé, en ne posant que les questions de confirmation (confirm). Premier pas de toute feature ou correctif non trivial.
---

# workflow:spec:new

Entrée : la demande de l'utilisateur. Suis les étapes dans l'ordre.

Demande : la demande de l’utilisateur

Trois façons de passer une demande, mélangeables :

| Tu donnes | Exemple | Mode par défaut |
| --- | --- | --- |
| une idée à construire | `export CSV des campagnes ? sur acme/app` | `discuss` : l'agent challenge, une question à la fois |
| un prompt déjà clair | critères, comportement attendu, fichiers visés | `confirm` : spec écrite d'emblée, puis tes confirmations |
| des liens qui détaillent l'implémentation | un fil Slack, une page Notion, `acme/app#42`, `docs/plan.md` | `confirm` |

`--mode` force l'un ou l'autre. En `confirm`, réponds « ok » pour accepter toutes les réponses par défaut, ou corrige
celles qui ne vont pas ; « discutons » repasse en `discuss`.

1. **Repo et dossier** — le repo visé : donné, lu dans les sources (issue, PR), ou le clone courant. Il doit être
   déclaré (`repo-conf` répond) ; sinon, propose d'abord `workflow:repo:onboard`. Crée le dossier d'exécution
   `.agent-run/<date>-<slug>/` dans le repo (et ajoute `.agent-run/` à `.git/info/exclude`).
2. **Sources** — `adorno-inputs/scripts/input-refs "la demande de l’utilisateur"`. Des liens ou un fichier : lis chacun avec son
   connecteur et écris `source.md` (skill `adorno-inputs`). Un connecteur manque ou une page est illisible : dis
   lequel, et demande de le connecter ou de coller le contenu ; ne devine jamais ce que dit un lien.
3. **Mode** — `--mode` s'il est donné. Sinon `confirm` si `source.md` existe ou si la demande dit déjà quoi faire et
   comment le vérifier (comportement attendu, périmètre, au moins un critère testable) ; `discuss` sinon. Annonce le
   mode choisi en une ligne, avec comment en changer.
4. **Cadrer** — délègue à `agent:core:intake` avec la demande, `source.md` et le mode : en `discuss`, la conversation ;
   en `confirm`, la spec d'emblée puis ses confirmations numérotées. Il écrit `spec.md` (avec ses Sources et, s'il y en
   a un, le Plan fourni).
5. **Point de contrôle 1** — présente le résumé de la spec et attends un « oui » explicite, ou des corrections
   (l'agent met la spec à jour et repose la question). Rien d'autre ne démarre avant.
6. Rends le chemin du dossier d'exécution et la commande suivante : `workflow:feature:build <dossier>`, ou
   `workflow:issue:fix <dossier>` pour un correctif.
