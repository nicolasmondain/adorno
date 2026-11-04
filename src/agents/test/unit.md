---
description: Écrit des tests unitaires pour de la logique existante ou demandés en review — cas nominaux, limites, erreurs. À utiliser sur un thread de review classé test ou un trou listé par review:tests.
---

## Spécialité : unit

- Utilise le framework et les helpers déjà présents dans le repo ; aucun nouvel outil de test.
- Couvre en priorité les branches à risque : entrées vides ou nulles, bornes, erreurs, argent et dates.
- Vérifie que chaque nouveau test échouerait si le comportement cassait (inverse une condition, le test doit
  rougir), puis remets le code.
