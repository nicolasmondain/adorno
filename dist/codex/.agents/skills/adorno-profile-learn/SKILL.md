---
name: adorno-profile-learn
description: workflow:profile:learn — Fait évoluer ton profil et ta voix — passe en revue les points relevés par adorno-learn pendant le travail (orientés tech, logique produit, logique code, méthode, écriture), te montre chacun avec ses preuves et la phrase proposée dans le bon fichier, et n'écrit que ce que tu valides, dans ta couche personnelle. Lancé à la main quand Adorno signale des points prêts.
---

# workflow:profile:learn

Entrée : la demande de l'utilisateur. Suis les étapes dans l'ordre.

Entrée : la demande de l’utilisateur

1. **Lister** — `adorno-learn/scripts/learn-list --ready` (`--all` : tous les points en attente, y compris ceux vus une
   seule fois ; `--kind` filtre). Rien → dis-le, fin.
2. **Situer** — `adorno-setup/scripts/adorno-source` → la couche personnelle. Pour chaque point, lis le fichier visé
   (`local/src/skills/adorno-profile/references/<fichier>`, `…/adorno-voice/references/voice.md` ou
   `local/src/instructions/20-owner.md`) : le principe y est-il déjà, en partie, ou contredit ?
3. **Proposer**, un point à la fois :
   - ce qui a été observé, combien de fois, avec les liens ;
   - le changement exact : la phrase ajoutée ou remplacée, dans quelle section (un diff) ; une contradiction avec
     le profil actuel est montrée comme telle, avec les deux versions ;
   - le choix : **accepter**, **reformuler** (tu dictes, on montre le nouveau diff), **plus tard**, **rejeter**.
4. **Écrire** ce qui est accepté, dans le fichier de la couche personnelle seulement (jamais dans un fichier suivi du
   dépôt adorno), puis `learn-decide <clé> accepted` ; `rejected` ou `later` sinon. Un principe qui change ta façon
   de travailler au quotidien remonte aussi, en une ligne, dans `20-owner.md` si tu le veux.
5. **Appliquer** — `<source>/bin/kit check`, puis `<source>/bin/kit install --global` (et les repos installés à
   part, s'il y en a). Compte rendu : ce qui a changé, fichier par fichier.
