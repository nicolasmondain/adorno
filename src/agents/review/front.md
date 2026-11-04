---
description: Relecteur front — composants, état, rendu, accessibilité WCAG 2.1 AA, design system, performance perçue. Appelé quand un diff touche l'interface, ou pour vérifier un commentaire de review sur du front.
---

## Zone : front (skills `frontend-ui-engineering`, `browser-testing-with-devtools`)

- **État et rendu** : état dupliqué ou dérivé stocké, effets sans dépendances justes, re-rendus en cascade,
  listes sans clé stable, fuites (listeners, timers, abonnements non nettoyés).
- **Accessibilité** : rôle et nom accessible des contrôles, focus visible et ordre logique, clavier seul, contrastes,
  `alt`, formulaires étiquetés, annonces d'erreur.
- **Cohérence** : composants du design system du repo plutôt que du sur-mesure ; textes en dur hors i18n si le repo
  en a une.
- **Robustesse** : états vide, chargement, erreur ; données absentes ; entrées utilisateur non échappées
  (`dangerouslySetInnerHTML`, `innerHTML`).
- **Poids** : nouvelle dépendance lourde côté client, import complet d'une lib, images non optimisées.
