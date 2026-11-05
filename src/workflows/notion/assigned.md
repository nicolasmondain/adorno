---
description: Trouve les documents Notion qui te sont assignés (propriétés « personne » des bases suivies, statut encore ouvert) et lance sur chaque nouveau document l'agent ou le workflow qui convient — choisi par base dans ta config, sinon par le routeur. Lecture seule sur Notion ; compte rendu envoyé à toi seul. Modes report (défaut) ou run.
args: "[--mode report|run] [--since 30d] [--dry-run] [--all]"
uses:
  skills: [adorno-watch, adorno-github]
  agents: [agent:core:analyst, agent:core:router, agent:adorno]
  workflows: [workflow:spec:new, workflow:issue:fix]
model: balanced
---

Entrée : {{args}}. Réglages dans ta couche personnelle (`local/adorno.yaml` › `notion.assigned`) :

```yaml
notion:
  assigned:
    properties: ["Assignee", "Owner"]        # propriétés « personne » qui valent assignation
    databases: ["https://www.notion.so/…"]   # bases suivies ; vide = recherche dans tout l'espace
    exclude_status: ["Done", "Archived"]     # statuts ignorés
    since: 30d                               # documents modifiés depuis
    max_messages: 20                         # documents traités au plus par exécution
    agents:                                  # quoi lancer selon la base (nom ou lien) ; sinon le routeur décide
      "Roadmap": workflow:spec:new
      "Bugs": workflow:issue:fix
    mode: report                             # report : analyse et plan · run : lance l'agent ou le workflow
    level: L0                                # droits en mode run
    notify: dm
```

Dossier d'exécution : `~/.adorno/runs/notion-assigned-<date>/`.

1. **Réglages** — `adorno-watch/scripts/watch-conf notion-assigned` (code 3 → skill `adorno-setup`) ; `--mode` et
   `--since` les remplacent. Toi dans Notion : le connecteur (ton utilisateur).
2. **Trouver** — avec le connecteur Notion : dans chaque base de `databases`, les pages dont une propriété de
   `properties` te contient, statut hors `exclude_status`, modifiées depuis `since` ; sans base, une recherche des
   pages qui te sont assignées. `max_messages` au plus, les plus récentes d'abord. Normalise en `docs.json` :
   `{id, title, url, database, status, assigned_by, last_edited}`.
3. **Ne garder que le nouveau** — `watch-seen filter notion-assigned docs.json` (`--all` : tout). Un document déjà
   traité mais modifié depuis ne revient que s'il change de statut. Rien → fin. `--dry-run` : la liste, et fin.
4. **Lire et choisir** — pour chaque document : son contenu complet, ses propriétés et commentaires. L'action :
   `agents` de la config pour sa base, sinon `agent:core:router` (une spec à cadrer → `workflow:spec:new`, un bug →
   `workflow:issue:fix`, une question → `agent:core:analyst`…).
5. **Agir** —
   - `report` (défaut) : `agent:core:analyst` rend l'analyse et ce que l'action choisie ferait (plan, repo visé,
     droits nécessaires), sans rien lancer ;
   - `run` : l'action choisie, avec `ADORNO_LEVEL` = `level` et les droits du repo visé. Les étapes qui demandent ta
     validation (spec, ouverture de PR) restent des points d'arrêt.
   Les documents sont indépendants : en parallèle par lots de 3.
6. **Retenir** — `watch-seen mark notion-assigned <id>…` pour chaque document traité, puis
   `watch-seen touch notion-assigned`.
7. **Rendre compte** — `report.md` et un message selon `notify` (à toi seul) : par document, le titre et son lien,
   la base, l'action choisie et pourquoi, le résultat, ce qui attend ta décision. Notion n'est jamais modifié.
