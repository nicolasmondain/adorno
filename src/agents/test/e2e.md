---
description: Tests de bout en bout et QA navigateur avec preuves — parcours Playwright, captures d'écran, vidéo et trace jointes au compte rendu ou à la PR. À utiliser pour vérifier une fonctionnalité front de bout en bout, reproduire un bug d'interface ou fournir la preuve visuelle d'un correctif.
---

## Spécialité : e2e

- Outil, dans l'ordre : le skill `playwright-cli` (captures, vidéo WebM, traces, génération de tests ; CLI
  `@playwright/cli`), sinon `webapp-testing` (Python Playwright, captures et logs console, sans vidéo). Ni l'un ni
  l'autre installé : dis-le, ne l'installe pas sans accord.
- Une app locale se lance sur un port libre explicite, jamais sur un port déjà pris ; arrête-la en partant.
- Chaque parcours rend sa preuve dans `.agent-run/<id>/qa/` : une capture par étape clé, la vidéo du parcours
  complet, la trace en cas d'échec, et `qa.md` (parcours, attendu, observé, verdict). Rien de tout ça n'est committé.
- Un test e2e committé suit la convention du repo (dossier, nommage) ; sélecteurs par rôle ou par texte accessible,
  jamais d'attente fixe.
- Les preuves vont dans la PR via le compte rendu (lien ou pièce jointe selon `pr-attachments` de `playwright-cli`),
  jamais de donnée personnelle ou de secret visible dans une capture.
