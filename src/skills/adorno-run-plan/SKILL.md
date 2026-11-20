---
name: adorno-run-plan
description: How the main session executes a run-plan.yaml written by agent:core:router — one delegation per step, capped loops, parallel reviews merged by script, escalations, status.md. Use in workflow:feature:build (and any workflow that unrolls a plan) (a subagent cannot start others, the session does it).
---

# Executing a run plan

Only the main session delegates: agents never start agents. You hold the plan and the state; each agent gets only
its input.

1. Read `run-plan.yaml` and `spec.md`. The level is the one of the run opened by the workflow (`run-begin`); never
   widen it.
2. For each step, delegate to the agent named, passing only its input (the previous deliverable and the spec) and the `skills` of its areas and the `ponytail` level (`pr-areas`), never
   the whole history. `parallel` steps: start them in the same turn. Before each step and each loop round,
   `adorno-github/scripts/run-budget <id>`: exit 7 → stop (step 5).
3. **Loops**: `loop.evaluator: tests` = the repo's `test`/`lint` commands; send the failing output back to the agent,
   up to `max`. `fix_with: same_agent` = the agent that wrote the slice fixes the review findings. A round that
   fails again climbs, within `max` (the same rule for every capped loop of a workflow):
   - first round: the agent on its own tier;
   - middle rounds (from `max: 3`): the same agent with `effort: high`;
   - last round: one tier up, `fast` → `balanced` → `deep` → `frontier` (in Claude Code the Agent tool's `model`:
     haiku → sonnet → opus → fable, the only values it takes: a tier mapped to another model id does not climb);
     an agent already on `frontier` stays there with `effort: high`; an agent sent to an external route
     (`models.agents.<id>.route`) does not climb.
   Say in `status.md` which round ran on which model.
4. **Reviews**: each reviewer writes `reviews/<agent>.json`; merge with `adorno-github/scripts/review-merge reviews/`
   and read only the merged result. A `block` stops the loop and goes up.
5. **Escalations**: a reviewer disputes the spec, or a test can only pass by changing the spec → back to
   `agent:core:intake`, not to the builder. Cap reached, missing right, unregistered repo → stop. Budget reached
   (`run-budget` exit 7) → launch nothing more, `status.md` opens with `Stopped: budget`, `run-end <id> stopped`
   (orchestration › Runs).
6. After each step, update `status.md` in the run folder: step, result, rounds used, next action, and the `Ponytail`
   note of an agent's deliverable (lite: the smaller option, ultra: the pushback). At the end,
   `run-end <id> --status <run folder>/status.md` adds the run's cost line there.
7. Mark the run's journal as you go, so its replay shows the plan: `adorno-github/scripts/run-mark step-begin <index>
   <name>` before a step and `run-mark step-end <index> <name>` after it (index: the step's place in `steps:`, from
   1), `run-mark round <n> <max> "<why>"` when a loop round starts.

Deliverable: `status.md` up to date and a five-line report — what is done, what was verified, where it stopped and
why, what waits for the owner, and the cost line `run-end` printed.
