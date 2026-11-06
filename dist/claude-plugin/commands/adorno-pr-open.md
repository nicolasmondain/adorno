---
description: Ouvre la PR d'une branche prête — porte de revue d'abord (spécialistes par zone + ton agent), puis titre et description en anglais selon ton gabarit, relecteurs du registre. Pas de PR tant qu'un 🔴 ou un 🟠 n'est pas réglé ou accepté.
argument-hint: <owner/repo> <branche> [dossier .agent-run]
---

Entrée : $ARGUMENTS

**Exécution** — avant toute chose : `adorno-github/scripts/run-begin --workflow workflow:pr:open --mode auto --level L3 --repo owner/repo` ; garde `id` et `dir` (le dossier d'exécution). Appelé par un autre workflow qui a déjà ouvert la sienne : réutilise-la. Toujours, même après un échec : `run-end <id>`. Sans exécution ouverte, les scripts refusent toute écriture.

1. **Vérifications locales**, dans le clone où vit la branche : nom conforme à `branch_pattern`, à jour avec la base
   (`git fetch` puis `git diff origin/<base>...HEAD` : la vraie portée), chaque commit au format Conventional Commits,
   tests, lint et typecheck verts. Un échec : arrêt et compte rendu.
2. **Porte de revue** (situation 1 de `agent:adorno`) : `pr-areas owner/repo` sur ce diff → relecteurs ; ils
   relisent en parallèle, en lecture seule ; `agent:adorno` revérifie et rend son verdict. **Pas de PR tant qu'un 🔴 ou un 🟠 n'est pas réglé ou explicitement accepté par
   l'utilisateur** ; les 🟡 et ❓ restants vont dans la description (`Impact / Risks`, Verification).
3. `agent:adorno` rédige en anglais, dans ta voix (skill `adorno-voice`), avec la skill de PR du repo si `repo-conf` en donne une (`pr_skill`) :
   - le titre au format Conventional Commit du changement principal ;
   - la description selon `process.md` § Pull requests : What / How / mermaid / Verification, `How to test` ouvert par
     les commandes réellement lancées et leur résultat, lien vers l'issue (`Fixes #n`). Aucune donnée réelle.
4. **Point de contrôle 2** si `gates` contient `open_pr` : montre titre, description et verdict de la porte, attends le
   « oui ».
5. `adorno-github/scripts/git-push owner/repo <branche>` (jamais un `git push` direct), puis `pr-open owner/repo <branche> "<titre>" <fichier> --draft` : brouillon tant que
   la CI n'est pas verte (`process.md`), relecteurs du registre sans l'auteur.
6. Rends l'URL de la PR et propose `workflow:pr:watch owner/repo#N`.
