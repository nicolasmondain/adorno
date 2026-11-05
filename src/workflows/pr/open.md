---
description: Ouvre la PR d'une branche prête — porte de revue d'abord (spécialistes par zone + ton agent), puis titre et description en anglais selon ton gabarit, relecteurs du registre. Pas de PR tant qu'un 🔴 ou un 🟠 n'est pas réglé ou accepté.
args: "<owner/repo> <branche> [dossier .agent-run]"
uses:
  skills: [adorno-github, adorno-commit, adorno-profile, adorno-voice]
  agents: [agent:core:triage, agent:adorno, agent:review:code, agent:review:ponytail, agent:review:front, agent:review:back, agent:review:mongodb, agent:review:api, agent:review:security, agent:review:tests]
---

Entrée : {{args}}

1. `export ADORNO_LEVEL=L3` (un `max_level` plus bas du repo l'emporte : alors s'arrêter ici).
2. **Vérifications locales**, dans le clone où vit la branche : nom conforme à `branch_pattern`, à jour avec la base
   (`git fetch` puis `git diff origin/<base>...HEAD` : la vraie portée), chaque commit au format Conventional Commits,
   tests, lint et typecheck verts. Un échec : arrêt et compte rendu.
3. **Porte de revue** (situation 1 de `agent:adorno`) : `pr-areas owner/repo` sur ce diff → relecteurs ; ils
   relisent en parallèle, en lecture seule ; `agent:adorno` revérifie et rend son verdict. **Pas de PR tant qu'un 🔴 ou un 🟠 n'est pas réglé ou explicitement accepté par
   l'utilisateur** ; les 🟡 et ❓ restants vont dans la description (`Impact / Risks`, Verification).
4. `agent:adorno` rédige en anglais, dans ta voix (skill `adorno-voice`), avec la skill de PR du repo si `repo-conf` en donne une (`pr_skill`) :
   - le titre au format Conventional Commit du changement principal ;
   - la description selon `process.md` § Pull requests : What / How / mermaid / Verification, `How to test` ouvert par
     les commandes réellement lancées et leur résultat, lien vers l'issue (`Fixes #n`). Aucune donnée réelle.
5. **Point de contrôle 2** si `gates` contient `open_pr` : montre titre, description et verdict de la porte, attends le
   « oui ».
6. `git push -u origin <branche>`, puis `pr-open owner/repo <branche> "<titre>" <fichier> --draft` : brouillon tant que
   la CI n'est pas verte (`process.md`), relecteurs du registre sans l'auteur.
7. Rends l'URL de la PR et propose `workflow:pr:watch owner/repo#N`.
