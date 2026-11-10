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
bad "a commit_skill that is not a name" $'  ghost/repo:\n    commit_skill: [a, b]' "commit_skill must be a skill or command name"
bad "a pr_skill with a shell command" $'  ghost/repo:\n    pr_skill: "gh pr create"' "pr_skill must be a skill or command name"
bad "unknown notion_spec step" $'  ghost/repo:\n    notion_spec: {merged: {Lifecycle: Done}}' "unknown step 'merged'"
bad "non-scalar notion_spec value" $'  ghost/repo:\n    notion_spec: {start: {Lifecycle: [a, b]}}' "must be a string, a number, a boolean or null"
bad "unknown notion_spec placeholder" $'  ghost/repo:\n    notion_spec: {pr_opened: {PR: "{{pr-url}}"}}' "unknown placeholder"
bad "pr_url before the PR" $'  ghost/repo:\n    notion_spec: {start: {PR: "{{pr_url}}"}}' "only exists once the PR is open"
bad "a commit_skill with a trailing newline" $'  ghost/repo:\n    commit_skill: "adorno-commit\\n"' "commit_skill must be a skill or command name"
bad "an empty setup_skill" $'  ghost/repo:\n    setup_skill: ""' "setup_skill must be a skill or command name"
bad "a pr_skill with a path" $'  ghost/repo:\n    pr_skill: "../x"' "pr_skill must be a skill or command name"
bad "unknown denied action" $'  ghost/repo:\n    permissions: {deny: [merge]}' "unknown action 'merge'"
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
check "no personal registry inside the repo" '! grep -rq "janedoe" "$A/.claude/skills/adorno-github/repos.json"'
check "SCHEMA.md is neither an item nor shipped" '[ -f "$ROOT/src/agents/review/SCHEMA.md" ] && [ -z "$(find "$A/.claude" "$A/.codex" -iname "*schema*" 2>/dev/null)" ]'
check "your own rules and keys are kept" 'jq -e ".model == \"x\" and (.permissions.allow | index(\"Bash(make:*)\")) != null" "$A/.claude/settings.local.json" >/dev/null'
check "the repo's and the default rules are added" 'jq -e "(.permissions.allow | index(\"Bash(npm test:*)\")) != null and (.permissions.deny | index(\"Bash(gh pr merge:*)\")) != null" "$A/.claude/settings.local.json" >/dev/null'
check "the guard hook refuses direct writes in this repo" 'jq -e "[.hooks.PreToolUse[].hooks[].command | select(contains(\"guard_bash.py\") and contains(\" deny --format=claude\"))] | length == 1" "$A/.claude/settings.local.json" >/dev/null'
check "Codex gets the same hook" 'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"^Bash$\") | .hooks[].command | select(contains(\"--format=codex\"))] | length == 1" "$A/.codex/hooks.json" >/dev/null'
HOOK="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$A/.claude/settings.local.json")"
got="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git -C x push"}}' | sh -c "$HOOK" | jq -r .hookSpecificOutput.permissionDecision)"
check "the installed hook runs and refuses" '[ "$got" = deny ]'
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | PATH=/nonexistent /bin/sh -c "$HOOK" 2>/dev/null; got=$?
check "without python3 the hook blocks (exit 2), it does not let commands through" '[ "$got" = 2 ]'
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
cp "$ROOT/dist/claude/.claude/skills/adorno-commit/SKILL.md" "$B/.claude/skills/adorno-commit/SKILL.md"
expect_exit 0 "install next to an identical file of yours" -- "${KIT[@]}" install "$B" --targets claude
expect_exit 0 "uninstall" -- "${KIT[@]}" uninstall "$B"
check "your identical file survives uninstall" '[ -f "$B/.claude/skills/adorno-commit/SKILL.md" ]'

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
"${KIT[@]}" uninstall "$TMP/newco/svc" --force >/dev/null
cp "$TMP/layer.bak" "$ADORNO_LOCAL/adorno.yaml"

echo "uninstall"
expect_exit 0 "uninstall the repo" -- "${KIT[@]}" uninstall "$A" --force
check "agents gone" '[ ! -e "$A/.claude/agents" ]'
check "exclude block gone" '! grep -q "adorno:begin" "$(git -C "$A" rev-parse --git-path info/exclude)"'
check "the Codex hook file is gone" '[ ! -e "$A/.codex/hooks.json" ]'
check "the hook is gone" '! jq -e ".hooks" "$A/.claude/settings.local.json" >/dev/null'
check "your settings are back as they were" 'jq -e ".model == \"x\" and .permissions.allow == [\"Bash(make:*)\"] and (.permissions.deny == null)" "$A/.claude/settings.local.json" >/dev/null'

echo "global install"
expect_exit 0 "install --global" -- "${KIT[@]}" install --global --targets claude,codex,gemini
check "Codex asks before direct writes (its own rules)" 'grep -q "prefix_rule(pattern=\[\"git\", \"push\"\], decision=\"prompt\"" "$HOME/.codex/rules/adorno.rules"'
check "Gemini asks too (its policy engine)" 'grep -q "decision = \"ask_user\"" "$HOME/.gemini/policies/adorno.toml" && grep -q "\"gh pr comment\"" "$HOME/.gemini/policies/adorno.toml"'
check "in your user settings, direct shell writes ask (they apply to every project)" 'jq -e "(.permissions.ask | index(\"Bash(gh pr comment:*)\")) != null and ((.permissions.deny // []) | index(\"Bash(gh pr comment:*)\")) == null" "$HOME/.claude/settings.json" >/dev/null'
check "the global guard hook asks" 'jq -e "[.hooks.PreToolUse[].hooks[].command | select(contains(\"guard_bash.py\") and contains(\" ask --format=claude\"))] | length == 1" "$HOME/.claude/settings.json" >/dev/null'
check "... and edits of adorno's files stay denied" 'jq -e "(.permissions.deny | index(\"Edit(~/.adorno/registry.json)\")) != null" "$HOME/.claude/settings.json" >/dev/null'
expect_exit 0 "dry run of --global" -- "${KIT[@]}" install --global --targets claude --dry-run
check "... names your user settings" 'grep -q "~/.claude/settings.json" <<<"$out"'
expect_exit 0 "a project next to a global install" -- "${KIT[@]}" install "$A" --targets claude
check "takes its instructions from the global one" '[ ! -e "$A/.claude/rules/adorno.md" ] && [ ! -e "$A/AGENTS.md" ]'
"${KIT[@]}" uninstall "$A" --force >/dev/null
expect_exit 0 "uninstall --global" -- "${KIT[@]}" uninstall --global
check "rules removed from your user settings" '[ ! -e "$HOME/.claude/settings.json" ] || ! jq -e ".permissions.deny // .permissions.ask" "$HOME/.claude/settings.json" >/dev/null'
check "the Codex and Gemini rules are removed" '[ ! -e "$HOME/.codex/rules/adorno.rules" ] && [ ! -e "$HOME/.gemini/policies/adorno.toml" ]'
check "the registry is removed" '[ ! -e "$ADORNO_HOME/registry.json" ]'

echo "workspace install"
expect_exit 0 "install --workspace" -- "${KIT[@]}" install --workspace acme --targets claude
check "every repo of the workspace" '[ -f "$TMP/code/acme/app/.claude/agents/adorno.md" ] && [ -f "$TMP/code/acme/web/.claude/agents/adorno.md" ]'
expect_exit 0 "uninstall --workspace" -- "${KIT[@]}" uninstall --workspace acme --force

echo "the public build never sees the personal layer"
check "dist/ has no template identity" '! grep -rq "janedoe" "$ROOT/dist"'

echo "areas, entry and orphans"
bad "an area role naming an unknown agent" $'  ghost/repo:\n    areas: {back: {build: "agent:feat:nope"}}' "areas.back.build names unknown agent 'agent:feat:nope'"
bad "a role outside its families" $'  ghost/repo:\n    areas: {back: {build: "agent:review:code"}}' "not a feat/test/docs/chore agent"
bad "an unknown skill in an area" $'  ghost/repo:\n    areas: {back: {skills: [no-such-skill]}}' "unknown skill 'no-such-skill'"
bad "an unknown area key" $'  ghost/repo:\n    areas: {back: {reviewers: []}}' "areas.back.reviewers: unknown key"
bad "a nested sub-area" $'  ghost/repo:\n    areas: {back: {sub: {q: {sub: {x: {}}}}}}' "areas.back.sub.q.sub: unknown key"
bad "a role in always other than review and skills" $'  ghost/repo:\n    areas: {always: {build: "agent:feat:back"}}' "areas.always.build: unknown key"
bad "an invalid content regex" $'  ghost/repo:\n    areas: {back: {content: "(unclosed"}}' "areas.back.content is an invalid regex"
bad "a content regex awk cannot run" $'  ghost/repo:\n    areas: {back: {content: "(?i)token"}}' "areas.back.content is an invalid regex"
bad "an unknown fallback" $'  ghost/repo:\n    fallbacks: {lint: "agent:fix:patch"}' "fallbacks.lint: unknown key"
bad "area_reviewers is refused with the migration hint" $'  ghost/repo:\n    area_reviewers: {docs: ["agent:review:security"]}' "bin/kit migrate areas"
OKL="$TMP/okl"; mkdir -p "$OKL"
printf 'owner: {name: T, github: t, language: fr}\nrepos:\n  ghost/repo:\n    areas: {back: {review: ["-agent:review:tests"]}}\n' >"$OKL/adorno.yaml"
expect_exit 0 "a removal entry (-x) is accepted" -- env ADORNO_LOCAL="$OKL" "${KIT[@]}" check

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
expect_exit 0 "the real registry passes with every dispatcher's roles covered" -- env ADORNO_LOCAL="$TMP/none" "${KIT[@]}" check
check "no area_reviewers reader is left in src/" '! grep -rn "area_reviewers" "$ROOT/src" "$ROOT/bin/kit" | grep -v -e "src/skills/adorno-setup/" -e "bin/kit:.*AREA_REVIEWERS_MSG\|bin/kit:.*area_reviewers" -e SCHEMA.md | grep .'
check "pr:ship leaves no family agent of its subject" '! grep -q "family agent of its subject" "$ROOT/src/workflows/pr/ship.md"'
check "entry never reaches a rendered agent" '! grep -rq "^entry:" "$ROOT/dist" --include=*.md --include=*.toml'

echo "migrate areas"
MIG="$TMP/mig"; mkdir -p "$MIG"
printf '%s\n' 'owner: {name: T, github: t, language: fr}' 'repos:' '  acme/app:' '    area_reviewers:' \
  '      docs: [agent:review:security]' '      api: [agent:review:api, agent:review:security]' \
  '      mongodb: [agent:review:mongodb, agent:review:back]' '      always: [agent:review:code]' \
  '      front: [agent:review:code]' >"$MIG/adorno.yaml"
cp "$MIG/adorno.yaml" "$TMP/mig-before.yaml"
out="$(ADORNO_LOCAL="$MIG" "${KIT[@]}" migrate areas 2>"$TMP/err")"; got=$?
check "migrate areas succeeds although check fails" '[ "$got" = 0 ] && ! ADORNO_LOCAL="$MIG" "${KIT[@]}" check >/dev/null 2>&1'
expect_jq "docs: the old list is all additions" '[.[] | select(.area_path == "areas.docs.review")][0].new == ["agent:review:security"]'
expect_jq "api: only the addition remains" '[.[] | select(.area_path == "areas.api.review")][0].new == ["agent:review:security"]'
expect_jq "mongodb maps to both back sub-areas, nothing to add over the inherited reviewers" \
  '([.[] | select(.area_path == "areas.back.sub.mongodb.review" or .area_path == "areas.back.sub.query.review")] | length == 2 and all(.new == [] and .scope == "repos.acme/app"))'
expect_jq "always: a public reviewer missing from the old list becomes a removal" \
  '[.[] | select(.area_path == "areas.always.review")][0].new == ["-agent:review:ponytail"]'
expect_jq "an area omitting a public reviewer gets its -x" \
  '[.[] | select(.area_path == "areas.front.review")][0].new == ["agent:review:code", "-agent:review:front", "-agent:review:perf"]'
check "migrate prints a YAML snippet per scope" 'grep -q "repos:" "$TMP/err" && grep -q "areas:" "$TMP/err"'
check "migrate writes nothing" 'cmp -s "$MIG/adorno.yaml" "$TMP/mig-before.yaml" && [ "$(ls "$MIG")" = "adorno.yaml" ]'

check "review:security opens with a step 0 qualification and a one-line pass" \
  'grep -q "Step 0, qualification" "$ROOT"/dist/claude/.claude/agents/adorno-agent-review-security.md && grep -q "one line" "$ROOT"/dist/claude/.claude/agents/adorno-agent-review-security.md'

check "no _family.md hard-codes typescript-pro" '! grep -l "typescript-pro" "$ROOT"/src/agents/*/_family.md'
check "the skills-by-area rule appears once in the orchestration instructions" \
  '[ "$(grep -c "Skills by area" "$ROOT"/src/instructions/10-orchestration.md)" = 1 ]'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
