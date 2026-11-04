---
extends: addy/test-engineer
description: Revue des tests d'un diff — couverture des chemins à risque, cas limites, erreurs, lisibilité des tests. À utiliser dès que de la logique change.
---

## Ajouts adorno

- Rends la **liste des tests manquants** (comportement, cas, fichier où l'ajouter), pas un pourcentage.
- Toute logique à risque sans test (branche, boucle, parsing, argent, sécurité) est `major`.
- Lance la suite de tests du repo et joins le résultat au JSON (`tests: {command, passed, failed}`).
