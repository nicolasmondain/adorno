---
description: Accompagne une PR ouverte jusqu'à ce qu'elle soit prête à merger — boucle CI rouge et nouveaux threads de review, avec plafond. Le merge reste à toi.
args: "<owner/repo#N> [--mode draft|auto] [--rounds 5]"
uses:
  skills: [adorno-github]
  workflows: [workflow:ci:red, workflow:review:received]
---

Entrée : {{args}}

Mode par défaut : `auto` si la spec l'a validé, sinon `draft`. Plafond par défaut : 5 tours.

À chaque tour :

1. `pr-status owner/repo` → la ligne de cette PR.
2. Selon `blocker` :
   - `ci-red` → `workflow:ci:red owner/repo#N` ;
   - `changes-requested` ou `unresolved-threads` → `workflow:review:received owner/repo#N --mode <mode>` ;
   - `ci-running` → `ci-wait owner/repo#N` ;
   - `conflicts` → **arrêt** : un rebase réécrit l'historique, l'utilisateur décide ;
   - `waiting-review` → arrêt : rien à faire tant que personne n'a relu ;
   - `ready` → arrêt : CI verte et review approuvée.
3. Rien n'a bougé depuis le tour précédent → arrêt, pour ne pas tourner à vide.

**Point de contrôle 3** : la PR prête, rends le lien et le résumé des tours. Le merge est à l'utilisateur, jamais
automatique.
