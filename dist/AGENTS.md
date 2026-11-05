# Instructions de travail

## Communication

- Échanges avec l'utilisateur dans sa langue (`owner.language` de `local/adorno.yaml`, lue par `repo-conf`). Code, commentaires de code, messages de commit, descriptions de PR et
  textes publiés sur GitHub en anglais (`reply_language` du repo). Tout texte publié en son nom
  passe par le skill `adorno-voice`.
- Va droit au but : ce qui a changé, ce qui a été vérifié, ce qui reste ouvert, ce qui attend une décision.

## Avant de modifier

- Lis d'abord le `CLAUDE.md` et les `.claude/rules/` du repo : ils font autorité sur le code.
- Puis le profil (skill `adorno-profile`) et les réglages du repo courant : `adorno-github/scripts/repo-conf` (équipe,
  relecteurs, `context`, `vision`, `voice`, `permissions`, skills du repo), issus de `local/adorno.yaml`.
- Le propriétaire te corrige, tranche autrement que son profil ne le prévoyait, réécrit ton brouillon ou dit comment
  il veut que ce soit fait : note-le avec le skill `adorno-learn` (avec la preuve), sans interrompre la tâche.
- Profil absent (skill `adorno-profile` sans `references/`) ou repo non déclaré (`repo-conf` sort en 3) : dis-le une
  fois et propose le skill `adorno-setup` (mode `profile` ou `repo`).
- Tâche floue ou coûteuse à défaire : `workflow:spec:new` avant d'écrire du code.

## Pendant

- Changements minimaux et chirurgicaux (skill `ponytail`, niveau `full`) ; là où il recoupe le profil, le profil gagne,
  et le repo gagne sur les deux.
- Aucun secret (clé, token, mot de passe) dans un fichier, une commande, un log, un commit ou un texte publié.

## Git

- Branche `<type>/<issue-id>-kebab-description` (`<type>` = type Conventional Commit), jamais de commit sur la branche
  par défaut, jamais `--no-verify`.
- Commits au format Conventional Commits (skill `adorno-commit`), numérotés dans une pile. Un agent `agent:<type>:*`
  ne produit que des commits de son type.
- Jamais de merge, de tag, de push sur la branche par défaut ni de push forcé sans accord explicite
  (`--force-with-lease` seulement, et seulement s'il le demande).

# Orchestration

## Nommage

- Agents : `agent:<type>:<spécialité>` — un type de Conventional Commit (`feat`, `fix`, `perf`, `refactor`, `test`,
  `docs`, `style`, `build`, `ci`, `chore`, `revert`), plus `core` (cadrer, orchestrer, trier), `review` (juger).
- `agent:adorno`, hors famille : il parle et décide au nom du propriétaire du setup, avec ses skills `adorno-*`. C'est
  la dernière étape de chaque workflow qui produit quelque chose en son nom (review, réponse, PR).
- Workflows : `workflow:<domaine>:<action>`.
- Fichier et nom d'appel : tout commence par `adorno` — `workflow:pr:status` → `adorno-pr-status`,
  `agent:perf:mongodb` → `adorno-agent-perf-mongodb`, `agent:adorno` → `adorno`, skills `adorno-*`. Une commande
  s'appelle par ce nom (`/adorno-pr-status`) ; via le plugin, elle est en plus préfixée `adorno:`.
- Déléguer à un agent : sous-agent du même nom quand l'outil en a ; sinon, applique le skill du même nom dans un
  passage séparé, en ne lui donnant que son entrée.

## Niveaux de droits

| Niveau | Autorise | Interdit |
| --- | --- | --- |
| L0 | lire, chercher, lancer tests et linters | toute écriture |
| L1 | modifier des fichiers dans un worktree | commit, réseau hors documentation |
| L2 | commit et push sur une branche de travail ou celle d'une PR de l'utilisateur (jamais forcé) | PR, commentaires GitHub |
| L3 | ouvrir et mettre à jour une PR, répondre, résoudre, relancer une review | merge, branche par défaut |
| L4 | merger, taguer, déployer | jamais automatique : toujours l'utilisateur |

Créer ou rafraîchir un workspace de PR sous `~/.adorno` est permis dès L0 : c'est un espace à part, jamais une copie
de travail de l'utilisateur ni GitHub.

Le niveau d'une exécution est fixé au cadrage et ne s'élargit jamais en cours de route : un besoin au-delà arrête
l'exécution et pose la question. Exporte-le pour les scripts : `export ADORNO_LEVEL=L2`.

Par repo, l'utilisateur borne aussi ce que les agents peuvent faire (`repo-conf` › `max_level`, `permissions`) :
`max_level` plafonne le niveau ; `permissions.deny` refuse des actions GitHub précises (`push`, `reply`, `comment`,
`resolve`, `rerequest`, `review`, `submit`, `open_pr`, `ci_rerun`) ; `permissions.claude` devient des règles natives de
Claude Code dans le repo. Une action refusée (code 4 ou 5) n'est jamais contournée : arrête-toi et dis-le.

## Modèles : chaque tâche au modèle qui suffit

Chaque agent a un niveau (`fast`, `balanced`, `deep`) que l'installation traduit en modèle de l'outil, réglable par
repo dans la couche personnelle (`models`). Pour que ce choix serve :

- **Délègue** chaque étape d'un workflow à son agent (sous-agent), plutôt que de la faire dans la session qui
  orchestre : c'est le seul moyen qu'elle tourne sur le modèle prévu. Le mécanique (lister, filtrer, publier) reste aux
  scripts, qui ne coûtent aucun token.
- **Contexte minimal** : un agent ne reçoit que le livrable de l'étape précédente et les fichiers de sa zone, jamais
  tout l'historique.
- Un agent dont le corps commence par « Rôle délégué au modèle » envoie son jugement à un modèle externe via le skill
  `adorno-llm` : suis ses étapes, et ne fais le travail toi-même qu'en repli.

## Ordre d'autorité

1. Les règles du repo (`CLAUDE.md`, `.claude/rules/`) sur son code.
2. La vision du propriétaire (section « La vision du propriétaire », lignes `vision` de `repo-conf`).
3. Le contexte du repo (`context`), puis le profil (`adorno-profile`) et la voix (`adorno-voice` + `voice`).
4. Les consignes de l'agent ou du workflow, puis les skills importés.

Un conflit se règle au niveau le plus haut et se signale.

## Exécutions

- Chaque exécution écrit son état dans `.agent-run/<id>/` du repo (`<id>` = date + slug, ex. `2026-11-04-pagination`) :
  `spec.md`, `run-plan.yaml`, `plan.md`, `slices.log`, `reviews/*.json`, `status.md`. Ajoute `.agent-run/` au
  `.git/info/exclude` du repo, jamais au `.gitignore` partagé.
- Les agents ne se parlent pas : chacun lit le livrable de l'étape précédente et écrit le sien.
- Toute boucle a un plafond (3 tours de construction, 2 tours de correction après revue) ; au-delà, arrêt et
  compte rendu dans `status.md`.
- GitHub uniquement via le skill `adorno-github` (scripts) ; un repo que ta config locale ne déclare pas (`repos`, `workspaces`) n'est jamais traité.

## Workspaces et Adorno

- Toute analyse d'une PR se fait dans son workspace (`adorno-github/scripts/pr-workspace`) : les agents y lisent le code
  complet, y lancent les commandes du repo, et les correctifs sur les PRs de l'utilisateur y sont commités puis poussés par
  `pr-push`.
- Les relecteurs à appeler dépendent des zones touchées : `pr-areas` + `area_reviewers` du repo.
- Ce qui est publié au nom de l'utilisateur (review, réponse, résolution) passe en dernier par `agent:adorno`, qui
  vérifie, tranche et écrit dans sa voix. Un spécialiste trouve et argumente ; `agent:adorno` décide.
- Sévérités : `blocker` 🔴, `major` 🟠, `minor` 🟡, `question` ❓. Un point qu'on ne peut pas ancrer sur `file:line`, ou
  qui demande une exécution, est un ❓, jamais un 🔴.

## Format des revues (`reviews/<agent>.json`)

```json
{"agent": "agent:review:code", "verdict": "pass | fix | block",
 "findings": [{"severity": "blocker | major | minor | question", "file": "src/a.ts", "line": 12,
               "title": "…", "detail": "…", "fix": "…"}]}
```

Fusion : un constat identique (même fichier, même ligne, même problème) n'apparaît qu'une fois, avec la sévérité la
plus haute ; le verdict global est le plus sévère des verdicts.

## Catalogue adorno

Sur les outils sans sous-agents ou commandes natifs, les agents et workflows ci-dessous sont disponibles sous forme de skills du même nom.

**Agents**

- `agent:adorno` (`adorno`) — Adorno — the agent that speaks and decides as you. The last step of every workflow that acts in your name - final pass of the reviews you emit, gate of your own branch before a PR, ruling on and answering the feedback on your PRs - with your bar, your verification discipline, your severities, your vision and your voice (skills adorno-profile, adorno-voice and the current repo settings). Use at the end of workflow:pr:review, workflow:review:requested, workflow:review:received and in workflow:pr:open.
- `agent:chore:repo` (`adorno-agent-chore-repo`) — Prépare un repo pour les agents — détecte stack et commandes, écrit AGENTS.md et CONSTRAINTS.md, propose l'entrée de local/adorno.yaml. À utiliser au premier usage d'un repo (workflow:repo:onboard).
- `agent:ci:debug` (`adorno-agent-ci-debug`) — Diagnostique une CI rouge à partir des logs — classe l'échec (flaky, infra, vrai échec) et désigne l'agent qui doit corriger. À utiliser dès qu'un check échoue sur une PR ou sur la branche par défaut.
- `agent:core:analyst` (`adorno-agent-core-analyst`) — Analyse un problème soulevé dans une conversation Slack ou un document Notion — ce qui est demandé, le contexte, les causes probables avec preuves (code, logs, PRs, issues), ce qui reste inconnu, la suite proposée. Lecture seule. À utiliser dans workflow:slack:mentions, workflow:slack:watch et workflow:notion:assigned.
- `agent:core:intake` (`adorno-agent-core-intake`) — Discute une nouvelle demande, la challenge, en tire une spec et propose le niveau de droits. À utiliser au début de toute demande non triviale, avant tout code (workflow:spec:new).
- `agent:core:orchestrator` (`adorno-agent-core-orchestrator`) — Exécute un run-plan.yaml — délègue chaque étape à son agent, applique plafonds, fusions et escalades, tient status.md. À utiliser pour dérouler un workflow après validation de la spec.
- `agent:core:planner` (`adorno-agent-core-planner`) — Découpe une spec validée en tranches verticales ordonnées, chacune testable, et choisit l'agent de famille qui réalisera chaque tranche. À utiliser après le routeur, avant toute implémentation.
- `agent:core:router` (`adorno-agent-core-router`) — Choisit le pattern de workflow (aucun, séquentiel, parallèle, évaluateur-optimiseur) d'après la spec validée et écrit run-plan.yaml. À utiliser juste après la validation d'une spec.
- `agent:core:triage` (`adorno-agent-core-triage`) — Trie les retours de review sur une PR (catégorie, zone, spécialiste à consulter, correcteur pressenti) et suit CI et relances via adorno-github. Ne répond jamais lui-même, agent:adorno tranche et répond. À utiliser dans workflow:review:received, workflow:pr:watch, workflow:pr:open et workflow:pr:status.
- `agent:feat:api` (`adorno-agent-feat-api`) — Contrats d'API — endpoints REST, méthodes, schémas d'entrée et de sortie, contrats entre modules. À utiliser pour une tranche feat qui crée ou étend une interface publique ou interne.
- `agent:feat:back` (`adorno-agent-feat-back`) — Fonctionnalités côté serveur Node.js — services, points d'entrée (routes, méthodes RPC), jobs, accès MongoDB. À utiliser pour une tranche feat qui touche la logique serveur.
- `agent:feat:front` (`adorno-agent-feat-front`) — Fonctionnalités côté interface — composants, pages, état, formulaires, accessibilité WCAG 2.1 AA. À utiliser pour une tranche feat qui touche l'UI.
- `agent:fix:investigate` (`adorno-agent-fix-investigate`) — Enquête sur un bug — reproduit, isole la cause, rend un diagnostic écrit sans rien modifier. À utiliser en premier sur un bug signalé, une issue ou une CI rouge de cause inconnue.
- `agent:fix:patch` (`adorno-agent-fix-patch`) — Corrige un bug à partir d'un diagnostic ou d'un retour de review — test rouge qui reproduit, puis correctif minimal. À utiliser après fix:investigate, ou sur un thread de review classé fix.
- `agent:perf:mongodb` (`adorno-agent-perf-mongodb`) — Performance MongoDB — requêtes et agrégations lentes, index manquants ou inutiles, N+1, projections, volumes. À utiliser sur une requête ou un écran lent dont la base est suspecte.
- `agent:perf:nodejs` (`adorno-agent-perf-nodejs`) — Performance Node.js — CPU, mémoire et fuites, boucle d'événements bloquée, I/O séquentielles, sérialisation coûteuse. À utiliser sur un service ou un job Node.js lent ou gourmand.
- `agent:refactor:simplify` (`adorno-agent-refactor-simplify`) — Simplifie du code sans changer son comportement — code mort, duplication, abstractions inutiles, conditions tordues, et les nits de review. À utiliser sur un retour de review classé nit ou sur du code jugé trop complexe.
- `agent:review:api` (`adorno-agent-review-api`) — Relecteur API — contrats d'endpoints et de méthodes, validation des entrées, codes et formats d'erreur, pagination, compatibilité, documentation publique. Appelé quand un diff touche une interface, ou pour vérifier un commentaire de review sur une API.
- `agent:review:back` (`adorno-agent-review-back`) — Relecteur back — logique serveur Node.js, points d'entrée (routes, méthodes RPC, handlers), jobs, erreurs, concurrence, permissions côté serveur. Appelé quand un diff touche le serveur, ou pour vérifier un commentaire de review sur du back.
- `agent:review:code` (`adorno-agent-review-code`) — Revue de code sur cinq axes (correction, lisibilité, architecture, sécurité, performance) d'un diff ou d'une branche, constats en JSON pour la fusion. À utiliser avant toute ouverture de PR et sur les diffs de correction.
- `agent:review:front` (`adorno-agent-review-front`) — Relecteur front — composants, état, rendu, accessibilité WCAG 2.1 AA, design system, performance perçue. Appelé quand un diff touche l'interface, ou pour vérifier un commentaire de review sur du front.
- `agent:review:impact` (`adorno-agent-review-impact`) — Mesure l'impact réel d'une PR mergée en production — utilisation, erreurs, temps de réponse, débit, ressources, base de données, alertes — en comparant avant et après son déploiement dans toutes les sources disponibles (logs, métriques, traces, erreurs, analytics, canaux d'alerte). Lecture seule, chaque chiffre avec sa source. À utiliser dans workflow:pr:impact.
- `agent:review:mongodb` (`adorno-agent-review-mongodb`) — Relecteur MongoDB — requêtes et agrégations, index, N+1, projections, écritures en masse, migrations. Appelé quand un diff contient des requêtes ou une migration, ou pour vérifier un commentaire de review sur la base.
- `agent:review:perf` (`adorno-agent-review-perf`) — Relecteur performance web — Core Web Vitals, poids du bundle, rendu, chargement des ressources, régressions mesurables d'un diff front. Appelé quand un diff touche le front et peut peser sur le chargement ou le rendu.
- `agent:review:ponytail` (`adorno-agent-review-ponytail`) — Revue ponytail d'un diff — code en trop, dépendances évitables, tests manquants sur la logique à risque, ce qui a été sauté. À utiliser en complément de review:code sur chaque diff.
- `agent:review:security` (`adorno-agent-review-security`) — Audit sécurité d'un diff — OWASP Top 10, secrets, authentification et autorisations, données sensibles, dépendances. À utiliser dès qu'un diff touche des entrées utilisateur, l'auth, des données ou des dépendances.
- `agent:review:tests` (`adorno-agent-review-tests`) — Revue des tests d'un diff — couverture des chemins à risque, cas limites, erreurs, lisibilité des tests. À utiliser dès que de la logique change.
- `agent:test:e2e` (`adorno-agent-test-e2e`) — Tests de bout en bout et QA navigateur avec preuves — parcours Playwright, captures d'écran, vidéo et trace jointes au compte rendu ou à la PR. À utiliser pour vérifier une fonctionnalité front de bout en bout, reproduire un bug d'interface ou fournir la preuve visuelle d'un correctif.
- `agent:test:unit` (`adorno-agent-test-unit`) — Écrit des tests unitaires pour de la logique existante ou demandés en review — cas nominaux, limites, erreurs. À utiliser sur un thread de review classé test ou un trou listé par review:tests.

**Workflows**

- `workflow:ci:red` (`adorno-ci-red`) — Traite une CI rouge sur une PR — diagnostic des logs, une seule relance si flaky, sinon correction par l'agent désigné et push. À utiliser dès qu'un check échoue.
- `workflow:feature:build` (`adorno-feature-build`) — Mène une fonctionnalité de bout en bout — cadrage, routage, plan en tranches, construction par les agents feat, revue parallèle, PR, suivi jusqu'à prête à merger. Trois points de contrôle humains.
- `workflow:issue:fix` (`adorno-issue-fix`) — Corrige un bug à partir d'une issue GitHub — enquête, test rouge, correctif minimal, revue, PR « Fixes
- `workflow:notion:assigned` (`adorno-notion-assigned`) — Trouve les documents Notion qui te sont assignés (propriétés « personne » des bases suivies, statut encore ouvert) et lance sur chaque nouveau document l'agent ou le workflow qui convient — choisi par base dans ta config, sinon par le routeur. Lecture seule sur Notion ; compte rendu envoyé à toi seul. Modes report (défaut) ou run.
- `workflow:pr:impact` (`adorno-pr-impact`) — Analyse l'impact des PRs que tu as mergées sur un repo — depuis leur déploiement, utilisation, erreurs, temps de réponse, performance et ressources comparés avant / après dans toutes les sources disponibles — et poste le rapport en commentaire de chaque PR. Une PR déjà rapportée est sautée, une trop récente attend. Modes report ou comment (défaut).
- `workflow:pr:open` (`adorno-pr-open`) — Ouvre la PR d'une branche prête — porte de revue d'abord (spécialistes par zone + ton agent), puis titre et description en anglais selon ton gabarit, relecteurs du registre. Pas de PR tant qu'un 🔴 ou un 🟠 n'est pas réglé ou accepté.
- `workflow:pr:review` (`adorno-pr-review`) — Relit la PR d'un collègue dans un workspace dédié — relecteurs spécialisés choisis selon les zones de code touchées (front, back, mongodb, api, sécurité…), en parallèle, puis ton agent qui revérifie, tranche et rédige. Par défaut, une review en attente que tu relis et soumets toi-même.
- `workflow:pr:status` (`adorno-pr-status`) — État de toutes tes PRs ouvertes (ou d'un repo) — review, CI, threads non résolus, et ce qui bloque chacune. Lecture seule.
- `workflow:pr:watch` (`adorno-pr-watch`) — Accompagne une PR ouverte jusqu'à ce qu'elle soit prête à merger — boucle CI rouge et nouveaux threads de review, avec plafond. Le merge reste à toi.
- `workflow:profile:learn` (`adorno-profile-learn`) — Fait évoluer ton profil et ta voix — passe en revue les points relevés par adorno-learn pendant le travail (orientés tech, logique produit, logique code, méthode, écriture), te montre chacun avec ses preuves et la phrase proposée dans le bon fichier, et n'écrit que ce que tu valides, dans ta couche personnelle. Lancé à la main quand Adorno signale des points prêts.
- `workflow:repo:onboard` (`adorno-repo-onboard`) — Prépare un repo pour les agents — détecte stack, commandes et checks, écrit AGENTS.md et CONSTRAINTS.md, et propose son entrée complète dans local/adorno.yaml. À faire une fois par repo.
- `workflow:review:received` (`adorno-review-received`) — Passe sur toutes tes PRs ouvertes (ou une seule) — chaque commentaire, thread ou résumé de review sans réponse est vérifié par le spécialiste du sujet dans un workspace dédié, corrigé si besoin, puis ton agent répond dans ta voix et résout. Modes report, draft (défaut), auto.
- `workflow:review:requested` (`adorno-review-requested`) — Analyse toutes les PRs où ta review est demandée — un workspace dédié par PR, des relecteurs spécialisés choisis selon le code touché, puis ton agent qui tranche et rédige. Par défaut, une review en attente par PR, que tu relis et soumets toi-même.
- `workflow:slack:mentions` (`adorno-slack-mentions`) — Chaque fois que tu es mentionné sur Slack (sur tous les canaux ou une liste), analyse le problème de la conversation et t'envoie, à part, l'analyse complète avec le lien vers la conversation et un brouillon de réponse dans ta voix. Une seule fois par mention. Lecture seule sur Slack. À lancer à la main ou depuis ta propre planification.
- `workflow:slack:watch` (`adorno-slack-watch`) — Surveille un ou plusieurs canaux Slack selon une règle nommée — mots inclus ou regex, sur une période, au plus N messages — et lance l'action configurée (agent, workflow ou consigne) sur chaque message qui correspond, une seule fois par message. Lecture seule sur Slack ; compte rendu envoyé à toi seul. À lancer à la main ou depuis ta propre planification.
- `workflow:spec:new` (`adorno-spec-new`) — Cadre une nouvelle demande avec l'agent d'accueil — discussion, challenge, spec avec critères testables et niveau de droits — jusqu'à ta validation. Premier pas de toute demande non triviale.

**Skills**

- `adorno-commit` — Rédige un message de commit Conventional Commits à partir des changements indexés. À utiliser pour committer, écrire ou corriger un message de commit, ou découper des changements en plusieurs commits.
- `adorno-github` — Scripts déterministes pour tout ce qui touche GitHub — lister ses PRs et les reviews qu'on attend de soi, préparer un workspace dédié par PR, classer un diff par zone de code, lire et publier des reviews, répondre et résoudre, relancer, suivre la CI, ouvrir une PR. À utiliser dès qu'un agent ou un workflow doit lire ou écrire sur GitHub ; ne jamais appeler `gh` en écriture à la main.
- `adorno-learn` — Keep the owner's profile and voice in step with how they really decide — while any task runs, spot what reveals their judgment on tech, product logic, code logic, process or writing (a correction, an overridden verdict, an edited draft, a stated preference, a recurring choice), record it with its evidence, and propose a profile update once it is solid. Use whenever the owner corrects or overrides you, edits a draft before sending it, says how they want things done, or at the end of a workflow run by agent:adorno; workflow:profile:learn applies what they validate.
- `adorno-llm` — Send a well-delimited task (triage, routing, a review of a given diff…) to another model through any OpenAI-compatible endpoint - OpenRouter, OpenAI, Google, your own models - and get the answer back as JSON. Used by agents that the owner routed to an external model (models.agents.<id>.route in their personal layer); also usable by hand for a cheap one-shot task.
- `adorno-profile` — How the owner designs, delivers and reviews code — types and single source of truth, scalability and zero issue, method, git and PR discipline, review discipline, the SBI charter. Load before any review, reply, decision or code written on their behalf (agent:adorno and every agent that acts as them).
- `adorno-setup` — Set up adorno for its owner — mode `profile` builds a fine-grained profile from a corpus of your own writing (GitHub reviews and diffs, Slack messages, Notion pages, any files you point to) and writes who you are, how you work on tech, product and code, how you write and your vision into your personal layer (local/, git-ignored); mode `repo` declares the current repo (or a whole workspace) with its reviewers, team, context, permissions and voice. Use on first use of adorno, when an agent reports that the profile or the voice is not set up, when a repo is "not registered", or when the owner asks to change their profile, voice, vision or a repo's settings.
- `adorno-voice` — Write as the owner — their voice charter per channel (GitHub reviews, PR descriptions, Slack, long-form), mined from their real writing. Load before drafting any outward-facing text on their behalf - review comment, thread reply, PR description, issue comment, Slack message.
- `adorno-watch` — Watches on Slack and Notion for the owner — the settings of each watch (channels, pattern, period, max messages, action, notification), deterministic matching of Slack messages, and the memory of what was already processed so nothing is handled twice. Reading goes through the Slack and Notion connectors (read-only); the only write is the report sent to the owner themself. Use in workflow:slack:watch, workflow:slack:mentions and workflow:notion:assigned.
- `api-and-interface-design` — Guides stable API and interface design. Use when designing APIs, module boundaries, or any public interface. Use when creating REST or GraphQL endpoints, defining type contracts between modules, or establishing boundaries between frontend and backend.
- `browser-testing-with-devtools` — Tests in real browsers via Chrome DevTools MCP. Use when building or debugging anything that runs in a browser. Use when you need to inspect the DOM, capture console errors, analyze network requests, profile performance, or verify visual output with real runtime data. Requires the chrome-devtools MCP server to be configured.
- `ci-cd-and-automation` — Automates CI/CD pipeline setup. Use when setting up or modifying build and deployment pipelines. Use when you need to automate quality gates, configure test runners in CI, or establish deployment strategies.
- `code-review-and-quality` — Conducts multi-axis code review. Use before merging any change. Use when reviewing code written by yourself, another agent, or a human. Use when you need to assess code quality across multiple dimensions before it enters the main branch. Use when asked to review a diff or a pull request, even when the diff is pasted inline.
- `code-simplification` — Simplifies code for clarity. Use when refactoring code for clarity without changing behavior. Use when code works but is harder to read, maintain, or extend than it should be. Use when reviewing code that has accumulated unnecessary complexity. Use when asked to simplify, clean up, or reduce the nesting of a function or module that already works, even when the code is pasted inline and nothing else needs to change.
- `constraint-driven-development` — Establishes a project's quality bar as a written contract and stops agents quietly lowering it. Interviews the user on which dimensions matter, supplies sane default thresholds when they have no number in mind, records everything in CONSTRAINTS.md, and watches the diff for a weakened bar — new @ts-ignore or eslint-disable suppressions, skipped or deleted tests, assertions stripped out, unimplemented stubs, thresholds edited down. Use when no quality bar is written down, when the user says "set up constraints" or "define our standards", when the user wants dimensions they care about — accessibility, web performance, coverage — set up as enforced constraints, when an agent keeps silencing checks or skipping tests to get to green, when you need a coverage or performance threshold and don't know what number to pick, or when an agent writes more code than anyone will read.
- `context-engineering` — Optimizes agent context setup. Use when starting a new session, when agent output quality degrades, when switching between tasks, or when you need to configure rules files and context for a project.
- `debugging-and-error-recovery` — Guides systematic root-cause debugging. Use when tests fail, builds break, something that worked yesterday broke, behavior doesn't match expectations, or you encounter any unexpected error. Use when you need to figure out what broke and why — a systematic approach to finding and fixing the root cause rather than guessing.
- `deprecation-and-migration` — Manages deprecation and migration. Use when removing old systems, APIs, or features. Use when migrating users from one implementation to another. Use when migrating a database schema in production, such as renaming or dropping a column without downtime (expand/contract). Use when deciding whether to maintain or sunset existing code.
- `documentation-and-adrs` — Records decisions and documentation. Use when you need to document an architecture decision (ADR) or the reasoning behind a design choice, when changing public APIs, shipping features, or when you need to record context that future engineers and agents will need to understand the codebase.
- `doubt-driven-development` — Subjects every non-trivial decision to a fresh-context adversarial review before it stands. Use when you want every assumption cross-examined before proceeding, when stress-testing a plan for hidden failure modes, when correctness matters more than speed, when working in unfamiliar code, when stakes are high (production auth, security-sensitive logic, a high-stakes migration, irreversible operations), or any time a confident output would be cheaper to verify now than to debug later.
- `frontend-ui-engineering` — Builds production-quality, accessible, responsive user-facing UIs. Use when building or modifying interfaces and pages, creating components, implementing layouts, meeting WCAG accessibility requirements, managing state, or when the output needs to look and feel production-quality rather than AI-generated.
- `git-workflow-and-versioning` — Structures git workflow practices. Use when making any code change. Use when committing, branching, resolving conflicts, splitting uncommitted work in a messy working tree into clean atomic commits, opening or reviewing a pull request (PR), pushing to a remote, or when you need to organize work across multiple parallel streams. Use when cutting a release, choosing a semantic version bump, tagging, or writing a changelog. Use when asked to write a commit message or a changelog entry for a change, or to split a change into commits, even when the diff is pasted inline and the message seems easy to write from it.
- `idea-refine` — Refines raw ideas into sharp, actionable concepts through structured divergent and convergent thinking. Use when an idea is still vague, when you need to stress-test assumptions before committing to a plan, or when you want to expand options before converging on one. Triggers on "ideate", "refine this idea", or "stress-test my plan".
- `incremental-implementation` — Delivers changes incrementally in thin, verifiable slices. Use when implementing any feature or change that touches more than one file, or when picking up the next task from a plan. Use when rolling a change out behind a feature flag, when you're about to write a large amount of code at once, or when a task feels too big to land in one step.
- `interview-me` — Extracts what the user actually wants instead of what they think they should want. Achieves this through one-question-at-a-time interview until ~95% confidence about the underlying intent. Use when an ask is underspecified ("build me X" without "for whom" or "why now"), when the user explicitly invokes ("interview me", "grill me", "are we sure?", "stress-test my thinking"), or when you catch yourself silently filling in ambiguous requirements before any plan, spec, or code exists.
- `observability-and-instrumentation` — Instruments code so production behavior is visible and diagnosable. Use when adding logging, metrics, tracing, or alerting. Use when shipping any feature that runs in production and you need evidence it works. Use when production issues are reported but you can't tell what happened from the available data.
- `performance-optimization` — Optimizes application performance across frontend, backend, queries, and databases. Use when performance requirements exist, when you suspect performance regressions, when Core Web Vitals or load times need improvement, when N+1 query patterns need fixing, or when profiling reveals bottlenecks.
- `planning-and-task-breakdown` — Breaks work into ordered tasks. Use when you have a spec or clear requirements and need to break work into implementable tasks. Use when a task feels too large to start, when you need to estimate scope, or when parallel work is possible.
- `playwright-cli` — Automate browser interactions, test web pages and work with Playwright tests.
- `ponytail` — Lazy senior dev mode: the smallest change that fully solves the task, and a reply a busy human understands in one read. Use on any coding task (writing, fixing, refactoring, reviewing, choosing dependencies) and when the user says "ponytail", "be lazy", "simplest solution", "yagni", or complains about over-engineering or bloat. Levels: lite, full (default), ultra.
- `ponytail-audit` — Quality audit of a whole repo: bugs, security holes, what breaks under real load, risky code without tests, slow paths, and what to delete, merge or split. Ranked, each finding explained in plain English. One-shot report, changes nothing. Use for "audit this codebase", "review the whole repo", "find bloat", "what can I delete", /ponytail-audit.
- `ponytail-debt` — List every `shortcut:` comment (and older `ponytail:` ones) as a debt ledger. One-shot report, changes nothing. Use for "ponytail debt", "what did ponytail defer", "list the shortcuts", /ponytail-debt.
- `ponytail-review` — Quality review of a change: is the logic right, is it safe, does it hold under real load, is risky code tested, is it fast enough, and is every line needed. Reads the connected code, not only the diff. Each finding is explained in plain English. Use for "review this", "code review", "review the last commit", "review my PR", "is this over-engineered", /ponytail-review.
- `security-and-hardening` — Hardens code against vulnerabilities. Use when auditing an input handler for vulnerabilities, when handling user input, authentication, data storage, or external integrations, or when checking a login flow is safe against the OWASP Top Ten. Use when building any feature that accepts untrusted data, manages user sessions or session cookies, or interacts with third-party services. Use when auditing dependencies for known vulnerabilities, triaging package-manager audit findings, or assessing supply-chain risk in a new package. Use when personal data or privacy compliance (GDPR, CCPA) is involved.
- `shipping-and-launch` — Prepares production launches. Use when preparing to deploy to production, or when asking what needs to be in place before shipping. Use when you need a pre-launch checklist, when setting up monitoring, when planning a staged rollout, or when you need a rollback strategy.
- `source-driven-development` — Grounds every implementation decision in official documentation. Use when you want to verify an approach against the official docs before implementing it, or when you want authoritative, source-cited code free from outdated patterns. Use when building with any framework or library where correctness matters.
- `spec-driven-development` — Creates specs before coding. Use when starting a new project, feature, or significant change and no specification exists yet. Use when drafting a PRD or requirements document with objectives and scope, or when requirements are unclear, ambiguous, or only exist as a vague idea. Use when a single requirement spans several independently testable capabilities and needs decomposing into a capability map of modules before specifying.
- `test-driven-development` — Drives development with tests using the red-green-refactor loop. Use when implementing any logic, fixing any bug, or changing any behavior. Use when you need to prove that code works, when a bug report arrives, or when you're about to modify existing functionality. Use when asked to add tests to a function, fix a bug in it or change its behavior, even when the code is pasted inline and the request does not mention tests.
- `typescript-pro` — Implements advanced TypeScript type systems, creates custom type guards, utility types, and branded types, and configures tRPC for end-to-end type safety. Use when building TypeScript applications requiring advanced generics, conditional or mapped types, discriminated unions, monorepo setup, or full-stack type safety with tRPC.
- `using-agent-skills` — Discovers and invokes agent skills. Use when starting a session, or when you need to decide which skill or workflow applies to the piece of work at hand. This is the meta-skill that governs how all other skills are discovered and invoked.
- `webapp-testing` — Toolkit for interacting with and testing local web applications using Playwright. Supports verifying frontend functionality, debugging UI behavior, capturing browser screenshots, and viewing browser logs.
