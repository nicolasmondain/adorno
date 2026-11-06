# Instructions de travail

## Communication

- Échanges avec l'utilisateur dans sa langue (`owner.language` de `local/adorno.yaml`, lue par `repo-conf`). Code, commentaires de code, messages de commit, descriptions de PR et
  textes publiés sur GitHub en anglais (`reply_language` du repo). Tout texte publié en son nom
  passe par le skill `adorno-voice`.
- Va droit au but : ce qui a changé, ce qui a été vérifié, ce qui reste ouvert, ce qui attend une décision.

## Avant de modifier

- Lis d'abord le `CLAUDE.md` et les `.claude/rules/` du repo : ils font autorité sur le code (sauf `.claude/rules/adorno.md`, qui est ce texte-ci, posé par `bin/kit` quand le repo suit déjà son `CLAUDE.md`).
- Puis le profil (skill `adorno-profile`) et les réglages du repo courant : `adorno-github/scripts/repo-conf` (équipe,
  relecteurs, `context`, `vision`, `voice`, `permissions`, skills du repo), issus de `local/adorno.yaml`.
- Le propriétaire te corrige, tranche autrement que son profil ne le prévoyait, réécrit ton brouillon ou dit comment
  il veut que ce soit fait : note-le avec le skill `adorno-learn` (avec la preuve), sans interrompre la tâche.
- Profil absent (skill `adorno-profile` sans `references/`) ou repo non déclaré (`repo-conf` sort en 3) : dis-le une
  fois et propose le skill `adorno-setup` (mode `profile` ou `repo`).
- Tâche floue ou coûteuse à défaire : `workflow:spec:new` avant d'écrire du code.

## Pendant

- Changements minimaux et chirurgicaux (skill `ponytail`, au niveau `ponytail` du repo, `full` par défaut) ; là où il recoupe le profil, le profil gagne,
  et le repo gagne sur les deux.
- Aucun secret (clé, token, mot de passe) dans un fichier, une commande, un log, un commit ou un texte publié.

## Git

- Branche `<type>/<issue-id>-kebab-description` (`<type>` = type Conventional Commit), jamais de commit sur la branche
  par défaut, jamais `--no-verify`.
- Commits au format Conventional Commits (skill `adorno-commit`), numérotés dans une pile. Un agent `agent:<type>:*`
  ne produit que des commits de son type.
- Jamais de merge, de tag, de push sur la branche par défaut ni de push forcé sans accord explicite
  (`--force-with-lease` seulement, et seulement s'il le demande).
