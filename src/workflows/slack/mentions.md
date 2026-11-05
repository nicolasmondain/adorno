---
description: Chaque fois que tu es mentionné sur Slack (sur tous les canaux ou une liste), analyse le problème de la conversation et t'envoie, à part, l'analyse complète avec le lien vers la conversation et un brouillon de réponse dans ta voix. Une seule fois par mention. Lecture seule sur Slack. À lancer à la main ou depuis ta propre planification.
args: "[--since 24h] [--channels '#a,#b'] [--dry-run] [--all]"
uses:
  skills: [adorno-watch, adorno-voice, adorno-github]
  agents: [agent:core:analyst, agent:adorno]
model: balanced
---

Entrée : {{args}}. Réglages dans ta couche personnelle (`local/adorno.yaml` › `slack.mentions`) :

```yaml
slack:
  user_id: U0123ABCD           # ton identifiant Slack (Profil › … › Copier l'identifiant de membre)
  mentions:
    channels: ["#team", "#product-bug"]   # vide = tous les canaux
    groups: ["@devs"]                     # groupes dont la mention compte aussi
    since: 24h
    max_messages: 50
    notify: dm                            # dm | draft | none
```

Dossier d'exécution : `~/.adorno/runs/slack-mentions-<date>/`.

1. **Réglages** — `adorno-watch/scripts/watch-conf slack-mentions` (code 3 → skill `adorno-setup`).
   `user_id` absent : retrouve-le avec le connecteur (ton profil) et propose de l'ajouter.
2. **Chercher** — avec le connecteur Slack, les messages qui contiennent `<@user_id>` (et chaque groupe de
   `groups`) depuis `since`, limités à `channels` s'il y en a, `max_messages` au plus. Écarte les messages que tu as
   écrits toi-même et ceux où tu as déjà répondu dans le fil après la mention. Normalise en `mentions.json`.
3. **Ne garder que le nouveau** — `watch-seen filter slack-mentions mentions.json` (`--all` : tout). Rien →
   `watch-seen touch slack-mentions`, une ligne de compte rendu, fin. `--dry-run` : la liste, et fin.
4. **Analyser** — pour chaque mention, en parallèle par lots de 3 : `agent:core:analyst` avec le fil complet
   (`thread_ts`), le canal et le lien → `<id>/analysis.md`.
5. **Préparer la réponse** — `agent:adorno` lit l'analyse et écrit, dans ta voix (skill `adorno-voice`, registre
   Slack), un brouillon de réponse au fil → `<id>/reply.md`. Une question à laquelle seul toi peux répondre :
   le brouillon le dit au lieu d'inventer. Le brouillon **n'est jamais posté**.
6. **T'envoyer** — un message par mention, selon `notify` (à toi seul) :
   - en tête : qui t'a mentionné, où, quand, et le **lien vers la conversation** ;
   - le problème en une phrase, puis l'analyse complète ;
   - le brouillon de réponse, à copier.
   Plusieurs mentions dans le même fil : un seul message.
7. **Retenir** — `watch-seen mark slack-mentions <id>…` pour chaque mention envoyée, puis
   `watch-seen touch slack-mentions`. En réponse : le tableau des mentions traitées (canal, auteur, problème, lien).
