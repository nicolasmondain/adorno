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
- **One write**: the report to the owner themself, as their `notify` setting says — sent with
  `channel_id` = `slack.user_id` (their own DM), never a channel or a `D…` id; any doubt → a draft instead:
  - `dm` (default) — a direct message to themself (their own Slack user, `slack.user_id`);
  - `draft` — a Slack draft in their DM to themself, not sent;
  - `none` — the report stays in the run folder and in the answer.
  A draft reply to someone else is part of the report, never sent.
- **Enforced, not only asked**: each watch workflow opens a watch run (`adorno-github/scripts/run-begin --workflow
  <id> --watch`, `run-end <id>` at the end, failure included). While it is open, the guard hook (Claude Code) denies
  every Slack tool named `slack_*` and Notion tool named `notion-*` that writes, and every message or draft whose
  `channel_id` is not `slack.user_id` (`slack.user_id` missing → none goes out), for the whole session: the
  workflows a watch launches write nothing to Notion either: each refused update (page, what it would set) is listed
  in the report, for you to apply. Ending the run (`run-end` on it) asks you; unattended, the run ends on its TTL
  (24h). It stops a planted instruction to post, react, edit, or run `run-end`; it is not a sandbox. Not covered: a
  deliberate shell evasion (a glob for `run-end`, deleting the run file, code that builds a path), another Slack or
  Notion server (other tool names), a session Takt starts (it has no watch run), Codex and Gemini (they do not pass
  connector calls to the hook): there the rule above is the only barrier.

**Connector failure.** A connector call that errors, times out or is rate-limited is a failure; an empty success is
"nothing new". A failure is never read as "nothing". The rule covers every connector call of the run, at any step
(the first read, and the content, thread, comments or history read later).

- The window is always `since` back from now: a later run only catches up what is still inside it. The report gives
  the replay that covers the unread span: the workflow with `--since <the time watch-seen last KEY prints,
  unquoted>` (the last run without a failure; never run → the configured `since`). What was already processed is skipped (`mark`).
- Items whose action and report are done are `mark`ed, the others are not. No `touch` in a run that had a connector
  failure: `last` stays the last run without one.
- At most one retry, after a rate limit, with the indicated delay if any. Never scrape, never ask for a token.
- Report, at the top: the connector, the call, the error, what was not read, the replay command. The run ends
  `run-end <id> failed`, or `done` if the other sources went through.
- Slack is the failing connector: nothing is sent; the report stays in the run folder (`report.md`) and in the answer.

## Scripts

| Script | Does |
| --- | --- |
| `watch-conf list` | the watches configured |
| `watch-conf slack-watch NAME` | one pattern watch, defaults filled (`since` 24h, `max_messages` 200, `notify`, `action.level` L0) |
| `watch-conf slack-mentions` | the mentions watch (`channels`, `since`, `max_messages`, `agent`) |
| `watch-conf notion-assigned` | the Notion watch (`properties`, `databases`, `exclude_status`, `agents`, `mode`, `trusted_authors` []) |
| `watch-conf channel-repos CHANNEL` | the repos whose `team.slack` lists the channel: where the code behind a conversation lives |
| `watch-match NAME [FILE\|-] [--all]` | filters normalised messages: period, `includes` OR `regex`, `max_messages`, not processed yet |
| `watch-trust notion-assigned [FILE\|-]` | adds `trusted`, `action_level` (`level` if `authors_complete` and every one of `authors` is in `trusted_authors`, else L0), `untrusted` to each doc of `{id, authors: [user ids], authors_complete}`; how `authors` and `authors_complete` are built: workflow:notion:assigned step 4 |
| `watch-seen filter KEY [FILE\|-]` | drops items already processed (state `~/.adorno/state/KEY.json`) |
| `watch-seen mark KEY ID…` | records items as processed — **only after** their action and report are done |
| `watch-seen last KEY` / `touch KEY` | time of the last run / record this run |

State keys: `slack-watch-<name>`, `slack-mentions`, `notion-assigned`, `review-received` (the `pending` ids of
`adorno-github/scripts/pr-feedback-fetch`).
Exit codes: 2 usage, 3 not configured (point the owner to the `adorno-setup` skill).

## Normalised message

The connector's results are turned into a JSON array, one object per message, before any script:

```json
{"id": "C0123:1730800000.000100", "channel": "#dev-data", "ts": "1730800000.000100", "user": "U0456",
 "text": "…", "permalink": "https://…slack.com/archives/C0123/p1730800000000100", "thread_ts": null}
```

`id` = channel id + `:` + `ts`, stable across runs. Keep the full text (no summary at this stage). A message in a
thread keeps its `thread_ts`; its permalink points to the thread.
