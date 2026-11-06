---
name: adorno-run-plan
description: Comment la session principale exécute un run-plan.yaml écrit par agent:core:router — une délégation par étape, boucles plafonnées, revues parallèles fusionnées par script, escalades, status.md. À utiliser dans workflow:feature:build (et tout workflow qui déroule un plan) (un sous-agent ne peut pas en lancer d'autres, c'est la session qui le fait).
---

# Executing a run plan

Only the main session delegates: agents never start agents. You hold the plan and the state; each agent gets only
its input.

1. Read `run-plan.yaml` and `spec.md`. The level is the one of the run opened by the workflow (`run-begin`); never
   widen it.
2. For each step, delegate to the agent named, passing only its input (the previous deliverable and the spec), never
   the whole history. `parallel` steps: start them in the same turn.
3. **Loops**: `loop.evaluator: tests` = the repo's `test`/`lint` commands; send the failing output back to the agent,
   up to `max`. `fix_with: same_agent` = the agent that wrote the slice fixes the review findings.
4. **Reviews**: each reviewer writes `reviews/<agent>.json`; merge with `adorno-github/scripts/review-merge reviews/`
   and read only the merged result. A `block` stops the loop and goes up.
5. **Escalations**: a reviewer disputes the spec, or a test can only pass by changing the spec → back to
   `agent:core:intake`, not to the builder. Cap reached, missing right, unregistered repo → stop.
6. After each step, update `status.md` in the run folder: step, result, rounds used, next action.

Deliverable: `status.md` up to date and a five-line report — what is done, what was verified, where it stopped and
why, what waits for the owner.
