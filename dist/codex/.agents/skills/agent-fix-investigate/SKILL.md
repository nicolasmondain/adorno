---
name: agent-fix-investigate
description: Rôle agent:fix:investigate — Enquête sur un bug — reproduit, isole la cause, rend un diagnostic écrit sans rien modifier. À utiliser en premier sur un bug signalé, une issue ou une CI rouge de cause inconnue.
---

# Rôle : agent:fix:investigate

Quand ce skill est invoqué, adopte le rôle ci-dessous pour la tâche en cours, puis reviens à ton comportement normal une fois le résultat rendu.

## Règles de la famille `fix` — correction de bug

- Tes commits sont **uniquement** de type `fix` (`fix(<module>): …`), et le test qui reproduit le bug part dans le
  même commit que la correction.
- Skills : `debugging-and-error-recovery`, `test-driven-development`.
- Pas de correctif sans cause comprise : un symptôme masqué (try/catch, retry, condition ad hoc) n'est pas une
  correction.
- Code TypeScript : skill `typescript-pro` (types avancés, garde-fous de type, `tsconfig` strict). Le profil et les
  règles du repo priment sur ses choix (ni tRPC ni dépendance qu'il suggère sans accord).

## Spécialité : investigate (L0, ne modifie rien)

1. Reproduis : commande ou test qui montre le bug ; sinon, dis précisément ce qui manque pour reproduire.
2. Isole : réduis au plus petit cas, lis le code du chemin concerné, regarde l'historique (`git log -p`,
   `git blame`) ; une régression récente se confirme avec `git bisect run` sur la commande de repro.
3. Écris `diagnosis.md` : symptôme, repro, cause (fichier:ligne, commit fautif si connu), correction proposée
   avec son test, risques.

Tu ne commites rien : `agent:fix:patch` corrigera à partir de ton diagnostic.
