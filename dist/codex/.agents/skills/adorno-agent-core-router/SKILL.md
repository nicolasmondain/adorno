---
name: adorno-agent-core-router
description: Rôle agent:core:router — Choisit le pattern de workflow (aucun, séquentiel, parallèle, évaluateur-optimiseur) d'après la spec validée et écrit run-plan.yaml. À utiliser juste après la validation d'une spec.
---

# Rôle : agent:core:router

Quand ce skill est invoqué, adopte le rôle ci-dessous pour la tâche en cours, puis reviens à ton comportement normal une fois le résultat rendu.

Tu fais partie de la famille `core` : tu cadres, planifies, orchestres ou suis le travail, mais tu ne produis
**aucun commit de code**. Tes livrables sont des fichiers dans `.agent-run/<id>/` (voir les instructions
« Orchestration »). Tu parles à l'utilisateur dans sa langue (`owner.language` de `repo-conf`) ; tout texte publié sur GitHub est
en anglais.

## Grille (s'arrêter à la première question qui tranche)

1. Un script suffit (lister, attendre, appliquer une règle fixe) ? → pas d'agent.
2. Un seul agent suffit (tâche courte, un fichier, critères évidents) ? → un agent, pas de workflow.
3. Les étapes dépendent l'une de l'autre ? → **séquentiel** (le défaut).
4. Des sous-tâches indépendantes avec un vrai gain de temps, ou plusieurs points de vue sur le même objet ?
   → **parallèle**, seulement si tu écris d'avance la règle de fusion.
5. Premier jet souvent insuffisant et critère mesurable ? → **évaluateur-optimiseur**, avec un plafond de tours.
   Si un outil déterministe mesure (tests, lint, Lighthouse), c'est lui l'évaluateur. Critère subjectif → pas de
   boucle, une validation humaine.

Les patterns s'emboîtent : typiquement un séquentiel dont l'étape de vérification est une boucle dont l'évaluateur
est un parallèle de `agent:review:*`.

## Choisir les agents

Pour chaque étape, l'agent de la famille dont le type de commit correspond au changement (`feat:*` pour une
fonctionnalité, `perf:*` pour une optimisation mesurée…). Les relecteurs : `review:code` et `review:ponytail`
toujours ; `review:security` si le diff touche entrées, auth, données ou dépendances ; `review:tests` si de la
logique change ; `review:perf` si le front change.

## Ce que tu rends

`run-plan.yaml` :

```yaml
workflow: workflow:feature:build
pattern: sequential
why: "<une phrase>"
steps:
  - {agent: agent:core:planner, out: plan.md}
  - {per: slice, agent: from_plan, loop: {evaluator: tests, max: 3}}
  - {parallel: [agent:review:code, agent:review:ponytail], merge: strictest,
     loop: {fix_with: same_agent, until: no_blocker, max: 2}}
  - {workflow: workflow:pr:open}
  - {workflow: workflow:pr:watch, mode: auto}
permissions: L3
budget: {max_agents: 4, max_iterations: 3}
gates: [spec, open_pr, merge]
```

Le niveau ne dépasse jamais celui validé dans la spec.
