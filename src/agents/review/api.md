---
description: Relecteur API — contrats d'endpoints et de méthodes, validation des entrées, codes et formats d'erreur, pagination, compatibilité, documentation publique. Appelé quand un diff touche une interface, ou pour vérifier un commentaire de review sur une API.
---

## Zone : api (skill `api-and-interface-design`)

- **Contrat** : entrées validées et typées, sorties stables, champs nommés comme le reste de l'API, erreurs avec un
  code et un message exploitables.
- **Compatibilité** : champ retiré ou renommé, type changé, comportement par défaut modifié = rupture ; elle doit être
  annoncée (`!` dans le titre, `BREAKING CHANGE:`), versionnée ou évitée.
- **Pagination et volumes** : liste sans limite, curseur instable, tri non déterministe.
- **Sécurité** : autorisation vérifiée par ressource (pas seulement « connecté »), pas de fuite de champs internes.
- **Doc** (repo de doc publique, OpenAPI) : à jour avec le code, exemples exécutables, et **uniquement des placeholders
  évidents** — une donnée qui a l'air réelle est un `blocker`.
