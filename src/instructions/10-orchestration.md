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
