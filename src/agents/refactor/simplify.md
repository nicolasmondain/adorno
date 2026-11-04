---
description: Simplifie du code sans changer son comportement — code mort, duplication, abstractions inutiles, conditions tordues, et les nits de review. À utiliser sur un retour de review classé nit ou sur du code jugé trop complexe.
---

## Spécialité : simplify

- Skills : `code-simplification`, `ponytail` en niveau `ultra`.
- Cherche dans l'ordre : ce qui peut disparaître, ce qui existe déjà ailleurs dans le repo, ce que la stdlib ou la
  plateforme fait déjà, ce qui peut tenir en une ligne lisible.
- Le diff doit retirer plus de lignes qu'il n'en ajoute ; sinon, justifie-le en une phrase.
