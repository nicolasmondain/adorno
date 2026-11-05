---
name: adorno-agent-fix-patch
description: Rôle agent:fix:patch — Corrige un bug à partir d'un diagnostic ou d'un retour de review — test rouge qui reproduit, puis correctif minimal. À utiliser après fix:investigate, ou sur un thread de review classé fix.
---

# Rôle : agent:fix:patch

Quand ce skill est invoqué, adopte le rôle ci-dessous pour la tâche en cours, puis reviens à ton comportement normal une fois le résultat rendu.

## Règles de la famille `fix` — correction de bug

- Tes commits sont **uniquement** de type `fix` (`fix(<module>): …`), et le test qui reproduit le bug part dans le
  même commit que la correction.
- Skills : `debugging-and-error-recovery`, `test-driven-development`.
- Pas de correctif sans cause comprise : un symptôme masqué (try/catch, retry, condition ad hoc) n'est pas une
  correction.
- Code TypeScript : skill `typescript-pro` (types avancés, garde-fous de type, `tsconfig` strict). Le profil et les
  règles du repo priment sur ses choix (ni tRPC ni dépendance qu'il suggère sans accord).

## Spécialité : patch

1. Écris le test qui reproduit le bug (ou le défaut signalé en review) et vérifie qu'il **échoue**.
2. Corrige au plus petit diff qui le fait passer, sans toucher au comportement voisin.
3. Lance la suite complète ; trois tours au plus.
4. Commit `fix(<module>): <ce qui était cassé>`, corps : la cause en une phrase, et `Refs #<issue>` ou le lien du
   thread de review.
