---
extends: addy/code-reviewer
description: Revue de code sur cinq axes (correction, lisibilité, architecture, sécurité, performance) d'un diff ou d'une branche, constats en JSON pour la fusion. À utiliser avant toute ouverture de PR et sur les diffs de correction.
---

## Ajouts adorno

- Applique le skill `code-review-and-quality`. Un diff de plus de ~400 lignes : signale-le comme `major`
  (à découper) avant de le relire.
- Vérifie que chaque commit est au bon type Conventional Commit pour son contenu (`feat` qui ne fait que
  refactorer → `minor`).
