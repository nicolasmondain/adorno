---
name: workflow-spec-new
description: workflow:spec:new — Cadre une nouvelle demande avec l'agent d'accueil — discussion, challenge, spec avec critères testables et niveau de droits — jusqu'à ta validation. Premier pas de toute demande non triviale.
---

# workflow:spec:new

Entrée : la demande de l'utilisateur. Suis les étapes dans l'ordre.

Demande : la demande de l’utilisateur

1. Crée le dossier d'exécution `.agent-run/<date>-<slug>/` dans le repo concerné (et ajoute `.agent-run/` à
   `.git/info/exclude`). Le repo doit être déclaré (`repo-conf` répond) ; sinon, propose d'abord `workflow:repo:onboard`.
2. Délègue à `agent:core:intake`, en mode conversation : il lit le repo, pose ses questions une à une, challenge,
   puis écrit `spec.md` avec le niveau de droits et les points de contrôle proposés.
3. **Point de contrôle 1** : présente le résumé de la spec et attends un « oui » explicite de l'utilisateur, ou ses
   corrections. Rien d'autre ne démarre avant.
4. Rends le chemin du dossier d'exécution et la commande suivante (`workflow:feature:build <dossier>`, ou
   `workflow:issue:fix` pour un bug).
