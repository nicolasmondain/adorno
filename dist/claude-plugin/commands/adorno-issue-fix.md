---
description: Corrige un bug à partir d'une issue GitHub, d'un fil Slack, d'une page Notion, d'un prompt ou d'une spec validée — enquête, test rouge, correctif minimal, revue, PR (« Fixes
argument-hint: <owner/repo#N | liens Slack / Notion | description du bug avec owner/repo | dossier .agent-run>
---

Entrée : $ARGUMENTS

**Exécution** — dès le point de contrôle 1 passé (avant, tout est lecture) : `adorno-github/scripts/run-begin --workflow workflow:issue:fix --mode auto --level <niveau validé au point de contrôle 1> --repo owner/repo` ; garde `id` et `dir` (le dossier d'exécution). Appelé par un autre workflow qui a déjà ouvert la sienne : réutilise-la. Toujours, même après un échec : `run-end <id>`. Sans exécution ouverte, les scripts refusent toute écriture.

1. **Ce qui est rapporté**, dans un nouveau dossier `.agent-run/` :
   - une issue (`owner/repo#N` ou son lien) : `adorno-github/scripts/issue-fetch` → `issue.json` ;
   - des liens (fil Slack où le bug est signalé, page Notion) ou un fichier : `adorno-inputs/scripts/input-refs`, puis
     `source.md` (skill `adorno-inputs`) ; une issue citée dans les sources est lue aussi ;
   - un dossier `.agent-run` avec une `spec.md` validée : elle tient lieu de rapport ;
   - seulement une description : elle tient lieu de rapport, le repo doit y être nommé (ou le clone courant).
2. `agent:fix:investigate` reproduit à partir de ce rapport et écrit `diagnosis.md`. Pas de repro possible → réponse en brouillon (sur l'issue ou le fil d'origine, jamais postée) en
   anglais demandant ce qui manque, rendu à l'utilisateur ; arrêt.
3. **Point de contrôle 1** : diagnostic et niveau (L3 par défaut) validés par l'utilisateur.
4. Branche `fix/<n>-<slug>` (sans issue : `fix/<slug>`) depuis la base ; `agent:fix:patch` : test rouge, correctif, suite verte.
5. `agent:review:code` et `agent:review:tests` en parallèle ; un `blocker` → retour à `fix:patch` (deux tours).
6. `workflow:pr:open` avec `Fixes #N` dans la description s'il y a une issue (sinon les liens des sources, s'ils
   sont accessibles à l'équipe), puis `workflow:pr:watch`.
