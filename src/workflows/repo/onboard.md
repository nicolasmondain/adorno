---
description: Prépare un repo pour les agents — détecte stack, commandes et checks, écrit AGENTS.md et CONSTRAINTS.md, et propose son entrée complète dans local/adorno.yaml. À faire une fois par repo.
args: "<owner/repo> [chemin du clone local]"
uses:
  skills: [adorno-github, adorno-setup]
  agents: [agent:chore:repo]
---

Entrée : {{args}}

1. Clone local (rien n'est publié : aucune exécution à ouvrir) : le chemin donné, sinon un clone dans
   un dossier temporaire.
2. `agent:chore:repo` détecte, vérifie chaque commande en la lançant, et écrit `AGENTS.md` et `CONSTRAINTS.md`
   dans une branche `chore/agents-onboarding` (sans les committer : l'utilisateur relit d'abord).
3. Déclare le repo avec le skill `adorno-setup`, mode `repo` : réglages, droits, voix, éventuellement un workspace,
   écrits dans `local/adorno.yaml` (ignoré par git) après validation, puis `bin/kit install` sur le repo. Rien n'est
   écrit ni committé dans les fichiers suivis du dépôt adorno.
