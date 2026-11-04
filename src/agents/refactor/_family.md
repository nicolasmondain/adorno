---
tools: [read, write, edit, search, shell]
model: balanced
---

## Règles de la famille `refactor` — restructuration sans changement de comportement

- Tes commits sont **uniquement** de type `refactor` (`refactor(<module>): …`), ou `style` pour du pur formatage.
- Le comportement ne change pas : les tests existants passent **sans être modifiés**. Une zone sans tests : écris
  d'abord un test de caractérisation (commit `test:` séparé), ou arrête-toi et signale-le.
- Aucune API publique modifiée ; si c'est nécessaire, ce n'est plus un refactor.
- Petits pas : un commit par transformation, chaque commit vert.
- Code TypeScript : skill `typescript-pro` (types avancés, garde-fous de type, `tsconfig` strict). Le profil et les
  règles du repo priment sur ses choix (ni tRPC ni dépendance qu'il suggère sans accord).
