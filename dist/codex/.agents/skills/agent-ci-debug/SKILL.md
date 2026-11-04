---
name: agent-ci-debug
description: Rôle agent:ci:debug — Diagnostique une CI rouge à partir des logs — classe l'échec (flaky, infra, vrai échec) et désigne l'agent qui doit corriger. À utiliser dès qu'un check échoue sur une PR ou sur la branche par défaut.
---

# Rôle : agent:ci:debug

Quand ce skill est invoqué, adopte le rôle ci-dessous pour la tâche en cours, puis reviens à ton comportement normal une fois le résultat rendu.

## Règles de la famille `ci` — configuration et scripts de CI

- Tes commits sont **uniquement** de type `ci` (`ci(<workflow>): …`) quand tu modifies la CI elle-même.
- Skill : `ci-cd-and-automation`. Actions épinglées par SHA, `permissions:` minimales, aucun secret affiché.
- Lecture de CI via `github-ops` (`ci-failed`, `ci-wait`) ; relance via `ci-rerun` (une seule fois par run).

## Spécialité : debug

1. `github-ops/scripts/ci-failed owner/repo#N` : lis la fin des logs en échec.
2. Classe :
   - **infra** : runner, quota, réseau, service externe indisponible, secret manquant → rien à corriger dans le code.
   - **flaky** : le même test passe sur le commit précédent sans changement lié, timeouts aléatoires, ordre →
     une seule relance (`ci-rerun`) ; s'il rechute, c'est un vrai échec ou un test à stabiliser.
   - **vrai échec** : le diff casse un test, le build, le lint ou le typecheck → reproduis en local.
3. Désigne le correcteur : `agent:fix:patch` (code), `agent:test:unit` (test faux), `agent:ci:*` (pipeline),
   `agent:refactor:simplify` (lint).

## Ce que tu rends

`ci.md` : check, classe, extrait de log décisif (dix lignes au plus), cause, agent désigné. Tu ne commites rien.
