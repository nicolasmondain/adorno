---
description: Analyse toutes les PRs où ta review est demandée — un workspace dédié par PR, des relecteurs spécialisés choisis selon le code touché, puis ton agent qui tranche et rédige. Par défaut, une review en attente par PR, que tu relis et soumets toi-même.
args: "[owner/repo] [--mode report|pending|auto] [--include-reviewed] [--direct-only]"
uses:
  skills: [github-ops]
  workflows: [workflow:pr:review]
---

Entrée : {{args}}

Modes de `workflow:pr:review` : `report` (rien sur GitHub), `pending` (défaut : une review en attente, visible de toi
seul), `auto` (soumise, jamais d'`APPROVE` si `allow_approve` est faux).

1. **Lister** — `github-ops/scripts/pr-review-requested [owner/repo]`. Écarte et cite dans le compte rendu :
   - les repos non enregistrés (`registered: false`) ;
   - les brouillons (`isDraft`) ;
   - les PRs déjà relues à leur commit actuel (`reviewedHead`), sauf avec `--include-reviewed` ;
   - celles où tu as déjà une review en attente (`pendingReview`) : elle est à toi, on n'y touche pas ;
   - les demandes faites à une équipe seulement, avec `--direct-only`.
2. **Annoncer** — montre la liste retenue (repo, PR, auteur, taille) avant de commencer. Plus de 10 PRs ou une PR de
   plus de 1 500 lignes : demande confirmation, l'analyse coûte cher.
3. **Analyser** — `workflow:pr:review owner/repo#N --mode <mode>` pour chaque PR. Les PRs sont indépendantes :
   traite-les **en parallèle**, par lots de `max_parallel` (3 par défaut). Chaque PR a son propre
   workspace et son propre dossier `.agent-run`, rien n'est partagé.
4. **Rendre compte** — un tableau trié par urgence : PR (lien), auteur, zones touchées, relecteurs appelés, verdict,
   nombre de points (🔴 / 🟠 / 🟡 / ❓), et le lien de la review en attente (ou soumise en `auto`). En `report`, la commande
   pour créer la review en attente : `github-ops/scripts/pr-review-submit owner/repo#N <review-final.json>`.

Les workspaces restent en place pour un second passage ; `pr-workspace --clean` supprime ceux des PRs fermées.
