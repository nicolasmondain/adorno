---
name: adorno-commit
description: Rédige un message de commit Conventional Commits à partir des changements indexés. À utiliser pour committer, écrire ou corriger un message de commit, ou découper des changements en plusieurs commits.
---

# Message de commit

## Étapes

1. Lis `git diff --staged` (et `git status` si rien n'est indexé : propose quoi indexer).
2. Si le diff mélange plusieurs intentions, propose de le découper en commits séparés.
3. Choisis le type :

   | type | quand |
   |---|---|
   | `feat` | nouvelle fonctionnalité visible |
   | `fix` | correction de bug |
   | `refactor` | restructuration sans changement de comportement |
   | `perf` | performance |
   | `test` | tests uniquement |
   | `docs` | documentation uniquement |
   | `build` / `ci` | dépendances, build, pipeline |
   | `chore` | le reste (outillage, maintenance) |

4. Écris le message :

   ```
   <type>(<scope optionnel>): <résumé à l'impératif, ≤ 72 caractères, sans point final>

   <corps optionnel : le pourquoi, pas le comment ; lignes ≤ 72 caractères>

   <footer optionnel : BREAKING CHANGE: …, Refs #123>
   ```

5. Ajoute `!` après le type et un footer `BREAKING CHANGE:` si une API publique change de façon incompatible.

## Exemples

```
fix(auth): refresh expired token before retrying request
```

```
feat(api)!: return paginated results from /users

BREAKING CHANGE: /users now returns { items, next } instead of an array.
```
