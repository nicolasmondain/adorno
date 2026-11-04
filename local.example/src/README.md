# local/src — ton src/ privé

Même arborescence que `src/` ; chaque fichier ici remplace (ou ajoute) le fichier public du même chemin à l'install.
Le profil, la voix et le résumé n'existent **que** ici : le dépôt public n'en livre aucun. Les fichiers de ce modèle
sont des points de départ ; le skill `adorno-setup` (mode `profile`) t'aide à écrire les tiens.

| Pour… | Écris |
| --- | --- |
| ton profil (principes, méthode, identité) | `skills/adorno-profile/references/{personality,engineering-types,engineering-scale,process}.md` |
| ta manière d'écrire | `skills/adorno-voice/references/voice.md` |
| ton résumé toujours actif | `instructions/20-owner.md` |
| une consigne privée de plus | `instructions/NN-sujet.md` |
| un agent, un workflow ou un skill privé | `agents/<type>/<spécialité>.md`, `workflows/<domaine>/<action>.md`, `skills/<nom>/SKILL.md` |

Un dossier `skills/<nom>/` sans `SKILL.md` se pose sur le skill public du même nom, fichier par fichier ; avec un
`SKILL.md`, il en remplace aussi la description et le corps.
