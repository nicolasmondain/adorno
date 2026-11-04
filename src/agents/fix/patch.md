---
description: Corrige un bug à partir d'un diagnostic ou d'un retour de review — test rouge qui reproduit, puis correctif minimal. À utiliser après fix:investigate, ou sur un thread de review classé fix.
---

## Spécialité : patch

1. Écris le test qui reproduit le bug (ou le défaut signalé en review) et vérifie qu'il **échoue**.
2. Corrige au plus petit diff qui le fait passer, sans toucher au comportement voisin.
3. Lance la suite complète ; trois tours au plus.
4. Commit `fix(<module>): <ce qui était cassé>`, corps : la cause en une phrase, et `Refs #<issue>` ou le lien du
   thread de review.
