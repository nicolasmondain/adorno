# Consignes pour les agents qui travaillent sur ce dépôt

adorno est un setup d'agents portable et réutilisable. On y écrit des agents, des workflows et des skills dans un format neutre ;
`bin/kit` les traduit pour chaque outil (Claude Code, Codex, Gemini CLI…).

## Où mettre quoi

| Je veux… | Fichier |
| --- | --- |
| une consigne valable dans tous les projets | `src/instructions/NN-sujet.md` (concaténés par ordre de nom) |
| un agent | `src/agents/<type>/<spécialité>.md` → `agent:<type>:<spécialité>` ; `<type>` = un type Conventional Commit, ou `core`, `review` ; hors famille : `src/agents/adorno.md` → `agent:adorno` |
| une règle commune à une famille | `src/agents/<type>/_family.md` (fusionné avant chaque spécialité ; `{{specialty}}` et `{{family}}` y sont remplacés) |
| un workflow | `src/workflows/<domaine>/<action>.md` → `workflow:<domaine>:<action>` ; `{{args}}` = l'entrée |
| un savoir-faire à la demande | `src/skills/<nom>/SKILL.md` (+ `scripts/`, `references/`) |
| un accès GitHub | un script dans `src/skills/adorno-github/scripts/` + son test dans `tests/adorno-github.test.sh` |
| une surveillance Slack ou Notion | un workflow `src/workflows/slack/…` ou `src/workflows/notion/…` ; le déterministe dans `src/skills/adorno-watch/scripts/` + `tests/adorno-watch.test.sh` ; lecture via les connecteurs, seule écriture : le compte rendu à soi-même |
| le modèle d'un agent | son niveau `model:` (`fast`, `balanced`, `deep`) ; `delegable: true` s'il peut juger sur des entrées rassemblées d'avance (route externe) ; le choix réel par outil et par repo est dans `local/` › `models` |
| un repo, un workspace, des droits, une voix, une vision | `local/` (ignoré par git ; modèle : `local.example/`) — jamais dans le dépôt |
| un réglage public par défaut | `repos.yaml` (+ sa validation dans `bin/kit` › `validate_registry`) |
| une règle de résolution des réglages | `src/skills/adorno-github/scripts/resolve.jq` (partagé par les scripts et `kit conf`) + ses tests |
| du contenu d'un autre dépôt | `imports:` dans `kit.yaml`, puis `bin/kit import` |
| modifier un élément importé | un fichier local avec `extends: <import>/<nom>` (jamais d'édition dans `vendor/`) |

`bin/kit new agent perf:redis` (ou `new workflow ci:flaky`, `new skill <nom>`) crée un fichier de départ.

## Règles

- **Ce dépôt est statique, enrichi à la main** : rien n'y est committé depuis un autre projet, ni par un agent. Ce qui
  concerne une personne ou un repo réel (identité, relecteurs, équipe, contexte, droits, voix, vision, profil) va dans
  `local/`, ignoré par git ; le public n'a que des modèles (`local.example/`). Seuls le skill `adorno-setup` et
  `workflow:profile:learn` écrivent dans `local/`, et seulement ce que le propriétaire a validé.

- Un agent d'une famille ne produit que des commits de son type ; `core` et `review` ne committent pas.
- La `description` dit ce que fait l'élément et quand l'utiliser : c'est elle qui le fait choisir.
- `tools` : capacités neutres `read`, `write`, `edit`, `search`, `shell`, `web`, `agent`. `model` : `inherit`,
  `fast`, `balanced`, `deep`. Un réglage propre à un outil va sous `targets: { claude: { … } }`.
- `uses:` d'un workflow : identifiants logiques (`agent:fix:patch`, `workflow:ci:red`, `adorno-github`), vérifiés par
  `kit check`.
- Scripts : bash compatible macOS 3.2, `set -euo pipefail`, JSON sur stdout, codes de sortie de `adorno-github/SKILL.md`,
  écriture GitHub seulement après `require_level`, mode `ADORNO_DRY_RUN`.
- Ne modifie jamais `dist/` ni `vendor/` à la main.

## Après chaque modification

```sh
bin/kit check && bin/kit build && for t in tests/*.test.sh; do $t || break; done
```

Committe `src/`, `dist/`, `vendor/`, `kit.yaml`, `kit.lock` et `repos.yaml` ensemble : la CI refuse un `dist/`
périmé. Message au format Conventional Commits, ex. `feat(agents): add perf:redis`.
