---
description: Mène une fonctionnalité de bout en bout — cadrage, routage, plan en tranches, construction par les agents feat, revue parallèle, PR, suivi jusqu'à prête à merger. Trois points de contrôle humains.
argument-hint: <la demande, des liens Slack / Notion / GitHub, un fichier de plan, ou le dossier .agent-run d'une spec validée> [--mode discuss|confirm]
---

Entrée : $ARGUMENTS

**Exécution** — avant toute chose : `adorno-github/scripts/run-begin --workflow workflow:feature:build --mode auto --level <niveau de la spec> --repo owner/repo` ; garde `id` et `dir` (le dossier d'exécution). Appelé par un autre workflow qui a déjà ouvert la sienne : réutilise-la. Toujours, même après un échec : `run-end <id>`. Sans exécution ouverte, les scripts refusent toute écriture.

1. **Cadrer** — sans spec validée, `workflow:spec:new $ARGUMENTS` d'abord (point de contrôle 1) : une idée se
   discute, un prompt clair ou des liens (fil Slack, page Notion, issue, fichier de plan) se confirment. Un plan déjà
   rédigé passe dans `spec.md` § Plan fourni, et `core:planner` le suit.
2. **Router** — `agent:core:router` lit `spec.md` et écrit `run-plan.yaml`. Si le routeur conclut qu'un seul
   agent suffit, le plan n'a qu'une étape : c'est normal.
3. **Planifier** — `agent:core:planner` écrit `plan.md` (tranches, agent `feat:*` de chaque tranche, tests
   d'acceptation).
4. **Construire et vérifier** — tu déroules toi-même `run-plan.yaml` (skill `adorno-run-plan` : un sous-agent ne peut pas en lancer d'autres) sur la branche `<type>/<issue-id>-<slug>` :
   tranches (boucle tests, trois tours ; QA `agent:test:e2e` avec captures et vidéo pour les tranches visibles),
   puis relecteurs en parallèle (boucle de correction, deux tours).
5. **Ouvrir** — `workflow:pr:open`, dont `agent:adorno` est la porte : il relit la branche comme toi, et la
   description de PR part dans ta voix (point de contrôle 2 si prévu).
6. **Suivre** — `workflow:pr:watch` jusqu'à ce que la PR soit prête (point de contrôle 3 : le merge, par l'utilisateur).

À chaque arrêt (plafond, droit manquant, escalade vers la spec) : `status.md` dit où et pourquoi, et la commande
pour reprendre.
