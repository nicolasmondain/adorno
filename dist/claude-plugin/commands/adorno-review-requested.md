---
description: Analyse toutes les PRs où ta review est demandée — un workspace dédié par PR, des relecteurs spécialisés choisis selon le code touché, puis ton agent qui tranche et rédige. Par défaut, une review en attente par PR, que tu relis et soumets toi-même.
argument-hint: '[owner/repo] [--mode report|pending|auto] [--include-reviewed] [--direct-only]'
model: sonnet
---

Entrée : $ARGUMENTS

**Exécution** — avant toute écriture : `adorno-github/scripts/run-begin --workflow workflow:review:requested --mode <mode> --level L3 --repo owner/repo [--repo …]` — une fois la liste des PRs connue, un `--repo` par repo à traiter (une exécution ne vaut que pour les repos qu'elle nomme) (`--deny submit` en mode `pending`) ; garde `id` et `dir` (le dossier d'exécution). Appelé par un autre workflow qui a déjà ouvert la sienne : réutilise-la. Toujours, même après un échec : `run-end <id>`. Sans exécution ouverte, les scripts refusent toute écriture.

Modes de `workflow:pr:review` : `report` (rien sur GitHub), `pending` (défaut : une review en attente, visible de toi
seul), `auto` (soumise, jamais d'`APPROVE` si `allow_approve` est faux).

1. **Lister** — `adorno-github/scripts/pr-review-requested [owner/repo]`. Écarte et cite dans le compte rendu :
   - les repos non enregistrés (`registered: false`) ;
   - les brouillons (`isDraft`) ;
   - les PRs déjà relues à leur commit actuel (`reviewedHead`), sauf avec `--include-reviewed` ;
   - celles où tu as déjà une review en attente (`pendingReview`) : elle est à toi, on n'y touche pas ;
   - les demandes faites à une équipe seulement, avec `--direct-only`.
2. **Annoncer** — montre la liste retenue (repo, PR, auteur, taille) avant de commencer. Plus de 10 PRs ou une PR de
   plus de 1 500 lignes : demande confirmation, l'analyse coûte cher.
3. **Analyser** — pour chaque PR, tu déroules toi-même les étapes de `workflow:pr:review owner/repo#N --mode <mode>`
   dans l'exécution déjà ouverte (un sous-agent ne peut pas en lancer d'autres). Les PRs sont indépendantes : par lots
   de `max_parallel` (3 par défaut), lance dans le même tour les spécialistes de toutes les PRs du lot. Chaque PR a son
   propre workspace et son dossier `reviews/` ; de chaque PR, ne garde en contexte que son `review.json` fusionné
   (`review-merge`) et la passe d'Adorno, jamais les avis bruts.
4. **Rendre compte** — un tableau trié par urgence : PR (lien), auteur, zones touchées, relecteurs appelés, verdict,
   nombre de points (🔴 / 🟠 / 🟡 / ❓), et le lien de la review en attente (ou soumise en `auto`). En `report`, la commande
   pour créer la review en attente : `adorno-github/scripts/pr-review-submit owner/repo#N <review-final.json>`.

Les workspaces restent en place pour un second passage ; `pr-workspace --clean` supprime ceux des PRs fermées.
