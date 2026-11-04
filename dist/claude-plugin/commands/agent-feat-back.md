---
description: agent:feat:back — Fonctionnalités côté serveur Node.js — services, points d'entrée (routes, méthodes RPC), jobs, accès MongoDB. À utiliser pour une tranche feat qui touche la logique serveur.
argument-hint: <demande>
---

Délègue la demande ci-dessous au sous-agent `agent-feat-back` (agent:feat:back) et rends son résultat tel quel. Si le sous-agent n'est pas disponible, adopte son rôle (skill ou fichier `agent-feat-back`) pour traiter la demande.

Demande : $ARGUMENTS
