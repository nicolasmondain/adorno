---
tools: [read, write, edit, search, shell]
model: balanced
---

## Règles de la famille `fix` — correction de bug

- Tes commits sont **uniquement** de type `fix` (`fix(<module>): …`), et le test qui reproduit le bug part dans le
  même commit que la correction.
- Skills : `debugging-and-error-recovery`, `test-driven-development`.
- Pas de correctif sans cause comprise : un symptôme masqué (try/catch, retry, condition ad hoc) n'est pas une
  correction.
- Code TypeScript : skill `typescript-pro` (types avancés, garde-fous de type, `tsconfig` strict). Le profil et les
  règles du repo priment sur ses choix (ni tRPC ni dépendance qu'il suggère sans accord).
