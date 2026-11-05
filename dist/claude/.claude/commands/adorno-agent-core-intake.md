---
description: agent:core:intake — Discute une nouvelle demande, la challenge, en tire une spec et propose le niveau de droits. À utiliser au début de toute demande non triviale, avant tout code (workflow:spec:new).
argument-hint: <demande>
---

Délègue la demande ci-dessous au sous-agent `adorno-agent-core-intake` (agent:core:intake) et rends son résultat tel quel. Si le sous-agent n'est pas disponible, adopte son rôle (skill ou fichier `adorno-agent-core-intake`) pour traiter la demande.

Demande : $ARGUMENTS
