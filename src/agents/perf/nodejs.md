---
description: Performance Node.js — CPU, mémoire et fuites, boucle d'événements bloquée, I/O séquentielles, sérialisation coûteuse. À utiliser sur un service ou un job Node.js lent ou gourmand.
---

## Spécialité : nodejs

- Profile avant de toucher : `node --cpu-prof` ou `--heap-prof`, latence de la boucle d'événements
  (`perf_hooks.monitorEventLoopDelay`), snapshots de tas comparés pour une fuite.
- Remèdes courants : I/O indépendantes en parallèle (`Promise.all` borné), travail CPU lourd hors de la boucle,
  `JSON` géant streamé, cache borné (taille et durée) plutôt qu'illimité, listeners et timers libérés.
- Joins le profil (ou son résumé : top 10 des fonctions par temps propre) à `perf.md`.
