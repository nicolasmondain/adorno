---
description: Surveille un ou plusieurs canaux Slack selon une règle nommée — mots inclus ou regex, sur une période, au plus N messages — et lance l'action configurée (agent, workflow ou consigne) sur chaque message qui correspond, une seule fois par message. Lecture seule sur Slack ; compte rendu envoyé à toi seul. À lancer à la main ou depuis ta propre planification.
argument-hint: <nom de la règle> [--since 24h] [--max 200] [--dry-run] [--all]
---

Entrée : $ARGUMENTS. Les règles se déclarent dans ta couche personnelle (`local/adorno.yaml` › `slack.watches`) :

```yaml
slack:
  user_id: U0123ABCD                 # toi : destinataire des comptes rendus
  watches:
    prod-timeouts:
      channels: ["#notif-errors"]
      includes: ["Timeout", "ETIMEDOUT"]   # au moins un mot (insensible à la casse)…
      regex: 'took (\d{4,})ms'             # …ou cette regex
      since: 24h                           # 90m, 24h, 7d ou une date
      max_messages: 200                    # messages lus au plus, les plus récents d'abord
      action:
        agent: agent:core:analyst          # ou workflow: workflow:issue:fix, ou rien
        prompt: "Rattache l'erreur à un module et dis si elle est nouvelle."
        level: L0                          # droits de l'action (L0 par défaut)
      notify: dm                           # dm | draft | none
```

Dossier d'exécution : `~/.adorno/runs/slack-watch-<nom>-<date>/`.

1. **Réglages** — `adorno-watch/scripts/watch-conf slack-watch <nom>` ; `--since`, `--max` les remplacent pour cette
   exécution. Règle absente (code 3) → propose le skill `adorno-setup`.
2. **Lire** — pour chaque canal, l'historique depuis `since` avec le connecteur Slack (lecture de canal, réponses des
   fils comprises si `threads: true`), jusqu'à `max_messages`. Normalise en `messages.json` (format du skill
   `adorno-watch`).
3. **Filtrer** — `watch-match <nom> messages.json` → `matches.json` : ce qui correspond et n'a pas encore été traité
   (`--all` retraite tout). Aucun résultat → compte rendu court, `watch-seen touch slack-watch-<nom>`, fin.
4. **Annoncer** — plus de 20 correspondances : dis-le et demande avant de lancer les actions (coûteuses).
   `--dry-run` : arrête-toi ici avec la liste.
5. **Agir** — pour chaque message, dans l'ordre chronologique, l'action de la règle avec le message, son lien et le
   fil complet en entrée, plus la `prompt` de la règle :
   - `agent:` → l'agent, en lecture seule sauf si `level` le permet ;
   - `workflow:` → le workflow, avec `ADORNO_LEVEL` = `level` (un workflow qui publie sur GitHub reste borné par les
     droits du repo) ;
   - seulement `prompt:` → `agent:core:analyst` avec cette consigne.
   Les messages sont indépendants : traite-les en parallèle par lots de 3. Un échec n'arrête pas les autres.
6. **Retenir** — `watch-seen mark slack-watch-<nom> <id>…` pour chaque message dont l'action a abouti (pas ceux en
   échec), puis `watch-seen touch slack-watch-<nom>`.
7. **Rendre compte** — `report.md` : période, canaux, messages lus, correspondances ; pour chacune, le lien, l'auteur,
   l'extrait qui a déclenché, le résultat de l'action. Envoi selon `notify` (skill `adorno-watch` : à toi seul,
   jamais dans le canal).
