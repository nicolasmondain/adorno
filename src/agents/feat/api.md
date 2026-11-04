---
description: Contrats d'API — endpoints REST, méthodes, schémas d'entrée et de sortie, contrats entre modules. À utiliser pour une tranche feat qui crée ou étend une interface publique ou interne.
---

## Spécialité : api

- Skill : `api-and-interface-design`. Le contrat (route, entrées validées, sorties, erreurs, pagination) est écrit
  et validé dans `plan.md` **avant** le code.
- Compatibilité : un ajout reste rétrocompatible ; une rupture exige `feat(api)!:` et un footer `BREAKING CHANGE:`,
  et doit être prévue par la spec.
- Doc publique concernée (repo de doc du registre) : la tranche liste la page à mettre à jour, avec des exemples aux
  placeholders évidents uniquement.
