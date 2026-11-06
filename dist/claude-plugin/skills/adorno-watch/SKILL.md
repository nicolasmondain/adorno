---
name: adorno-watch
description: The owner's Slack and Notion watches — settings of each watch (channels, pattern, period, maximum messages, action, notification), deterministic filtering of Slack messages, and memory of what is already processed so nothing is handled twice. Reading goes through the Slack and Notion connectors (read-only); the only write is the report sent to the owner themself. Use in workflow:slack:watch, workflow:slack:mentions and workflow:notion:assigned.
---

# adorno-watch

Settings come from the owner's personal layer (`local/adorno.yaml` › `slack`, `notion`, git-ignored), installed by
`bin/kit install` in `~/.adorno/registry.json`, outside every repo. The scripts of `scripts/` (relative to this file) do everything deterministic and print JSON; the
workflow's agent does the reading through the connectors and the judgment.

## Connectors

Slack and Notion are read through their MCP connectors (in Claude: the Slack and Notion connectors; tool names vary by
client, e.g. `slack_search_public_and_private`, `slack_read_channel`, `slack_read_thread`, `notion-search`,
`notion-query-data-sources`, `notion-fetch`, `notion-get-self`). No connector → stop and say which one to connect;
never scrape, never ask for a token.

- **Read-only** on Slack and Notion: never post in a channel or a thread, never react, never edit a Notion page.
- **One write**: the report to the owner themself, as their `notify` setting says — check the recipient before
  sending: it is exactly `slack.user_id` (their own DM); any doubt → a draft instead:
  - `dm` (default) — a direct message to themself (their own Slack user, `slack.user_id`);
  - `draft` — a Slack draft in their DM to themself, not sent;
  - `none` — the report stays in the run folder and in the answer.
  A draft reply to someone else is part of the report, never sent.

## Scripts

| Script | Does |
| --- | --- |
| `watch-conf list` | the watches configured |
| `watch-conf slack-watch NAME` | one pattern watch, defaults filled (`since` 24h, `max_messages` 200, `notify`, `action.level` L0) |
| `watch-conf slack-mentions` | the mentions watch (`channels`, `since`, `max_messages`, `agent`) |
| `watch-conf notion-assigned` | the Notion watch (`properties`, `databases`, `exclude_status`, `agents`, `mode`) |
| `watch-conf channel-repos CHANNEL` | the repos whose `team.slack` lists the channel: where the code behind a conversation lives |
| `watch-match NAME [FILE\|-] [--all]` | filters normalised messages: period, `includes` OR `regex`, `max_messages`, not processed yet |
| `watch-seen filter KEY [FILE\|-]` | drops items already processed (state `~/.adorno/state/KEY.json`) |
| `watch-seen mark KEY ID…` | records items as processed — **only after** their action and report are done |
| `watch-seen last KEY` / `touch KEY` | time of the last run / record this run |

State keys: `slack-watch-<name>`, `slack-mentions`, `notion-assigned`.
Exit codes: 2 usage, 3 not configured (point the owner to the `adorno-setup` skill).

## Normalised message

The connector's results are turned into a JSON array, one object per message, before any script:

```json
{"id": "C0123:1730800000.000100", "channel": "#dev-data", "ts": "1730800000.000100", "user": "U0456",
 "text": "…", "permalink": "https://…slack.com/archives/C0123/p1730800000000100", "thread_ts": null}
```

`id` = channel id + `:` + `ts`, stable across runs. Keep the full text (no summary at this stage). A message in a
thread keeps its `thread_ts`; its permalink points to the thread.
