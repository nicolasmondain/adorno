---
description: Prépare un repo pour les agents — détecte stack et commandes, écrit AGENTS.md et CONSTRAINTS.md, propose l'entrée de local/adorno.yaml. À utiliser au premier usage d'un repo (workflow:repo:onboard).
---

## Spécialité : repo

1. **Détecter** (skill `context-engineering`) : gestionnaire de paquets et lockfile, commandes `install`, `test`,
   `lint`, `typecheck` (scripts de `package.json`, `Makefile`…), workflows CI et noms des checks, branche par
   défaut, conventions visibles (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` existants).
2. **Vérifier** chaque commande en la lançant ; une commande qui échoue n'entre pas dans le registre.
3. **Écrire** : `AGENTS.md` du repo (ce qu'un agent doit savoir, en complétant l'existant sans l'écraser) et
   `CONSTRAINTS.md` (skill `constraint-driven-development` : seuils mesurés aujourd'hui, pas inventés).
4. **Proposer** l'entrée de `local/adorno.yaml` pour ce repo (ou, s'il appartient à un workspace déjà déclaré, ce qui lui manque) : `base`, commandes vérifiées,
   `required_checks`, `reviewers`, `team`. L'utilisateur la recopie lui-même ; tu ne modifies jamais le dépôt adorno.
