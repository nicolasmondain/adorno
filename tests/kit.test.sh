#!/usr/bin/env bash
# Tests for bin/kit: validation, conf, install / uninstall into throwaway git repos and a throwaway home.
# Never touches your real home, your personal layer or dist/. Usage: tests/kit.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
# python3 with PyYAML runs bin/kit directly; else uv, keeping its real cache (the throwaway HOME would hide it)
if python3 -c 'import yaml' 2>/dev/null; then KIT=(python3 "$ROOT/bin/kit")
elif command -v uv >/dev/null 2>&1; then
  UV_CACHE_DIR="${UV_CACHE_DIR:-$(uv cache dir 2>/dev/null)}"; export UV_CACHE_DIR; KIT=("$ROOT/bin/kit")
else echo "needs python3 with PyYAML, or uv" >&2; exit 1; fi
export HOME="$TMP/home" ADORNO_HOME="$TMP/home/.adorno" ADORNO_LOCAL="$TMP/local"
mkdir -p "$HOME"
git config --global user.email t@t 2>/dev/null; git config --global user.name t 2>/dev/null

pass=0 fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
expect_exit() {
  local code="$1" name="$2"; shift 3
  out="$("$@" 2>"$TMP/err" </dev/null)"; got=$?
  if [ "$got" = "$code" ]; then ok "$name"; else ko "$name" "exit $got, want $code: $(tail -c 400 "$TMP/err")"; fi
}
expect_jq() { if jq -e "$2" >/dev/null 2>&1 <<<"$out"; then ok "$1"; else ko "$1" "$2 on: $(head -c 300 <<<"$out")"; fi; }
check() { if eval "$2"; then ok "$1"; else ko "$1" "$2"; fi; }

# a personal layer: the template, with a workspace pointing at our throwaway code folder
cp -r "$ROOT/local.example" "$ADORNO_LOCAL"
mkdir -p "$TMP/code/acme"
sed -i.bak "s#~/code/acme#$TMP/code/acme#" "$ADORNO_LOCAL/adorno.yaml" && rm -f "$ADORNO_LOCAL/adorno.yaml.bak"
mkrepo() {  # mkrepo DIR owner/repo
  git init -q -b main "$1"; git -C "$1" remote add origin "git@github.com:$2.git"
  git -C "$1" commit -q --allow-empty -m init
}
mkrepo "$TMP/code/acme/app" acme/app
mkrepo "$TMP/code/acme/web" acme/web
mkrepo "$TMP/code/acme/both" acme/both
mkrepo "$TMP/code/acme/own" acme/own

echo "check and conf"
expect_exit 0 "public check" -- env ADORNO_LOCAL="$TMP/none" "${KIT[@]}" check
expect_exit 0 "check with the template layer" -- "${KIT[@]}" check
expect_exit 0 "conf of a repo" -- "${KIT[@]}" conf acme/app
expect_jq "workspace and exact entry resolved, deny lists accumulated" \
  '(.scopes | index("workspace:acme")) != null and (.scopes | index("repos:acme/app")) != null and (.permissions.claude.deny | index("Bash(gh pr merge:*)")) != null'
expect_jq "commit_skill and pr_skill: repo override over the public defaults" \
  '.commit_skill == "/acme-commit" and .pr_skill == "/acme-pr"'
expect_exit 0 "conf, case-insensitive" -- "${KIT[@]}" conf ACME/App
expect_exit 0 "a repo found under a workspace path is declared" -- "${KIT[@]}" conf acme/web
expect_jq "no override: the public defaults adorno-commit and adorno-pr-open" \
  '.commit_skill == "adorno-commit" and .pr_skill == "adorno-pr-open"'
expect_exit 1 "an undeclared repo" -- "${KIT[@]}" conf nobody/repo
"${KIT[@]}" list 2>"$TMP/err" | head -n 1 >/dev/null
check "kit list | head: no traceback" '! grep -q Traceback "$TMP/err"'

bad() {  # bad NAME YAML-APPENDED — the layer with YAML appended must fail check with a message
  mkdir -p "$TMP/bad"
  printf 'owner: {name: T, github: t, language: fr}\nrepos:\n%s\n' "$2" >"$TMP/bad/adorno.yaml"
  out="$(ADORNO_LOCAL="$TMP/bad" "${KIT[@]}" check 2>&1)"; got=$?
  rm -rf "$TMP/bad"
  if [ "$got" != 0 ] && grep -q "$3" <<<"$out"; then ok "$1"; else ko "$1" "exit $got: $(tail -c 300 <<<"$out")"; fi
}
echo "validation"
bad "unknown preset" $'  ghost/repo:\n    use: [nope]' "unknown preset 'nope'"
bad "bad level" $'  ghost/repo:\n    max_level: L9' "max_level must be one of"
bad "bad ponytail level" $'  ghost/repo:\n    ponytail: max' "ponytail must be one of"
OKP="$TMP/okp"; mkdir -p "$OKP"
for level in lite ultra; do
  printf 'owner: {name: T, github: t, language: fr}\nrepos:\n  ghost/repo:\n    ponytail: %s\n' "$level" >"$OKP/adorno.yaml"
  expect_exit 0 "ponytail: $level is accepted" -- env ADORNO_LOCAL="$OKP" "${KIT[@]}" check
done
bad "a commit_skill that is not a name" $'  ghost/repo:\n    commit_skill: [a, b]' "commit_skill must be a skill or command name"
bad "a pr_skill with a shell command" $'  ghost/repo:\n    pr_skill: "gh pr create"' "pr_skill must be a skill or command name"
bad "unknown notion_spec step" $'  ghost/repo:\n    notion_spec: {merged: {Lifecycle: Done}}' "unknown step 'merged'"
bad "non-scalar notion_spec value" $'  ghost/repo:\n    notion_spec: {start: {Lifecycle: [a, b]}}' "must be a string, a number, a boolean or null"
bad "unknown notion_spec placeholder" $'  ghost/repo:\n    notion_spec: {pr_opened: {PR: "{{pr-url}}"}}' "unknown placeholder"
bad "pr_url before the PR" $'  ghost/repo:\n    notion_spec: {start: {PR: "{{pr_url}}"}}' "only exists once the PR is open"
bad "after_pr that is not a list" $'  ghost/repo:\n    after_pr: {skill: /x}' "after_pr must be a list"
bad "an after_pr skill with a shell command" $'  ghost/repo:\n    after_pr: [{skill: "npm publish", workflows: [workflow:issue:fix]}]' "after_pr\[0\].skill must be a skill or command name"
bad "an after_pr entry without workflows" $'  ghost/repo:\n    after_pr: [{skill: /x}]' "workflows must be a non-empty list of workflow ids"
bad "an after_pr workflow that is not an id" $'  ghost/repo:\n    after_pr: [{skill: /x, workflows: [issue-fix]}]' "workflows must be a non-empty list of workflow ids"
bad "an unknown after_pr need" $'  ghost/repo:\n    after_pr: [{skill: /x, workflows: [workflow:issue:fix], needs: slack}]' "needs must be one of notion"
bad "an unknown after_pr key" $'  ghost/repo:\n    after_pr: [{skill: /x, workflows: [workflow:issue:fix], when: always}]' "unknown key 'when'"
bad "an after_pr workflow that does not exist" $'  ghost/repo:\n    after_pr: [{skill: /x, workflows: [workflow:issue:fixx]}]' "unknown workflow 'workflow:issue:fixx'"
bad "the same after_pr skill twice" $'  ghost/repo:\n    after_pr: [{skill: /x, workflows: [workflow:issue:fix]}, {skill: /x, workflows: [workflow:feature:build]}]' "list several workflows in one entry"
bad "an after_pr entry that is not a mapping" $'  ghost/repo:\n    after_pr: [x]' "after_pr\[0\] must be a mapping"
bad "an after_pr entry with no workflow" $'  ghost/repo:\n    after_pr: [{skill: /x, workflows: []}]' "workflows must be a non-empty list of workflow ids"
bad "an after_pr entry without skill" $'  ghost/repo:\n    after_pr: [{workflows: [workflow:issue:fix]}]' "after_pr\[0\].skill must be a skill or command name"
bad "a commit_skill with a trailing newline" $'  ghost/repo:\n    commit_skill: "adorno-commit\\n"' "commit_skill must be a skill or command name"
bad "an empty setup_skill" $'  ghost/repo:\n    setup_skill: ""' "setup_skill must be a skill or command name"
bad "a pr_skill with a path" $'  ghost/repo:\n    pr_skill: "../x"' "pr_skill must be a skill or command name"
bad "unknown denied action" $'  ghost/repo:\n    permissions: {deny: [merge]}' "unknown action 'merge'"
bad "a negative price" $'  ghost/repo: {}\nprices:\n  claude-x: {input: -1}' "prices.claude-x: numbers >= 0"
bad "an incomplete price" $'  ghost/repo: {}\nprices:\n  claude-x: {input: 1, output: 5}' "prices.claude-x: numbers >= 0"
bad "an unknown tier" $'  ghost/repo:\n    models: {tiers: {claude: {huge: x}}}' "tiers are inherit, fast, balanced, deep, frontier"
mkdir -p "$TMP/bad/src/agents/feat"
printf -- '---\ndescription: x\neffort: extreme\n---\nx\n' >"$TMP/bad/src/agents/feat/odd.md"
bad "an unknown effort" '' "effort 'extreme' must be one of"
bad "secret in claude_env" $'  ghost/repo:\n    models: {claude_env: {ANTHROPIC_AUTH_TOKEN: x}}' "secrets stay in your shell profile"
bad "subagent model override" $'  ghost/repo:\n    models: {claude_env: {CLAUDE_CODE_SUBAGENT_MODEL: x}}' "would override every agent"
bad "plain http route" $'  ghost/repo:\n    models: {routes: {r: {base_url: "http://llm.example/v1", model: m}}}' "plain http for localhost only"
bad "user info in a route" $'  ghost/repo:\n    models: {routes: {r: {base_url: "http://127.0.0.1@evil.example/v1", model: m}}}' "must be https"
bad "a key in a route" $'  ghost/repo:\n    models: {routes: {r: {base_url: "https://x.example/v1", model: m, api_key: k}}}' "never put a key here"
bad "a non-model key variable" $'  ghost/repo:\n    models: {routes: {r: {base_url: "https://x.example/v1", model: m, api_key_env: GH_TOKEN}}}' "must name a model key variable"
bad "a non-delegable agent on a route" $'  ghost/repo:\n    models: {routes: {r: {base_url: "https://x.example/v1", model: m}}, agents: {agent:adorno: {route: r}}}' "not .delegable."

echo "install into a repo"
A="$TMP/code/acme/app"
printf '# team rules\n' >"$A/CLAUDE.md"; git -C "$A" add CLAUDE.md; git -C "$A" commit -qm "team rules"
mkdir -p "$A/.claude"; printf '{"permissions":{"allow":["Bash(make:*)"]},"model":"x"}\n' >"$A/.claude/settings.local.json"
expect_exit 0 "install" -- "${KIT[@]}" install "$A" --targets claude,codex
check "nothing to commit: every installed file is excluded from git" '[ -z "$(git -C "$A" status --porcelain)" ]'
check "the tracked CLAUDE.md is untouched" '[ "$(cat "$A/CLAUDE.md")" = "# team rules" ]'
check "Claude gets the instructions as a rule file" '[ -f "$A/.claude/rules/adorno.md" ]'
check "the registry lives in the kit home, read-only" '[ "$(ls -l "$ADORNO_HOME/registry.json" | cut -c1-10)" = "-r--------" ]'
check "the registry carries the public prices" 'jq -e ".prices[\"claude-opus-5-5\"].input == 4" "$ADORNO_HOME/registry.json" >/dev/null'
check "... with the layer's prices merged in alongside" 'jq -e ".prices[\"claude-sonnet-5\"].input == 2 and .prices[\"claude-opus-5-5\"].output == 20" "$ADORNO_HOME/registry.json" >/dev/null'
check "no personal registry inside the repo" '! grep -rq "janedoe" "$A/.claude/skills/adorno-github/repos.json"'
check "SCHEMA.md is neither an item nor shipped" '[ -f "$ROOT/src/agents/review/SCHEMA.md" ] && [ -z "$(find "$A/.claude" "$A/.codex" -iname "schema.md" 2>/dev/null)" ]'
check "your own rules and keys are kept" 'jq -e ".model == \"x\" and (.permissions.allow | index(\"Bash(make:*)\")) != null" "$A/.claude/settings.local.json" >/dev/null'
check "the repo's and the default rules are added" 'jq -e "(.permissions.allow | index(\"Bash(npm test:*)\")) != null and (.permissions.deny | index(\"Bash(gh pr merge:*)\")) != null" "$A/.claude/settings.local.json" >/dev/null'
check "the guard hook refuses direct writes in this repo" 'jq -e "[.hooks.PreToolUse[].hooks[].command | select(contains(\"guard_bash.py\") and contains(\" deny --format=claude\"))] | length == 1" "$A/.claude/settings.local.json" >/dev/null'
check "the Claude guard also sees questions (unattended runs)" 'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"Bash|AskUserQuestion\")] | length == 1" "$A/.claude/settings.local.json" >/dev/null'
check "Codex gets the same hook" 'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"^Bash$\") | .hooks[].command | select(contains(\"--format=codex\"))] | length == 1" "$A/.codex/hooks.json" >/dev/null'
HOOK="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$A/.claude/settings.local.json")"
got="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git -C x push"}}' | sh -c "$HOOK" | jq -r .hookSpecificOutput.permissionDecision)"
check "the installed hook runs and refuses" '[ "$got" = deny ]'
got="$(printf '%s' '{"tool_name":"AskUserQuestion","permission_mode":"bypassPermissions","tool_input":{}}' | sh -c "$HOOK" | jq -r .hookSpecificOutput.permissionDecision)"
check "the installed hook refuses a question in an unattended run" '[ "$got" = deny ]'
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | PATH=/nonexistent /bin/sh -c "$HOOK" 2>/dev/null; got=$?
check "without python3 the hook blocks (exit 2), it does not let commands through" '[ "$got" = 2 ]'
# shellcheck disable=SC2034  # err is read by check's eval on the next line
err="$(printf '%s' '{"tool_name":"AskUserQuestion","permission_mode":"default","tool_input":{}}' | PATH=/nonexistent /bin/sh -c "$HOOK" 2>&1 >/dev/null)"; got=$?
check "without python3 the hook also blocks questions (exit 2), and says so" '[ "$got" = 2 ] && printf "%s" "$err" | grep -q "questions"'
# shellcheck disable=SC2034  # JQ_J is read by check's eval on the next lines
JQ_J='[.hooks | to_entries[] | .key as $e | .value[] | .hooks[] | select(.command | contains("adorno-journal/scripts/journal.py")) | {event: $e, async: (.async // false), timeout}]'
check "the journal's hooks are next to the guard, one per event it records" 'jq -e "$JQ_J | map(.event) | sort == [\"PostCompact\", \"PostToolUse\", \"PostToolUseFailure\", \"SessionEnd\", \"SessionStart\", \"Stop\", \"SubagentStart\", \"SubagentStop\", \"UserPromptSubmit\"]" "$A/.claude/settings.local.json" >/dev/null'
check "a tool call is never waited for; the end of a session is" 'jq -e "$JQ_J | (map(select(.async) | .event) | sort) == [\"PostToolUse\", \"PostToolUseFailure\"] and all(.[]; .timeout == 5)" "$A/.claude/settings.local.json" >/dev/null'
check "Codex and Gemini get no journal hook" '! grep -q journal.py "$A/.codex/hooks.json"'
JHOOK="$(jq -r '.hooks.PostToolUse[] | .hooks[] | select(.command | contains("journal.py")) | .command' "$A/.claude/settings.local.json")"
PAYLOAD='{"hook_event_name":"PostToolUse","session_id":"sess-k","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"stdout":"a.txt"},"duration_ms":12}'
printf '%s' "$PAYLOAD" | sh -c "$JHOOK"; got=$?
check "without an open run the journal hook does nothing and lets the session go on" '[ "$got" = 0 ] && [ -z "$(find "$ADORNO_HOME/runs" -name events.jsonl 2>/dev/null)" ]'
mkdir -p "$ADORNO_HOME/runs/active"
jq -n --arg j "$ADORNO_HOME/runs/test-20260101T000000-1-1" --argjson exp "$(( $(date +%s) + 600 ))" \
  '{id: "20260101T000000-1-1", session: "sess-k", workflow: "workflow:test:run", expires: $exp, journal: $j}' >"$ADORNO_HOME/runs/active/20260101T000000-1-1.json"
printf '%s' "$PAYLOAD" | sh -c "$JHOOK"; got=$?
check "inside a run the installed hook records the tool call" '[ "$got" = 0 ] && jq -e ".type == \"tool.call\" and .tool == \"Bash\" and .input == \"ls\" and .dur == 12 and .session == \"sess-k\"" "$ADORNO_HOME/runs/test-20260101T000000-1-1/events.jsonl" >/dev/null'
printf '%s' "$PAYLOAD" | PATH=/nonexistent /bin/sh -c "$JHOOK" 2>/dev/null; got=$?
check "without python3 the journal hook lets the session go on (exit 0): it records, it does not guard" '[ "$got" = 0 ]'
rm -rf "$ADORNO_HOME/runs"
check "tiers become Claude models" 'grep -q "^model: opus" "$A/.claude/agents/adorno.md"'
check "frontier becomes fable" 'grep -q "^model: fable" "$A/.claude/agents/adorno-agent-core-planner.md"'
check "an agent's effort reaches Claude" 'grep -q "^effort: low" "$A/.claude/agents/adorno-agent-core-triage.md"'
check "a workflow's tier and effort reach its command" 'grep -q "^model: haiku" "$A/.claude/commands/adorno-pr-status.md" && grep -q "^effort: low" "$A/.claude/commands/adorno-pr-status.md"'
check "the vision is in every agent" 'grep -q "owner.s vision" "$A/.claude/agents/adorno-agent-fix-patch.md"'
check "the private profile is installed" '[ -f "$A/.claude/skills/adorno-profile/references/product.md" ] || [ -d "$A/.claude/skills/adorno-profile" ]'
expect_exit 0 "reinstall" -- "${KIT[@]}" install "$A" --targets claude,codex
check "a reinstall writes nothing" 'grep -q "installed 0 file" <<<"$out"'
printf 'mine\n' >>"$A/.claude/agents/adorno-agent-fix-patch.md"
"${KIT[@]}" install "$A" --targets claude,codex >/dev/null 2>"$TMP/err"
check "a file you modified is kept, with a warning" 'grep -q "you modified it" "$TMP/err" && tail -n 1 "$A/.claude/agents/adorno-agent-fix-patch.md" | grep -q mine'

echo "install is safe"
B="$TMP/code/acme/web"
mkdir -p "$B/.claude"; printf '{ broken' >"$B/.claude/settings.local.json"
expect_exit 1 "invalid settings: refused" -- "${KIT[@]}" install "$B" --targets claude
check "... before writing anything" '[ ! -e "$B/.adorno" ] && [ ! -e "$B/.claude/agents" ]'
rm "$B/.claude/settings.local.json"
mkdir -p "$B/.claude/skills/adorno-commit"
cp "$ROOT/dist/claude-plugin/skills/adorno-commit/SKILL.md" "$B/.claude/skills/adorno-commit/SKILL.md"
expect_exit 0 "install next to an identical file of yours" -- "${KIT[@]}" install "$B" --targets claude
expect_exit 0 "uninstall" -- "${KIT[@]}" uninstall "$B"
check "your identical file survives uninstall" '[ -f "$B/.claude/skills/adorno-commit/SKILL.md" ]'

echo "per-repo models"
# a layer with no defaults: only the repo's own models.agents can move review:mongodb off its family tier (deep)
ML="$TMP/models-layer"; mkdir -p "$ML"
printf 'owner: {name: T, github: t, language: fr}\nrepos:\n  acme/models:\n    models: {agents: {agent:review:mongodb: balanced}}\n' >"$ML/adorno.yaml"
M="$TMP/code/acme/models"; mkrepo "$M" acme/models
expect_exit 0 "install with a repo-level models override" -- env ADORNO_LOCAL="$ML" "${KIT[@]}" install "$M" --targets claude
check "a repo's models.agents tier reaches the installed agent" \
  'grep -q "^model: sonnet" "$M/.claude/agents/adorno-agent-review-mongodb.md" && grep -q "^model: opus" "$M/.claude/agents/adorno-agent-review-back.md"'
ADORNO_LOCAL="$ML" "${KIT[@]}" uninstall "$M" --force >/dev/null
rm -rf "$ML" "$M"

echo "tracked and untracked instruction files"
D="$TMP/code/acme/both"
printf '# team\n' >"$D/CLAUDE.md"; printf '# team agents\n' >"$D/AGENTS.md"
git -C "$D" add CLAUDE.md AGENTS.md; git -C "$D" commit -qm "team files"
expect_exit 0 "a repo tracking CLAUDE.md and AGENTS.md" -- "${KIT[@]}" install "$D" --targets claude,codex,gemini
check "both tracked files untouched" '[ "$(cat "$D/CLAUDE.md")" = "# team" ] && [ "$(cat "$D/AGENTS.md")" = "# team agents" ]'
check "Claude gets the rule file" '[ -f "$D/.claude/rules/adorno.md" ]'
check "Gemini gets the full text, not a shim to the repo's AGENTS.md" 'grep -q "owner.s vision\|vision" "$D/GEMINI.md" && ! grep -qx "@AGENTS.md" "$D/GEMINI.md"'
check "Gemini gets the guard hook" 'jq -e ".hooks.BeforeTool[0].matcher == \"run_shell_command\" and (.hooks.BeforeTool[0].hooks[0].command | contains(\"--format=gemini\"))" "$D/.gemini/settings.json" >/dev/null'
check "Codex is warned it gets nothing" 'grep -q "codex get no adorno instructions" "$TMP/err"'
check "nothing to commit" '[ -z "$(git -C "$D" status --porcelain)" ]'
"${KIT[@]}" uninstall "$D" --force >/dev/null
O="$TMP/code/acme/own"
printf '# my notes\n' >"$O/AGENTS.md"
expect_exit 0 "an untracked AGENTS.md of yours" -- "${KIT[@]}" install "$O" --targets codex
check "... gets the block and is excluded from git" 'grep -q "adorno:begin\|<!-- adorno" "$O/AGENTS.md" && [ -z "$(git -C "$O" status --porcelain)" ]'
"${KIT[@]}" uninstall "$O" --force >/dev/null
check "... and gets back to what it was" '[ "$(cat "$O/AGENTS.md")" = "# my notes" ]'

echo "the registry follows the personal layer"
cp "$ADORNO_LOCAL/adorno.yaml" "$TMP/layer.bak"
awk '{ print } /^repos:/ { print "  newco/svc: {max_level: L1}" }' "$TMP/layer.bak" >"$ADORNO_LOCAL/adorno.yaml"
mkrepo "$TMP/newco/svc" newco/svc
expect_exit 0 "install for a repo added to the layer" -- "${KIT[@]}" install "$TMP/newco/svc" --targets claude
check "the registry knows it at once" 'jq -e "[.. | objects | has(\"newco/svc\")] | any" "$ADORNO_HOME/registry.json" >/dev/null'
check "the run journal's settings are in it, where the writer reads them" 'jq -e ".journal == {reasoning: false, retention_days: 30, max_mb: 2048}" "$ADORNO_HOME/registry.json" >/dev/null'
"${KIT[@]}" uninstall "$TMP/newco/svc" --force >/dev/null
sed 's/^  retention_days: 30 .*/  retention_days: soon/; s/^  reasoning: false .*/  reasoning: sometimes/' "$TMP/layer.bak" >"$ADORNO_LOCAL/adorno.yaml"
printf '  keep_forever: true\n' >>"$ADORNO_LOCAL/adorno.yaml"
expect_exit 1 "invalid journal settings are refused" -- "${KIT[@]}" check
check "... each one named" 'grep -q "journal.retention_days must be a positive integer" "$TMP/err" && grep -q "journal.reasoning must be true or false" "$TMP/err" && grep -q "journal.keep_forever: unknown setting" "$TMP/err"'
cp "$TMP/layer.bak" "$ADORNO_LOCAL/adorno.yaml"

# an install made before the journal recorded one hook per settings file: the next one takes it over
jq '.hook |= with_entries(.value |= .[0])' "$A/.adorno/installed.json" >"$TMP/state.json" && mv "$TMP/state.json" "$A/.adorno/installed.json"
expect_exit 0 "reinstall over an older install's state" -- "${KIT[@]}" install "$A" --targets claude,codex
check "... the guard is still there once, the journal hooks once each" 'jq -e "([.hooks.PreToolUse[].hooks[] | select(.command | contains(\"guard_bash.py\"))] | length == 1) and ([.hooks.Stop[].hooks[] | select(.command | contains(\"journal.py\"))] | length == 1)" "$A/.claude/settings.local.json" >/dev/null'

echo "uninstall"
expect_exit 0 "uninstall the repo" -- "${KIT[@]}" uninstall "$A" --force
check "agents gone" '[ ! -e "$A/.claude/agents" ]'
check "exclude block gone" '! grep -q "adorno:begin" "$(git -C "$A" rev-parse --git-path info/exclude)"'
check "the Codex hook file is gone" '[ ! -e "$A/.codex/hooks.json" ]'
check "the hook is gone" '! jq -e ".hooks" "$A/.claude/settings.local.json" >/dev/null'
check "your settings are back as they were" 'jq -e ".model == \"x\" and .permissions.allow == [\"Bash(make:*)\"] and (.permissions.deny == null)" "$A/.claude/settings.local.json" >/dev/null'

echo "which skills stay in the model's list, from what the session reads"
P="$TMP/code/acme/probe"; mkrepo "$P" acme/probe
mkdir -p "$ADORNO_LOCAL/src/skills/lonely-own"
printf -- '---\nname: lonely-own\ndescription: A private skill nothing cites.\n---\n\nNothing.\n' >"$ADORNO_LOCAL/src/skills/lonely-own/SKILL.md"
printf 'Use `test-driven-development`.\n' >"$ADORNO_LOCAL/src/instructions/99-probe.md"
expect_exit 0 "install with a private skill and a private instruction naming an imported skill" -- "${KIT[@]}" install "$P" --targets claude
check "a private skill nothing cites stays listed" \
  '[ -f "$P/.claude/skills/lonely-own/SKILL.md" ] && ! grep -q "disable-model-invocation" "$P/.claude/skills/lonely-own/SKILL.md"'
check "an imported skill a private instruction names stays listed (hidden in the public build)" \
  '[ -f "$P/.claude/skills/test-driven-development/SKILL.md" ] && ! grep -q "disable-model-invocation" "$P/.claude/skills/test-driven-development/SKILL.md"'
"${KIT[@]}" uninstall "$P" --force >/dev/null
rm -rf "$P" "$ADORNO_LOCAL/src/skills/lonely-own" "$ADORNO_LOCAL/src/instructions/99-probe.md"

echo "global install"
expect_exit 0 "install --global" -- "${KIT[@]}" install --global --targets claude,codex,gemini
check "Codex asks before direct writes (its own rules)" 'grep -q "prefix_rule(pattern=\[\"git\", \"push\"\], decision=\"prompt\"" "$HOME/.codex/rules/adorno.rules"'
check "Gemini asks too (its policy engine)" 'grep -q "decision = \"ask_user\"" "$HOME/.gemini/policies/adorno.toml" && grep -q "\"gh pr comment\"" "$HOME/.gemini/policies/adorno.toml"'
check "in your user settings, direct shell writes ask (they apply to every project)" 'jq -e "(.permissions.ask | index(\"Bash(gh pr comment:*)\")) != null and ((.permissions.deny // []) | index(\"Bash(gh pr comment:*)\")) == null" "$HOME/.claude/settings.json" >/dev/null'
check "the global install records runs too" 'jq -e "[.hooks.Stop[].hooks[].command | select(contains(\"adorno-journal/scripts/journal.py\"))] | length == 1" "$HOME/.claude/settings.json" >/dev/null'
check "the global guard hook asks" 'jq -e "[.hooks.PreToolUse[].hooks[].command | select(contains(\"guard_bash.py\") and contains(\" ask --format=claude\"))] | length == 1" "$HOME/.claude/settings.json" >/dev/null'
check "... and edits of adorno's files stay denied" 'jq -e "(.permissions.deny | index(\"Edit(~/.adorno/registry.json)\")) != null" "$HOME/.claude/settings.json" >/dev/null'
expect_exit 0 "dry run of --global" -- "${KIT[@]}" install --global --targets claude --dry-run
check "... names your user settings" 'grep -q "~/.claude/settings.json" <<<"$out"'
expect_exit 0 "a project next to a global install" -- "${KIT[@]}" install "$A" --targets claude
check "takes its instructions from the global one" '[ ! -e "$A/.claude/rules/adorno.md" ] && [ ! -e "$A/AGENTS.md" ]'
check "... and leaves the recording to it (no event written twice), keeping its own guard" '! grep -q journal.py "$A/.claude/settings.local.json" && grep -q guard_bash.py "$A/.claude/settings.local.json"'
"${KIT[@]}" uninstall "$A" --force >/dev/null
expect_exit 0 "uninstall --global" -- "${KIT[@]}" uninstall --global
check "the hooks are removed from your user settings" '[ ! -e "$HOME/.claude/settings.json" ] || ! jq -e ".hooks" "$HOME/.claude/settings.json" >/dev/null'
check "rules removed from your user settings" '[ ! -e "$HOME/.claude/settings.json" ] || ! jq -e ".permissions.deny // .permissions.ask" "$HOME/.claude/settings.json" >/dev/null'
check "the Codex and Gemini rules are removed" '[ ! -e "$HOME/.codex/rules/adorno.rules" ] && [ ! -e "$HOME/.gemini/policies/adorno.toml" ]'
check "the registry is removed" '[ ! -e "$ADORNO_HOME/registry.json" ]'

echo "workspace install"
expect_exit 0 "install --workspace" -- "${KIT[@]}" install --workspace acme --targets claude
check "every repo of the workspace" '[ -f "$TMP/code/acme/app/.claude/agents/adorno.md" ] && [ -f "$TMP/code/acme/web/.claude/agents/adorno.md" ]'
expect_exit 0 "uninstall --workspace" -- "${KIT[@]}" uninstall --workspace acme --force

echo "areas, entry and orphans"
bad "an area role naming an unknown agent" $'  ghost/repo:\n    areas: {back: {build: "agent:feat:nope"}}' "areas.back.build names unknown agent 'agent:feat:nope'"
bad "a role outside its families" $'  ghost/repo:\n    areas: {back: {build: "agent:review:code"}}' "not a feat/test/docs/chore agent"
bad "an unknown skill in an area" $'  ghost/repo:\n    areas: {back: {skills: [no-such-skill]}}' "unknown skill 'no-such-skill'"
bad "an unknown area key" $'  ghost/repo:\n    areas: {back: {reviewers: []}}' "areas.back.reviewers: unknown key"
bad "a nested sub-area" $'  ghost/repo:\n    areas: {back: {sub: {q: {sub: {x: {}}}}}}' "areas.back.sub.q.sub: unknown key"
bad "a role in always other than review and skills" $'  ghost/repo:\n    areas: {always: {build: "agent:feat:back"}}' "areas.always.build: unknown key"
bad "an invalid content regex" $'  ghost/repo:\n    areas: {back: {content: "(unclosed"}}' "areas.back.content is an invalid regex"
# (?i) is Oniguruma-only: BWK awk (macOS) rejects it, gawk / mawk (Linux CI) accept it. kit check runs the awk that
# pr-areas will run on the same machine, so the case only applies where that awk rejects it.
if ! AREA_RE='(?i)token' awk 'BEGIN { if ("" ~ ENVIRON["AREA_RE"]) {} }' 2>/dev/null; then
  bad "a content regex awk cannot run" $'  ghost/repo:\n    areas: {back: {content: "(?i)token"}}' "areas.back.content is an invalid regex"
fi
bad "an unknown fallback" $'  ghost/repo:\n    fallbacks: {lint: "agent:fix:patch"}' "fallbacks.lint: unknown key"
bad "a fallback from the wrong family" $'  ghost/repo:\n    fallbacks: {perf: {agent: "agent:test:unit"}}' "fallbacks.perf.agent: 'agent:test:unit' is not a perf/fix agent"
bad "a test fallback from another family" $'  ghost/repo:\n    fallbacks: {test: "agent:fix:patch"}' "fallbacks.test: 'agent:fix:patch' is not a test agent"
bad "a nit fallback from another family" $'  ghost/repo:\n    fallbacks: {nit: "agent:perf:nodejs"}' "fallbacks.nit: 'agent:perf:nodejs' is not a fix/test/refactor/ci/docs/chore agent"
bad "area_reviewers is refused with the migration hint" $'  ghost/repo:\n    area_reviewers: {docs: ["agent:review:security"]}' "bin/kit migrate areas"
OKL="$TMP/okl"; mkdir -p "$OKL"
printf 'owner: {name: T, github: t, language: fr}\nrepos:\n  ghost/repo:\n    areas: {back: {review: ["-agent:review:tests"]}}\n' >"$OKL/adorno.yaml"
expect_exit 0 "a removal entry (-x) is accepted" -- env ADORNO_LOCAL="$OKL" "${KIT[@]}" check
# public stack presets: a repo calls them, a local preset may build on one but not take its name
printf 'owner: {name: T, github: t, language: fr}\npresets:\n  ours: {use: [rails], context: ["Postgres 16"]}\nrepos:\n  ghost/repo: {use: [ours, sql]}\n' >"$OKL/adorno.yaml"
expect_exit 0 "a local preset using a public one is accepted" -- env ADORNO_LOCAL="$OKL" "${KIT[@]}" check
expect_exit 0 "conf of a repo on public presets" -- env ADORNO_LOCAL="$OKL" "${KIT[@]}" conf ghost/repo
expect_jq "the public presets reach the repo through the local one" \
  '(.areas.back.sub | has("rails") and has("activerecord") and has("sql") and has("migration")) and (.areas.back.sub.migration.review | index("agent:review:sql")) and .context == ["Postgres 16"]'
printf 'owner: {name: T, github: t, language: fr}\npresets:\n  sql: {context: ["mine"]}\n' >"$OKL/adorno.yaml"
out="$(ADORNO_LOCAL="$OKL" "${KIT[@]}" check 2>&1)"; got=$?
if [ "$got" != 0 ] && grep -q "presets.sql reuses the name of a public preset" <<<"$out"; then ok "a local preset named like a public one fails"; else ko "a local preset named like a public one fails" "exit $got: $(tail -c 300 <<<"$out")"; fi

# a throwaway copy of the kit to break the public sources
SB="$TMP/sandbox"; mkdir -p "$SB"
cp -r "$ROOT/bin" "$ROOT/src" "$ROOT/adapters" "$ROOT/vendor" "$ROOT/kit.yaml" "$ROOT/kit.lock" "$ROOT/repos.yaml" "$SB/"
SBKIT=("${KIT[@]}"); SBKIT[${#SBKIT[@]}-1]="$SB/bin/kit"
printf -- '---\ndescription: A lonely agent no role names.\ntools: [read]\nmodel: fast\n---\n\nNothing.\n' >"$SB/src/agents/feat/lonely.md"
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check 2>&1)"; got=$?
if [ "$got" != 0 ] && grep -q "orphan agent 'agent:feat:lonely': no area role, fallback or entry names it" <<<"$out"; then ok "an orphan agent fails the public check"; else ko "an orphan agent fails the public check" "exit $got: $(tail -c 300 <<<"$out")"; fi
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" list --orphans 2>&1)"
check "list --orphans names it" '[ "$out" = "agent:feat:lonely" ]'
sed -i.bak 's/^model: fast/model: fast\nentry: [workflow:spec:new]/' "$SB/src/agents/feat/lonely.md"; rm -f "$SB/src/agents/feat/lonely.md.bak"
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check 2>&1)"; got=$?
if [ "$got" != 0 ] && grep -q "entry 'workflow:spec:new' does not list agent:feat:lonely in its uses.agents" <<<"$out"; then ok "an entry whose workflow does not list the agent fails"; else ko "an entry whose workflow does not list the agent fails" "exit $got: $(tail -c 300 <<<"$out")"; fi
sed -i.bak 's/workflow:spec:new/workflow:spec:ghost/' "$SB/src/agents/feat/lonely.md"; rm -f "$SB/src/agents/feat/lonely.md.bak"
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check 2>&1)"; got=$?
if [ "$got" != 0 ] && grep -q "entry names unknown workflow 'workflow:spec:ghost'" <<<"$out"; then ok "an entry naming no workflow fails"; else ko "an entry naming no workflow fails" "exit $got: $(tail -c 300 <<<"$out")"; fi
out="$(ADORNO_LOCAL="$TMP/none" "${KIT[@]}" list --orphans 2>&1)"; got=$?
# perf:nodejs, perf:mongodb, review:mongodb and review:sql are named only by public presets
check "list --orphans is empty on the real registry" '[ "$got" = 0 ] && [ -z "$out" ]'
rm -f "$SB/src/agents/feat/lonely.md"
sed -i.bak 's/agent:fix:security, //' "$SB/src/workflows/pr/ship.md"; rm -f "$SB/src/workflows/pr/ship.md.bak"
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check 2>&1)"; got=$?
if [ "$got" != 0 ] && grep -q "workflow:pr:ship dispatches role 'fix' but uses.agents lacks 'agent:fix:security'" <<<"$out"; then ok "a dispatcher missing an agent of its roles fails"; else ko "a dispatcher missing an agent of its roles fails" "exit $got: $(tail -c 300 <<<"$out")"; fi
cp "$ROOT/src/workflows/pr/ship.md" "$SB/src/workflows/pr/ship.md"
sed -i.bak 's/^roles: \[.*\]/roles: [fix, deploy]/' "$SB/src/workflows/pr/ship.md"; rm -f "$SB/src/workflows/pr/ship.md.bak"
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check 2>&1)"; got=$?
if [ "$got" != 0 ] && grep -q "roles: unknown role 'deploy'" <<<"$out"; then ok "an unknown role value fails"; else ko "an unknown role value fails" "exit $got: $(tail -c 300 <<<"$out")"; fi
cp "$ROOT/src/workflows/pr/ship.md" "$SB/src/workflows/pr/ship.md"
# a sandbox import of its own (the last one in kit.yaml), so the real `uncited` lists stay out of the way
printf '  - name: fixture\n    source: ./fixture\n' >>"$SB/kit.yaml"
mkdir -p "$SB/vendor/fixture/skills/lonely"
printf -- '---\nname: lonely\ndescription: An imported skill no item cites.\n---\n\nNothing.\n' >"$SB/vendor/fixture/skills/lonely/SKILL.md"
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check 2>&1)"; got=$?
if [ "$got" != 0 ] && grep -q "orphan skill 'lonely' (import fixture): no item cites it" <<<"$out"; then ok "an imported skill no item cites fails the public check"; else ko "an imported skill no item cites fails the public check" "exit $got: $(tail -c 300 <<<"$out")"; fi
printf 'Use `lonely-helper` for this.\n' >"$SB/src/instructions/99-probe.md"
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check 2>&1)"; got=$?
if [ "$got" != 0 ] && grep -q "orphan skill 'lonely' (import fixture)" <<<"$out"; then ok "a longer name containing the skill's is not a citation"; else ko "a longer name containing the skill's is not a citation" "exit $got: $(tail -c 300 <<<"$out")"; fi
mkdir -p "$SB/vendor/fixture/skills/other"
printf -- '---\nname: other\ndescription: An imported skill that cites another.\n---\n\nSee `lonely`.\n' >"$SB/vendor/fixture/skills/other/SKILL.md"
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check 2>&1)"; got=$?
if [ "$got" != 0 ] && grep -q "orphan skill 'lonely' (import fixture)" <<<"$out"; then ok "an imported skill citing it is not a citation"; else ko "an imported skill citing it is not a citation" "exit $got: $(tail -c 300 <<<"$out")"; fi
rm -rf "$SB/vendor/fixture/skills/other"
printf 'Use `lonely` for this.\n' >"$SB/src/instructions/99-probe.md"
expect_exit 0 "an instruction citing the exact name clears the orphan" -- env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check
rm -f "$SB/src/instructions/99-probe.md"
printf '    uncited: [lonely]\n' >>"$SB/kit.yaml"
expect_exit 0 "listed in its import's uncited, it passes" -- env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check
sed -i.bak 's/uncited: \[lonely\]/uncited: [lonely, ghost]/' "$SB/kit.yaml"; rm -f "$SB/kit.yaml.bak"
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check 2>&1)"; got=$?
if [ "$got" != 0 ] && grep -q "import fixture: uncited 'ghost' is not one of its skills" <<<"$out"; then ok "an uncited entry naming no imported skill fails"; else ko "an uncited entry naming no imported skill fails" "exit $got: $(tail -c 300 <<<"$out")"; fi
rm -rf "$SB/vendor/fixture"; cp "$ROOT/kit.yaml" "$SB/kit.yaml"
cp "$ROOT/.gitignore" "$SB/"; git init -q "$SB"
# the full build (every target), with the template layer present: CI never runs `kit build`, so $ROOT/dist only
# holds the committed part there
expect_exit 0 "build into the sandbox, the template layer present" -- "${SBKIT[@]}" build
check "the sandbox build renders every target" '[ -d "$SB/dist/claude" ] && [ -d "$SB/dist/codex" ] && [ -d "$SB/dist/gemini" ]'
check "entry never reaches a rendered agent, on any target" '! grep -rq "^entry:" "$SB/dist" --include=*.md --include=*.toml'
check "the public build has no template identity, the layer present" '! grep -rq "janedoe" "$SB/dist"'
check "hidden is a Claude setting: no other target gets it" \
  '[ -d "$SB/dist/codex" ] && [ -f "$SB/dist/gemini/.gemini/commands/adorno-agent-review-code.toml" ] && ! grep -rq "disable-model-invocation" "$SB/dist/codex" "$SB/dist/gemini"'

echo "check --dist on a fresh clone"
# a fresh clone: only what .gitignore lets be committed
find "$SB/dist" -mindepth 1 -maxdepth 1 ! -name claude-plugin ! -name AGENTS.md -exec rm -rf {} +
expect_exit 0 "check --dist passes with no ignored target" -- env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check --dist
PLUGIN_FILE="$SB/dist/claude-plugin/agents/adorno-agent-review-code.md"
cp "$PLUGIN_FILE" "$TMP/plugin-file.bak"
echo stale >>"$PLUGIN_FILE"
expect_exit 1 "a stale plugin file fails check --dist" -- env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check --dist
cp "$TMP/plugin-file.bak" "$PLUGIN_FILE"
echo stray >"$SB/dist/claude-plugin/stray.md"
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check --dist 2>&1)"; got=$?
if [ "$got" = 1 ] && grep -q "dist/ is out of date" <<<"$out"; then ok "a stray plugin file fails check --dist as out of date"; else ko "a stray plugin file fails check --dist as out of date" "exit $got: $(tail -c 300 <<<"$out")"; fi
rm -f "$SB/dist/claude-plugin/stray.md"
mkdir -p "$SB/dist/claude"; echo x >"$SB/dist/claude/é.md"
expect_exit 0 "a file under an ignored target passes check --dist, even a non-ASCII name" -- env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check --dist
rm -rf "$SB/dist/claude"
mv "$SB/dist/AGENTS.md" "$TMP/agents.bak"
expect_exit 1 "a missing dist/AGENTS.md fails check --dist" -- env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check --dist
mv "$TMP/agents.bak" "$SB/dist/AGENTS.md"

expect_exit 0 "the real registry passes with every dispatcher's roles covered" -- env ADORNO_LOCAL="$TMP/none" "${KIT[@]}" check
check "no area_reviewers reader is left in src/" '[ -d "$ROOT/src" ] && [ -f "$ROOT/bin/kit" ] && [ -f "$ROOT/bin/kitlib/validate.py" ] && [ -f "$ROOT/bin/kitlib/commands.py" ] && ! grep -rn --exclude-dir=__pycache__ "area_reviewers" "$ROOT/src" "$ROOT/bin/kit" "$ROOT/bin/kitlib" | grep -v -e "src/skills/adorno-setup/" -e "bin/kitlib/validate.py:.*area_reviewers\|bin/kitlib/commands.py:.*area_reviewers" -e SCHEMA.md | grep .'
check "pr:ship leaves no family agent of its subject" '! grep -q "family agent of its subject" "$ROOT/src/workflows/pr/ship.md"'

echo "migrate areas"
MIG="$TMP/mig"; mkdir -p "$MIG"
printf '%s\n' 'owner: {name: T, github: t, language: fr}' 'repos:' '  acme/app:' '    area_reviewers:' \
  '      docs: [agent:review:security]' '      api: [agent:review:api, agent:review:security]' \
  '      mongodb: [agent:review:mongodb, agent:review:back]' '      always: [agent:review:code]' \
  '      front: [agent:review:code]' '  acme/web:' '    use: [node]' '    area_reviewers:' \
  '      mongodb: [agent:review:mongodb]' '  acme/mix:' '    use: [mongodb]' '    area_reviewers:' \
  '      mongodb: [agent:review:mongodb]' >"$MIG/adorno.yaml"
cp "$MIG/adorno.yaml" "$TMP/mig-before.yaml"
out="$(ADORNO_LOCAL="$MIG" "${KIT[@]}" migrate areas 2>"$TMP/err")"; got=$?
check "migrate areas succeeds although check fails" '[ "$got" = 0 ] && ! ADORNO_LOCAL="$MIG" "${KIT[@]}" check >/dev/null 2>&1'
expect_jq "docs: the old list is all additions" '[.[] | select(.area_path == "areas.docs.review")][0].new == ["agent:review:security"]'
expect_jq "api: only the addition remains" '[.[] | select(.area_path == "areas.api.review")][0].new == ["agent:review:security"]'
expect_jq "mongodb maps to the mongodb preset's sub-area, nothing to add over the inherited reviewers" \
  '([.[] | select(.area_path == "areas.back.sub.mongodb.review" and .scope == "repos.acme/app")] | length == 1 and all(.new == [] and .use == ["mongodb"]))'
check "the snippet calls the mongodb preset" 'grep -q -- "- mongodb" "$TMP/err"'
expect_jq "always: a public reviewer missing from the old list becomes a removal" \
  '[.[] | select(.area_path == "areas.always.review")][0].new == ["-agent:review:ponytail"]'
expect_jq "an area omitting a public reviewer gets its -x" \
  '[.[] | select(.area_path == "areas.front.review")][0].new == ["agent:review:code", "-agent:review:front"]'
expect_jq "a scope that already calls a preset keeps it, mongodb is appended once" \
  '([.[] | select(.scope == "repos.acme/web")][0].use == ["node", "mongodb"]) and ([.[] | select(.scope == "repos.acme/mix")][0].use == ["mongodb"])'
check "migrate prints a YAML snippet per scope" 'grep -q "repos:" "$TMP/err" && grep -q "areas:" "$TMP/err"'
check "migrate writes nothing" 'cmp -s "$MIG/adorno.yaml" "$TMP/mig-before.yaml" && [ "$(ls "$MIG")" = "adorno.yaml" ]'

echo "migrate agents"
bad "a merged agent id points to the migration" $'  ghost/repo:\n    areas: {front: {review: ["agent:review:perf"]}}' "names unknown agent 'agent:review:perf' (merged into 'agent:review:front': \`bin/kit migrate agents\`"
check "an unknown agent is not also reported as missing from the dispatchers" '! grep -q "uses.agents lacks" <<<"$out"'
mkdir -p "$TMP/old"
for layer in 'notion:|  assigned: {agents: {Perf: agent:review:perf}}' \
  'defaults:|  models:|    agents: {agent:review:perf: fast}' \
  'slack:|  watches:|    w: {channels: ["#c"], includes: [x], action: {agent: agent:review:perf-back}}'; do
  printf 'owner: {name: T, github: t, language: fr}\n%s\n' "$(tr '|' '\n' <<<"$layer")" >"$TMP/old/adorno.yaml"
  out="$(ADORNO_LOCAL="$TMP/old" "${KIT[@]}" check 2>&1)"; got=$?
  check "a merged agent id in ${layer%%:*} points to the migration" '[ "$got" != 0 ] && grep -q "merged into '"'"'agent:review:" <<<"$out"'
done
rm -rf "$TMP/old"
MA="$TMP/ma"; mkdir -p "$MA"
printf '%s\n' 'owner: {name: T, github: t, language: fr}' \
  'defaults:' '  models:' '    agents: {agent:review:perf-back: balanced, agent:review:perf: fast, agent:review:front: deep}' \
  'presets:' '  web:' '    areas:' '      front: {review: [agent:review:perf, agent:review:front]}' \
  '      back: {review: "-agent:review:perf-back"}' \
  'workspaces:' '  acme:' '    repos: ["acme/*"]' '    areas:' '      front: {review: ["-agent:review:perf"]}' \
  'repos:' '  acme/app:' '    areas:' '      back:' '        review: [agent:review:tests, agent:review:perf-back]' \
  '        sub: {query: {review: ["-agent:review:perf-back", "-agent:review:back"]}}' \
  '      front: {review: ["-agent:review:front", "agent:review:perf"]}' \
  '      docs: {review: [agent:review:security]}' \
  'slack:' '  watches:' '    w: {channels: ["#c"], includes: [x], action: {agent: agent:review:perf-back}}' \
  'notion:' '  assigned: {agents: {"Perf v2.1": agent:review:perf, Bugs: workflow:issue:fix}}' >"$MA/adorno.yaml"
cp "$MA/adorno.yaml" "$TMP/ma-before.yaml"
out="$(ADORNO_LOCAL="$MA" "${KIT[@]}" migrate agents 2>"$TMP/err")"; got=$?
check "migrate agents succeeds although check fails" '[ "$got" = 0 ] && ! ADORNO_LOCAL="$MA" "${KIT[@]}" check >/dev/null 2>&1'
expect_jq "one row per setting naming a merged id, nothing else" \
  '([.[] | .scope + " " + .path] | sort) == (["defaults models.agents.agent:review:perf-back", "defaults models.agents.agent:review:perf", "presets.web areas.front.review", "presets.web areas.back.review", "workspaces.acme areas.front.review", "repos.acme/app areas.back.review", "repos.acme/app areas.back.sub.query.review", "repos.acme/app areas.front.review", "slack watches.w.action.agent", "notion assigned.agents.Perf v2.1"] | sort)'
expect_jq "a renamed reviewer is renamed in place" \
  '(.[] | select(.path == "areas.back.review")) | .old == ["agent:review:tests", "agent:review:perf-back"] and .new == ["agent:review:tests", "agent:review:back"] and (has("decision") | not)'
expect_jq "a renamed reviewer already present is dropped as a duplicate" \
  '(.[] | select(.scope == "presets.web" and .path == "areas.front.review")) | .new == ["agent:review:front"]'
expect_jq "a scalar removal that would remove the surviving reviewer asks a human" \
  '(.[] | select(.scope == "presets.web" and .path == "areas.back.review")) | .new == null and (.decision | test("agent:review:back"))'
expect_jq "a merged reviewer next to the removal of its survivor asks a human" \
  '(.[] | select(.path == "areas.front.review" and .scope == "repos.acme/app")) | .new == ["-agent:review:front"] and (.decision | test("agent:review:front"))'
expect_jq "a removal already made on the target only loses its duplicate" \
  '(.[] | select(.path == "areas.back.sub.query.review")) | .new == ["-agent:review:back"] and (has("decision") | not)'
expect_jq "a removal that would remove the surviving reviewer asks a human" \
  '(.[] | select(.scope == "workspaces.acme")) | .new == [] and (.decision | test("agent:review:front"))'
expect_jq "a model setting is removed, its tier left to a human" \
  '[.[] | select(.path | startswith("models.agents."))] | length == 2 and all(.new == null and (.decision | test("agent:review:")))'
expect_jq "a watch action and a Notion agent are renamed" \
  '([.[] | select(.scope == "slack" or .scope == "notion") | .new] | sort) == ["agent:review:back", "agent:review:front"]'
check "migrate agents prints a YAML snippet per scope and flags the decision" \
  'grep -q "workspaces:" "$TMP/err" && grep -q "remove models.agents.agent:review:perf-back" "$TMP/err" && ! grep -q "balanced" "$TMP/err" && grep -qi "decide" "$TMP/err"'
check "migrate agents keeps a key with a dot whole in the snippet" 'grep -q "Perf v2.1: agent:review:front" "$TMP/err"'
check "migrate agents writes nothing" 'cmp -s "$MA/adorno.yaml" "$TMP/ma-before.yaml" && [ "$(ls "$MA")" = "adorno.yaml" ]'
out="$("${KIT[@]}" migrate agents 2>/dev/null)"
check "nothing to migrate in the template layer" '[ "$out" = "[]" ]'

check "review:security opens with a step 0 qualification and a one-line pass" \
  'grep -q "Step 0, qualification" "$ROOT"/dist/claude-plugin/agents/adorno-agent-review-security.md && grep -q "one line" "$ROOT"/dist/claude-plugin/agents/adorno-agent-review-security.md'

check "review:security step 0 only dismisses content matches, never path matches nor on diff text" \
  'grep -q "Only a match of the security .content. regex can be dismissed" "$ROOT"/dist/claude-plugin/agents/adorno-agent-review-security.md && grep -q "never evidence for a No" "$ROOT"/dist/claude-plugin/agents/adorno-agent-review-security.md'

check "an imported skill only agents and areas name is kept out of the model's list" \
  'grep -q "^disable-model-invocation: true" "$ROOT"/dist/claude-plugin/skills/test-driven-development/SKILL.md'
check "typescript-pro is area-only: kept out of the model's list" \
  'grep -q "^disable-model-invocation: true" "$ROOT"/dist/claude-plugin/skills/typescript-pro/SKILL.md'
check "skills a workflow or the instructions name stay listed (ours, ponytail)" \
  '[ -f "$ROOT"/dist/claude-plugin/skills/adorno-commit/SKILL.md ] && [ -f "$ROOT"/dist/claude-plugin/skills/ponytail/SKILL.md ] && ! grep -q "disable-model-invocation" "$ROOT"/dist/claude-plugin/skills/adorno-commit/SKILL.md "$ROOT"/dist/claude-plugin/skills/ponytail/SKILL.md'
check "agent commands are kept out of the list, workflow commands stay" \
  'grep -q "^disable-model-invocation: true" "$ROOT"/dist/claude-plugin/commands/adorno-agent-review-code.md && [ -f "$ROOT"/dist/claude-plugin/commands/adorno-pr-ship.md ] && ! grep -q "disable-model-invocation" "$ROOT"/dist/claude-plugin/commands/adorno-pr-ship.md'
check "no _family.md hard-codes typescript-pro" '! grep -l "typescript-pro" "$ROOT"/src/agents/*/_family.md'
check "the skills-by-area rule appears once in the orchestration instructions" \
  '[ "$(grep -c "Skills by area" "$ROOT"/src/instructions/10-orchestration.md)" = 1 ]'

echo "import --check and --update"
# an upstream git repo and a minimal kit importing from it over file://
UP="$TMP/up"; IK="$TMP/imp"
git init -q -b main "$UP"; mkdir -p "$UP/skills/foo" "$UP/agents"
printf -- '---\nname: foo\ndescription: Foo things.\n---\n\nDo foo.\n' >"$UP/skills/foo/SKILL.md"
printf -- '---\nname: bar\ndescription: Bar reviewer.\n---\n\nReview bar.\n' >"$UP/agents/bar.md"
printf 'readme\n' >"$UP/README.md"
git -C "$UP" add -A; git -C "$UP" commit -q -m init
upcommit() { git -C "$UP" add -A; git -C "$UP" commit -q -m "$1"; }
mkdir -p "$IK/src/agents/review" "$IK/src/instructions"
cp -r "$ROOT/bin" "$ROOT/adapters" "$IK/"
printf '%s\n' 'name: t' 'version: 0.0.0' 'description: t' 'targets: [claude]' 'imports:' '  - name: up' \
  "    source: file://$UP" '    ref: main' '    include: [skills/foo, agents/bar.md]' >"$IK/kit.yaml"
printf -- '---\nextends: up/bar\ndescription: Our bar reviewer.\n---\n\nMore.\n' >"$IK/src/agents/review/code.md"
mkdir -p "$IK/src/skills/ourfoo"
printf -- '---\nextends: up/foo\ndescription: Our foo.\n---\n\nMore foo.\n' >"$IK/src/skills/ourfoo/SKILL.md"
printf 'Use `foo` here.\n' >"$IK/src/instructions/10-probe.md"
IKKIT=("${KIT[@]}"); IKKIT[${#IKKIT[@]}-1]="$IK/bin/kit"
snap() { (cd "$IK" && find vendor kit.lock -type f -exec shasum {} + | sort); }
expect_exit 1 "check before any import: exits 1" -- "${IKKIT[@]}" import --check
check "it says not imported yet" 'grep -q "^up: not imported yet" <<<"$out"'
expect_exit 0 "import from a file:// source" -- "${IKKIT[@]}" import
check "it pins the upstream commit" 'grep -q "commit: $(git -C "$UP" rev-parse HEAD)" "$IK/kit.lock"'
expect_exit 0 "check right after the import: up to date" -- "${IKKIT[@]}" import --check
check "it says up to date" 'grep -q "^up: up to date" <<<"$out"'
printf 'more\n' >>"$UP/README.md"; upcommit readme
expect_exit 0 "commits outside the imported items: check passes" -- "${IKKIT[@]}" import --check
check "it counts the commits and says no item changed" 'grep -q "1 commit(s) behind main .*no imported item changed" <<<"$out"'
snap >"$TMP/snap-before"
printf -- '---\nname: foo\ndescription: Foo things.\nallowed-tools: Bash(*)\n---\n\nDo foo.\nAnd more.\n' >"$UP/skills/foo/SKILL.md"
mkdir -p "$UP/skills/foo/scripts"; printf '#!/bin/sh\n' >"$UP/skills/foo/scripts/run.sh"
printf '#!/bin/sh\n' >"$UP/skills/foo/scripts/run"; chmod +x "$UP/skills/foo/scripts/run"
printf -- '---\nname: bar\ndescription: Bar reviewer.\n---\n\nReview bar, differently.\n' >"$UP/agents/bar.md"
upcommit change
expect_exit 1 "an imported item changed upstream: check exits 1" -- "${IKKIT[@]}" import --check
check "it shows the changed skill with its line counts" \
  'grep -q "~ skill/foo: SKILL.md +2 -0, scripts/run (new) +1, scripts/run.sh (new) +1" <<<"$out"'
check "it flags the frontmatter key that changed" 'grep -q "⚠ frontmatter changed: allowed-tools" <<<"$out"'
check "a body-only change raises no ⚠" '! grep -A1 "~ agent/bar" <<<"$out" | grep -q "⚠"'
check "it flags the new scripts, an extensionless executable included" \
  'grep -q "⚠ script added or changed: scripts/run, scripts/run.sh" <<<"$out"'
check "it names what cites the skill, without repeating its extender" 'grep -q "cited by: src/instructions/10-probe.md$" <<<"$out"'
check "it names the local skill that extends the changed skill" 'grep -q "extended by: ourfoo" <<<"$out"'
check "it names the local agent that extends the changed agent" 'grep -q "extended by: agent:review:code" <<<"$out"'
check "check writes nothing" 'snap | cmp -s - "$TMP/snap-before"'
sed -i.bak 's/^  fetched: .*/  fetched: KEEP/' "$IK/kit.lock"; rm -f "$IK/kit.lock.bak"
expect_exit 0 "import without --update stays on the pin" -- "${IKKIT[@]}" import
check "an import that keeps its commit keeps its fetched date" 'grep -q "fetched: KEEP" "$IK/kit.lock"'
expect_exit 0 "update" -- "${IKKIT[@]}" import --update
check "update prints the summary and where to read the diff" \
  'grep -q "~ agent/bar: bar.md +1 -1" <<<"$out" && grep -q "review: git diff -- vendor/up" <<<"$out"'
check "the summary counts both scripts" 'grep -q "^up: .* — 2 script/asset file(s), review them" <<<"$out"'
check "update moves the pin and the fetched date" \
  'grep -q "commit: $(git -C "$UP" rev-parse HEAD)" "$IK/kit.lock" && ! grep -q "fetched: KEEP" "$IK/kit.lock"'
printf 'x\n' >>"$UP/README.md"; git -C "$UP" commit -q -a --amend -m rewrite
expect_exit 1 "the pinned commit rewritten off its ref: check exits 1" -- "${IKKIT[@]}" import --check
check "it says the pin left the ref, with no item changed" \
  'grep -q "^up: pinned commit is no longer on main" <<<"$out" && ! grep -q "^  [-+~] " <<<"$out"'
expect_exit 0 "update onto the rewritten ref" -- "${IKKIT[@]}" import --update
git -C "$UP" rm -q -r skills/foo agents/bar.md; upcommit "drop foo and bar"
expect_exit 1 "a skill removed upstream: check exits 1" -- "${IKKIT[@]}" import --check
check "it says removed and who still cites it" \
  'grep -q -- "- skill/foo (removed upstream)" <<<"$out" && grep -q "cited by: src/instructions/10-probe.md" <<<"$out"'
check "a removed item extended locally: it says kit check will fail on the extender" \
  'grep -q -- "- agent/bar (removed upstream)" <<<"$out" && grep -q "kit check will fail on: agent:review:code" <<<"$out" && ! grep -q "extended by" <<<"$out"'
expect_exit 2 "--check and --update together are refused" -- "${IKKIT[@]}" import --check --update
git -C "$UP" tag -a v1 -m v1
sed -i.bak 's/^    ref: main$/    ref: v1/' "$IK/kit.yaml"; rm -f "$IK/kit.yaml.bak"
expect_exit 0 "update onto an annotated tag" -- "${IKKIT[@]}" import --update
expect_exit 0 "an annotated tag ref: check right after the update passes" -- "${IKKIT[@]}" import --check
check "it says up to date on the tag" 'grep -q "^up: up to date" <<<"$out"'
sed -i.bak "s#^    source: file://$UP\$#    source: file://$UP/.git#" "$IK/kit.yaml"
expect_exit 1 "a source changed in kit.yaml: check exits 1" -- "${IKKIT[@]}" import --check
check "it says the source changed, not that it was never imported" 'grep -q "^up: source changed in kit.yaml" <<<"$out"'
mv "$IK/kit.yaml.bak" "$IK/kit.yaml"
git clone -q "$UP" "$TMP/gone"; mkdir -p "$TMP/locsrc"
printf '%s\n' '  - name: gone' "    source: file://$TMP/gone" '  - name: loc' "    source: $TMP/locsrc" >>"$IK/kit.yaml"
expect_exit 0 "import a second upstream" -- "${IKKIT[@]}" import gone
rm -rf "$TMP/gone"
expect_exit 3 "an upstream that cannot be fetched: check exits 3, not 1" -- "${IKKIT[@]}" import --check
check "it reports the failure and still checks the imports after it" \
  'grep -q "^gone: check failed" <<<"$out" && grep -q "^loc: local source, nothing pinned" <<<"$out" && grep -q "^up: up to date" <<<"$out"'
mkdir -p "$UP/skills/foo"; printf -- '---\nname: foo\ndescription: Foo.\n---\n\nBack.\n' >"$UP/skills/foo/SKILL.md"
upcommit back; git -C "$UP" tag -f -a v1 -m v1 >/dev/null
expect_exit 3 "a failed check wins over a moved import" -- "${IKKIT[@]}" import --check
check "it reports both the failure and the moved item" 'grep -q "^gone: check failed" <<<"$out" && grep -q "+ skill/foo" <<<"$out"'
printf -- '---\nname: foo\ndescription: Foo.\n---\n\n\377\n' >"$UP/skills/foo/SKILL.md"
upcommit broken; git -C "$UP" tag -f -a v1 -m v1 >/dev/null
expect_exit 3 "upstream content Python cannot read: check exits 3, not 1" -- "${IKKIT[@]}" import --check
check "it says why on stderr, reports the failure and still checks the imports after it" \
  'grep -q UnicodeDecodeError "$TMP/err" && grep -q "^up: check failed" <<<"$out" && grep -q "^loc: local source, nothing pinned" <<<"$out"'
expect_exit 3 "an unknown NAME under --check exits 3, not 1" -- "${IKKIT[@]}" import --check nosuch
expect_exit 1 "an unknown NAME without --check still exits 1" -- "${IKKIT[@]}" import nosuch
expect_exit 0 "check NAME on a local source" -- "${IKKIT[@]}" import --check loc
check "it says nothing is pinned and checks only that import" \
  'grep -q "^loc: local source, nothing pinned" <<<"$out" && ! grep -q "^up:" <<<"$out"'

in_dir() { (cd "$1" && shift && "$@"); }
# shellcheck disable=SC2034  # SBR is read by check's eval; bin/kit resolves its root (/var is /private/var on macOS)
SBR="$(cd "$SB" && pwd -P)"

echo "build"
sed -i.bak 's/^version: .*/version: 9.8.7/' "$SB/kit.yaml"; rm -f "$SB/kit.yaml.bak"
# shellcheck disable=SC2034  # NAME is read by check's eval on the next lines
NAME="$(sed -n 's/^name: //p' "$SB/kit.yaml")"
mkdir -p "$SB/dist"; echo stray >"$SB/dist/stray.md"
expect_exit 0 "build the sandbox" -- env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" build
check "the plugin manifest carries kit.yaml's name and version" \
  'jq -e --arg n "$NAME" ".name == \$n and .version == \"9.8.7\"" "$SB/dist/claude-plugin/.claude-plugin/plugin.json" >/dev/null'
check "the marketplace lists that plugin from ./dist/claude-plugin" \
  'jq -e --arg n "$NAME" ".name == \$n and (.plugins | length) == 1 and .plugins[0].name == \$n and .plugins[0].version == \"9.8.7\" and .plugins[0].source == \"./dist/claude-plugin\"" "$SB/.claude-plugin/marketplace.json" >/dev/null'
check "a file left in dist/ by an earlier build is gone" '[ ! -e "$SB/dist/stray.md" ]'
digest() { (cd "$SB" && find dist .claude-plugin -type f -exec shasum {} + | sort); }
digest >"$TMP/build-1"
expect_exit 0 "build it again" -- env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" build
check "... byte-identical" 'digest | cmp -s - "$TMP/build-1"'
cp "$ROOT/kit.yaml" "$SB/kit.yaml"
expect_exit 0 "rebuild with the real kit.yaml, so no 9.8.7 is left for the next sections" -- env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" build

echo "new"
NEW=(env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" new)
expect_exit 0 "new agent family:specialty" -- "${NEW[@]}" agent feat:probe
check "... writes src/agents/<family>/<specialty>.md, its name left to the path" \
  'grep -q "^description:" "$SB/src/agents/feat/probe.md" && ! grep -q "^name:" "$SB/src/agents/feat/probe.md"'
out="$(ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check 2>&1)"; got=$?
if [ "$got" != 0 ] && grep -q "orphan agent 'agent:feat:probe': no area role, fallback or entry names it" <<<"$out" \
  && [ "$(grep -c "^error: " <<<"$out")" = 1 ]; then ok "a starter agent's only error is being an orphan"
else ko "a starter agent's only error is being an orphan" "exit $got: $(tail -c 300 <<<"$out")"; fi
echo mine >>"$SB/src/agents/feat/probe.md"
expect_exit 1 "new on an existing agent is refused" -- "${NEW[@]}" agent feat:probe
check "... and leaves the file as it was" 'grep -q "already exists" "$TMP/err" && tail -n 1 "$SB/src/agents/feat/probe.md" | grep -qx mine'
rm -f "$SB/src/agents/feat/probe.md"
expect_exit 0 "new agent without a family" -- "${NEW[@]}" agent probe-solo
check "... writes src/agents/<name>.md and keeps its name" 'grep -qx "name: probe-solo" "$SB/src/agents/probe-solo.md"'
rm -f "$SB/src/agents/probe-solo.md"
expect_exit 0 "new workflow domain:action" -- "${NEW[@]}" workflow dom:act
check "... writes src/workflows/<domain>/<action>.md with the {{args}} input" \
  'grep -qx "Input: {{args}}" "$SB/src/workflows/dom/act.md" && ! grep -q "^name:" "$SB/src/workflows/dom/act.md"'
expect_exit 0 "a starter workflow passes the public check" -- env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check
rm -rf "$SB/src/workflows/dom"
expect_exit 0 "new skill" -- "${NEW[@]}" skill probe-skill
check "... writes src/skills/<name>/SKILL.md named after it" 'grep -qx "name: probe-skill" "$SB/src/skills/probe-skill/SKILL.md"'
expect_exit 0 "a starter skill passes the public check" -- env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" check
rm -rf "$SB/src/skills/probe-skill"
find "$SB/src" | sort >"$TMP/src-before"
refused() {  # refused NAME KIND ITEM — kit new must refuse the name, saying why, without crashing
  expect_exit 1 "$1" -- "${NEW[@]}" "$2" "$3"
  check "... saying why" 'grep -q "^kit: name: lowercase-with-hyphens" "$TMP/err" && ! grep -q Traceback "$TMP/err"'
}
refused "new with a name that is not lowercase-with-hyphens is refused" skill Bad_Name
refused "new skill with a group is refused" skill grp:name
refused "new agent with three parts is refused" agent a:b:c
check "... none of them writes a file" 'find "$SB/src" | sort | cmp -s - "$TMP/src-before"'
find "$SB/src" | sort | comm -13 "$TMP/src-before" - | while IFS= read -r f; do rm -rf "$f"; done  # what a regression wrote

echo "import from a local path"
mkdir -p "$SB/probe-src/skills/probe-skill" "$SB/probe-src/agents"
printf -- '---\nname: probe-skill\ndescription: A probe skill.\n---\n\nProbe.\n' >"$SB/probe-src/skills/probe-skill/SKILL.md"
printf -- '---\nname: probe-agent\ndescription: A probe agent.\ntools: [Read, Grep, Glob]\nmodel: opus\n---\n\nProbe.\n' \
  >"$SB/probe-src/agents/probe-agent.md"
printf -- '---\nname: nodesc\n---\n\nNo description.\n' >"$SB/probe-src/agents/nodesc.md"
printf '%s\n' '  - name: probe' '    source: ./probe-src' '    include: [skills/probe-skill, agents/*.md]' >>"$SB/kit.yaml"
expect_exit 0 "import a relative local source, run from outside the kit" -- in_dir "$TMP" env ADORNO_LOCAL="$TMP/none" "${SBKIT[@]}" import probe
check "... resolves it against the kit root and writes the skill and the agent under vendor/<name>/" \
  '[ -f "$SB/vendor/probe/skills/probe-skill/SKILL.md" ] && [ -f "$SB/vendor/probe/agents/probe-agent.md" ]'
check "an imported agent's native tools and model become neutral" \
  'grep -qx -- "- read" "$SB/vendor/probe/agents/probe-agent.md" && [ "$(grep -cx -- "- search" "$SB/vendor/probe/agents/probe-agent.md")" = 1 ] && grep -qx "model: deep" "$SB/vendor/probe/agents/probe-agent.md" && ! grep -q "Grep\|opus" "$SB/vendor/probe/agents/probe-agent.md"'
check "an .md without a description is skipped, with a warning" \
  '[ ! -e "$SB/vendor/probe/agents/nodesc.md" ] && grep -q "probe: skipped agents/nodesc.md (no description in frontmatter)" "$TMP/err"'
lock_entry() { awk -v n="$1:" '$0 == n { f = 1; next } /^[^ ]/ { f = 0 } f' "$SB/kit.lock"; }
check "kit.lock pins it as local, with its source and items" \
  'lock_entry probe | grep -qx "  commit: local" && lock_entry probe | grep -qx "  source: ./probe-src" && [ "$(lock_entry probe | grep "^  - ")" = "$(printf "  - agent/probe-agent\n  - skill/probe-skill")" ]'
check "the other imports' entries are kept as they were" \
  'awk "/^probe:/ { f = 1; next } /^[^ ]/ { f = 0 } !f" "$SB/kit.lock" | cmp -s - "$ROOT/kit.lock"'
rm -rf "$SB/vendor/probe" "$SB/probe-src"; cp "$ROOT/kit.yaml" "$SB/kit.yaml"; cp "$ROOT/kit.lock" "$SB/kit.lock"

echo "install --link"
L="$TMP/linked"; mkrepo "$L" acme/linked
expect_exit 1 "--link with the personal layer on is refused" -- "${SBKIT[@]}" install "$L" --link --targets claude
check "... saying why, before writing anything" \
  'grep -q -- "--link points to the public dist/" "$TMP/err" && [ ! -e "$L/.claude" ] && [ ! -e "$L/.adorno" ]'
rm -rf "$SB/dist/claude"
expect_exit 0 "--link --public-only" -- "${SBKIT[@]}" install "$L" --link --public-only --targets claude
link_targets() {
  jq -r '.files | keys[]' "$L/.adorno/installed.json" | while IFS= read -r f; do
    if [ -L "$L/$f" ]; then readlink "$L/$f"; else echo "not a link: $f"; fi
  done
}
check "every installed file is a symlink into the kit's dist/claude/" \
  '[ -n "$(link_targets)" ] && ! link_targets | grep -v "^$SBR/dist/claude/"'
check "... and resolves: --link rebuilt dist/ first" '[ -f "$L/.claude/agents/adorno.md" ] && [ -z "$(find -L "$L/.claude" -type l)" ]'
expect_exit 0 "uninstall a linked install" -- "${SBKIT[@]}" uninstall "$L"
check "... removes every link and leaves the kit's dist/ in place" \
  '[ -z "$(find "$L" -path "$L/.git" -prune -o -type l -print)" ] && [ ! -e "$L/.claude/agents" ] && [ ! -e "$L/.adorno" ] && [ -f "$SB/dist/claude/.claude/agents/adorno.md" ]'

echo "install --dry-run"
R="$TMP/dry"; mkrepo "$R" acme/dry
DH="$TMP/dry-home"; mkdir -p "$DH"  # an empty home: a real install would write ~/.adorno/registry.json into it
tree_of() { (cd "$R" && find . -path ./.git -prune -o -print | sort && cat .git/info/exclude 2>/dev/null); find "$DH" | sort; }
tree_of >"$TMP/dry-before"
expect_exit 0 "install --dry-run" -- env HOME="$DH" "${KIT[@]}" install "$R" --targets claude --dry-run
check "it lists the files it would write, the managed block and the guard hook" \
  'grep -q "^would install [1-9][0-9]* file(s) into .*/dry for claude$" <<<"$out" && grep -qx "  + .claude/agents/adorno.md" <<<"$out" && grep -qx "  ~ CLAUDE.md (managed block)" <<<"$out" && grep -q "hooks.PreToolUse.*: adorno guard$" <<<"$out"'
check "... and writes nothing: the repo, its .git/info/exclude and the home are unchanged" 'tree_of | cmp -s - "$TMP/dry-before"'

echo "conf without a repo"
expect_exit 0 "conf outside any repo" -- in_dir "$TMP" "${KIT[@]}" conf
check "it lists the scopes, weakest first, then the presets" \
  '[ "$(sed -n "s/^  \([a-z]*\).*/\1/p" <<<"$out" | uniq | tr "\n" " ")" = "defaults workspaces repos presets " ]'
check "... each one by name" \
  'grep -q "^scopes (weakest first" <<<"$out" && grep -q "^  workspaces.acme: " <<<"$out" && grep -qx "  repos.acme/app" <<<"$out" && grep -qx "  presets.platform-team (used with \`use:\`)" <<<"$out"'
expect_exit 0 "conf with no argument inside a declared repo" -- in_dir "$TMP/code/acme/app" "${KIT[@]}" conf
expect_jq "... resolves that repo" '(.scopes | index("repos:acme/app")) != null'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
