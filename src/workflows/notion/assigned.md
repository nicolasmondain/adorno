---
description: Find the Notion documents assigned to you ("person" properties of the watched databases, status still open) and launch on each new document the agent or workflow that fits — chosen per database in your config, otherwise by the router. Read-only on Notion; report sent to you alone. Modes report (default) or run.
args: "[--mode report|run] [--since 30d] [--dry-run] [--all]"
uses:
  skills: [adorno-watch, adorno-github]
  agents: [agent:core:analyst, agent:core:router, agent:adorno]
  workflows: [workflow:spec:new, workflow:issue:fix]
model: balanced
---

Input: {{args}}. Settings in your personal layer (`local/adorno.yaml` › `notion.assigned`):

```yaml
notion:
  assigned:
    properties: ["Assignee", "Owner"]        # "person" properties that count as an assignment
    databases: ["https://www.notion.so/…"]   # watched databases; empty = search the whole workspace
    exclude_status: ["Done", "Archived"]     # statuses ignored
    since: 30d                               # documents modified since
    max_messages: 20                         # documents processed at most per run
    agents:                                  # what to launch per database (name or link); otherwise the router decides
      "Roadmap": workflow:spec:new
      "Bugs": workflow:issue:fix
    mode: report                             # report: analysis and plan · run: launches the agent or workflow
    level: L0                                # permissions in run mode
    notify: dm
```

Run folder: `~/.adorno/runs/notion-assigned-<date>/`.

1. **Settings** — `adorno-watch/scripts/watch-conf notion-assigned` (exit code 3 → skill `adorno-setup`); `--mode` and
   `--since` override them. You in Notion: the connector (your user).
2. **Find** — with the Notion connector: in each database of `databases`, the pages where a property from
   `properties` contains you, status outside `exclude_status`, modified since `since`; without a database, a search
   for the pages assigned to you. `max_messages` at most, most recent first. Normalize into `docs.json`:
   `{id, title, url, database, status, assigned_by, last_edited}`.
3. **Keep only what is new** — `watch-seen filter notion-assigned docs.json` (`--all`: everything). A document already
   processed but modified since only comes back if its status changed. Nothing → end. `--dry-run`: the list, and end.
4. **Read and choose** — for each document: its full content, properties and comments. The action: `agents` from the
   config for its database, otherwise `agent:core:router` (a spec to scope → `workflow:spec:new`, a bug →
   `workflow:issue:fix`, a question → `agent:core:analyst`…).
5. **Act** —
   - `report` (default): `agent:core:analyst` returns the analysis and what the chosen action would do (plan, target
     repo, permissions needed), without launching anything;
   - `run`: the chosen action, which opens its own run at the `level` level (`run-begin --level <level>`), bounded by
     the permissions of the target repo. Steps that ask for your validation (spec, PR opening) remain stop points.
   Documents are independent: in parallel, in batches of 3.
6. **Remember** — `watch-seen mark notion-assigned <id>…` for each processed document, then
   `watch-seen touch notion-assigned`.
7. **Report** — `report.md` and a message according to `notify` (to you alone): per document, the title and its link,
   the database, the chosen action and why, the result, what awaits your decision. Notion is never modified.
