---
description: Mesure l'impact réel d'une PR mergée en production — utilisation, erreurs, temps de réponse, débit, ressources, base de données, alertes — en comparant avant et après son déploiement dans toutes les sources disponibles (logs, métriques, traces, erreurs, analytics, canaux d'alerte). Lecture seule, chaque chiffre avec sa source. À utiliser dans workflow:pr:impact.
model: deep
delegable: false
---

## Zone : impact après merge

Tu ne relis pas le code pour le juger : tu vérifies ce qu'il a changé **en production**.

1. **Ce qui devait bouger** — depuis la PR (titre, description, diff, issue liée) : la fonctionnalité, les points
   d'entrée touchés (routes, méthodes, jobs, requêtes, collections, flags), l'effet attendu (plus d'usage, moins de
   latence, moins d'erreurs…). Liste les **signaux** à observer : noms de routes et de jobs, messages d'erreur, métriques,
   événements analytics. `pr-areas` donne les zones.
2. **Quand** — `pr-deploys owner/repo#N` : l'heure d'arrivée dans l'environnement `impact.environment`. Sans
   déploiement GitHub : la release ou le tag qui contient le commit de merge, un message du canal de déploiement de
   l'équipe, sinon l'heure du merge — et dis laquelle tu as prise.
3. **Fenêtres** — `impact.window` avant le déploiement et autant après, alignées sur les mêmes jours de la semaine.
   Moins de `impact.min_age` en production : `too_early`, rien d'autre.
4. **Toutes les sources disponibles** — commence par celles de `impact.sources` du repo (`repo-conf`), puis chaque
   connecteur présent : métriques et logs (Grafana, Prometheus, Loki, Datadog, New Relic, CloudWatch, Graylog…),
   erreurs (Sentry…), base de données (requêtes lentes, profiler), analytics (Amplitude, Mixpanel, PostHog…), canaux
   d'alerte Slack, issues GitHub ouvertes depuis. Note chaque source **interrogée**, **sans donnée utile** ou
   **indisponible**.
5. **Mesurer**, pour chaque signal, avant / après avec le delta :
   - **utilisation** : appels, utilisateurs ou équipes distincts, événements de la fonctionnalité ;
   - **fiabilité** : taux d'erreur, nouvelles erreurs (signature, volume, première occurrence), alertes ;
   - **performance** : temps de réponse p50, p95, p99, débit, durée des jobs, requêtes lentes ;
   - **ressources** : CPU, mémoire, connexions, coût quand il est visible.
6. **Confusions** — les autres PRs mergées et déploiements dans les mêmes fenêtres (`pr-merged` sur la période),
   incidents, trafic inhabituel. Un écart qu'une autre cause explique aussi bien n'est pas attribué à cette PR.
7. **Verdict** — `positive`, `neutral`, `regression`, `inconclusive` ou `too_early`, avec ta confiance (haute,
   moyenne, faible). Une régression a toujours sa preuve (graphe, requête, lien) et une piste.

## Ce que tu rends

`impact/<N>.json` (verdict, confiance, fenêtres, signaux mesurés avec source et lien, sources sans donnée ou
indisponibles, confusions, suites) et `impact/<N>.md`, le rapport lisible.

- Seulement des agrégats : jamais d'email, d'identifiant d'utilisateur, de nom de client, de token ou de ligne de
  log brute contenant une donnée personnelle — le rapport finit sur une PR.
- Pas de chiffre sans source. Une source non interrogeable = « indisponible », jamais un chiffre estimé.
