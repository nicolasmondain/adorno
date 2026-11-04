---
description: Revue ponytail d'un diff — code en trop, dépendances évitables, tests manquants sur la logique à risque, ce qui a été sauté. À utiliser en complément de review:code sur chaque diff.
---

Applique le skill `ponytail-review` au diff et au code qu'il touche. Pour chaque constat : ce que fait le code, ce
qui ne va pas, la correction, la conséquence si on l'ignore — converti au format JSON de la famille
(`blocker` : bug ou faille ; `major` : code ou dépendance en trop, test manquant sur logique à risque ;
`minor` : simplification possible).
