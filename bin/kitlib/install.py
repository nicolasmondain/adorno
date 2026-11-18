"""Commands install, uninstall, journal and serve."""

from __future__ import annotations

import copy
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from kitlib import ctx
from kitlib.paths import BEGIN, BLOCK_RE, CLAUDE_RULES, DIST, END, LOCAL, LOCAL_CONF, ROOT, STATE
from kitlib.util import as_list, die, rel, sha, warn
from kitlib.registry import github_repo, local_conf, local_on, registry, resolve_repo, workspace_dirs
from kitlib.model import Config, Item
from kitlib.render import build_target, global_path, managed_files, render_instructions
from kitlib.build import build_all
from kitlib.commands import load_valid


def load_state(dest: Path) -> dict:
    p = dest / STATE
    return json.loads(p.read_text()) if p.exists() else {"files": {}, "managed": {}}


def upsert_block(path: Path, text: str) -> None:
    block = f"{BEGIN}\n{text.strip()}\n{END}\n"
    if path.exists():
        cur = path.read_text(encoding="utf-8")
        new = BLOCK_RE.sub(lambda _: block, cur, count=1) if BLOCK_RE.search(cur) \
            else cur.rstrip() + ("\n\n" if cur.strip() else "") + block
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        new = block
    path.write_text(new, encoding="utf-8")


def remove_block(path: Path, created: bool, root: Path) -> None:
    if not path.exists():
        return
    rest = BLOCK_RE.sub("", path.read_text(encoding="utf-8")).rstrip()
    if not rest and created:
        path.unlink()
        prune(path, root)
    else:
        path.write_text(rest + "\n" if rest else "", encoding="utf-8")


def prune(path: Path, stop: Path) -> None:
    d = path.parent
    while d != stop and d.is_dir() and not any(d.iterdir()):
        d.rmdir()
        d = d.parent


def remove_owned(dest: Path, path: str, digest: str, force: bool) -> bool:
    p = dest / path
    if p.is_symlink():
        p.unlink()
    elif p.exists():
        if sha(p.read_bytes()) != digest and not force:
            warn(f"kept {path}: modified since install (use --force to remove)")
            return False
        p.unlink()
    prune(p, dest)
    return True


def models_for(dest: Path | None) -> dict:
    """`models` the personal layer resolves for the repo at `dest` (its defaults for --global or a non-repo)."""
    if not local_on():
        return {}
    reg = registry()
    repo = github_repo(dest) if dest else None
    conf = resolve_repo(reg, repo) if repo else None
    if conf is None:
        conf = reg.get("defaults") or {}
    return dict(conf.get("models") or {})


def route_spec(models: dict, item_id: str) -> tuple[str, dict] | None:
    """The external route an agent is sent to, if any (and if the repo allows external models)."""
    spec = (models.get("agents") or {}).get(item_id)
    if not isinstance(spec, dict) or not spec.get("route") or models.get("external") is False:
        return None
    name = str(spec["route"])
    route = (models.get("routes") or {}).get(name)
    if not route:
        die(f"models.agents.{item_id}: unknown route '{name}'")
    return name, route


def apply_models(items: dict, models: dict) -> dict:
    """A copy of the items with the personal layer's model choices applied: tier or native model per agent and per
    workflow, and agents sent to an external route rewritten as a thin host agent that delegates to it."""
    if not models:
        return items
    out = copy.deepcopy(items)
    for kind, key in (("agent", "agents"), ("workflow", "workflows")):
        for it in out[kind].values():
            spec = (models.get(key) or {}).get(it.id)
            if isinstance(spec, str):
                it.meta["model"] = spec
            elif isinstance(spec, dict) and (spec.get("tier") or spec.get("model")):
                it.meta["model"] = spec.get("model") or spec.get("tier")
            if kind == "agent":
                routed = route_spec(models, it.id)
                if routed:
                    delegate(it, *routed)
    return out


def delegate(it: Item, name: str, route: dict) -> None:
    """Rewrite an agent so the host runs it cheaply and the judgment happens on an external model."""
    if not it.meta.get("delegable"):
        die(f"{it.id} cannot be sent to route '{name}': it is not `delegable` (it needs tools while it thinks)")
    flags = (f"--base-url {route['base_url']} --model {route['model']} --key-env {route.get('api_key_env', 'OPENROUTER_API_KEY')}")
    if route.get("max_tokens"):
        flags += f" --max-tokens {route['max_tokens']}"
    it.meta["model"] = route.get("host_tier", "fast")
    it.meta["tools"] = sorted(set(as_list(it.meta.get("tools")) or []) | {"read", "write", "search", "shell"})
    it.body = f"""## Role delegated to model `{route['model']}` (route `{name}`)

This role's judgment runs on an external model, not on this session's. You prepare and you verify, with the
`adorno-llm` skill:

1. Gather the inputs the instructions below describe (files, diff, script outputs) with your tools, without judging
   yourself. Nothing secret or personal: an input that contains any is trimmed or removed.
2. In a folder of your own (`d="$(mktemp -d)"`: other delegates may be running at the same time), write
   `$d/role.md` (the "Role instructions" section, in full) and `$d/prompt.md` (the task and the inputs).
3. `adorno-llm/scripts/llm-run {flags} --system "$d/role.md" "$d/prompt.md" > "$d/reply.json"`
4. Check `$d/reply.json` › `.content`: expected format respected, every cited `file:line` exists. Otherwise, one retry
   with the error; a second failure or an unavailable route → do the work yourself and flag it.
5. Write the expected deliverable from the reply; note `model` and `usage` in the report.

## Role instructions

{it.body.strip()}
"""


def kit_home() -> Path:
    """~/.adorno, where the scripts read the registry and the runs. No variable moves it (the scripts would not follow)."""
    return Path.home() / ".adorno"


def write_registry() -> Path | None:
    """The personal registry, read by every script at runtime: ~/.adorno/registry.json, outside every repo, read-only
    (agents edit it only by going out of their way). Nothing to write without the personal layer."""
    if not local_on():
        return None
    path = kit_home() / "registry.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.chmod(0o600)
    data = registry()
    # where it comes from: the scripts warn when this file is newer than the registry (an install was forgotten)
    data["_layer"] = {"file": str(LOCAL / "adorno.yaml"), "kit": str(ROOT)}
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False, default=str) + "\n")
    path.chmod(0o400)
    return path


def git_dir_file(dest: Path, name: str) -> Path | None:
    """`.git/<name>` of the repository at dest (worktrees included), or None outside git."""
    res = subprocess.run(["git", "-C", str(dest), "rev-parse", "--git-path", name], capture_output=True, text=True)
    if res.returncode != 0:
        return None
    p = Path(res.stdout.strip())
    return p if p.is_absolute() else dest / p


def is_tracked(dest: Path, path: str) -> bool:
    return subprocess.run(["git", "-C", str(dest), "ls-files", "--error-unmatch", path],
                          capture_output=True).returncode == 0


EXCLUDE_BEGIN, EXCLUDE_END = "# adorno:begin (bin/kit install: personal, never commit)", "# adorno:end"


def exclude_patterns(files: list[str], extra: list[str]) -> list[str]:
    """Anchored patterns covering what we installed: one per skill folder, one per other file."""
    out: set[str] = set()
    for f in files + extra:
        parts = Path(f).parts
        if len(parts) >= 3 and parts[1] == "skills":
            out.add("/" + "/".join(parts[:3]) + "/")
        else:
            out.add("/" + f)
    return sorted(out)


def update_exclude(dest: Path, patterns: list[str]) -> None:
    """Our block in .git/info/exclude: everything we install in a repo is invisible to git, so no `git add -A` (yours
    or an agent's) can publish your profile, registry or vision."""
    path = git_dir_file(dest, "info/exclude")
    if path is None:
        return
    cur = path.read_text() if path.exists() else ""
    cur = re.sub(rf"\n?{re.escape(EXCLUDE_BEGIN)}.*?{re.escape(EXCLUDE_END)}\n?", "\n", cur, flags=re.S).rstrip()
    if patterns:
        cur = (cur + "\n\n" if cur else "") + "\n".join([EXCLUDE_BEGIN, *patterns, EXCLUDE_END])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(cur + "\n" if cur else "")


def settings_path(dest: Path, global_: bool) -> Path:
    """Claude Code settings we manage rules in: your user settings for --global, the repo's local settings else."""
    return Path.home() / ".claude" / "settings.json" if global_ else dest / ".claude" / "settings.local.json"


def read_settings(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text() or "{}")
    except json.JSONDecodeError as e:
        die(f"{path} is not valid JSON ({e}); fix it before installing — nothing was written")
    if not isinstance(data, dict):
        die(f"{path} must contain a JSON object; nothing was written")
    return data


def install_dests(args) -> list[Path]:
    """Where to (un)install: ~ (--global), every local repo of a workspace (--workspace), or PATH."""
    if args.global_:
        return [Path.home()]
    if getattr(args, "workspace", None):
        ws = (local_conf().get("workspaces") or {}).get(args.workspace)
        if ws is None:
            die(f"no workspace '{args.workspace}' in {rel(LOCAL_CONF)}")
        dirs = list(workspace_dirs(ws).values())
        if not dirs:
            die(f"workspace '{args.workspace}': no git repository with a GitHub origin under its `paths`")
        return dirs
    return [Path(args.path).expanduser().resolve()]


def cmd_install(args) -> None:
    ctx.USE_LOCAL = not args.public_only
    if args.link and local_on():
        die("--link points to the public dist/, which has no local/: install by copy (or add --public-only)")
    cfg, items = load_valid()
    for dest in install_dests(args):
        install_into(args, cfg, items, dest)


def install_into(args, cfg: Config, items, dest: Path) -> None:
    if not dest.is_dir():
        die(f"{dest} is not a directory")
    if dest == ROOT:
        die("refusing to install the kit into itself")
    targets = args.targets.split(",") if args.targets else cfg.default_targets
    if args.link and set(targets) - set(cfg.default_targets):
        die("--link needs every target listed in kit.yaml `targets` (it links to dist/)")
    if args.link:
        build_all(cfg, items, ROOT)
    ctx.MODELS = models_for(None if args.global_ else dest)
    items = apply_models(items, ctx.MODELS)
    instructions = render_instructions(cfg, items)
    in_git = not args.global_ and git_dir_file(dest, "info/exclude") is not None
    # a project next to a global install takes its instructions from the global one (no double loading), for the
    # tools that read a global file next to the project's (Claude, Codex, Gemini), and only if that global install has
    # what this one would add (your personal layer)
    gstate = load_state(Path.home()) if not args.global_ else {}
    global_targets = set(gstate.get("targets") or []) & {"claude", "codex", "gemini"}
    if local_on() and not gstate.get("local"):
        global_targets = set()

    plan: dict[str, tuple[bytes, bool, Path]] = {}
    managed: dict[str, str] = {}
    for target in targets:
        tcfg = cfg.target(target)
        for orig, (data, exe) in build_target(cfg, target, items).items():
            path = global_path(tcfg, orig) if args.global_ else orig
            if path is None:
                continue
            if path in plan and plan[path][0] != data:
                die(f"targets disagree on {path}; adjust adapters/targets.yaml")
            plan[path] = (data, exe, DIST / target / orig)
        if target in global_targets:
            continue
        for path, text in managed_files(cfg, target, instructions, args.global_).items():
            if path in managed and managed[path] != text:
                managed[path] = instructions  # a full copy wins over a shim
            else:
                managed.setdefault(path, text)
    if args.global_:
        for path, data in global_rule_files(targets).items():
            plan[path] = (data, False, None)  # generated: written even with --link
    managed = {p: t for p, t in managed.items() if p not in plan}
    if in_git:
        # never write personal instructions into a file the repo tracks. Claude gets them as a rule file instead; a
        # shim that would import a tracked AGENTS.md (the repo's, not ours) gets the full text.
        tracked = [p for p in list(managed) if is_tracked(dest, p)]
        for path in tracked:
            managed.pop(path, None)
        if "claude" in targets and ({"CLAUDE.md", "AGENTS.md"} & set(tracked)):
            plan[".claude/rules/adorno.md"] = (instructions.encode(), False, DIST / "claude" / "AGENTS.md")
            managed.pop("CLAUDE.md", None)
        if "AGENTS.md" in tracked:
            for path in list(managed):
                if managed[path] != instructions:
                    managed[path] = instructions
            others = [t for t in targets if t not in ("claude", "gemini")]
            if others:
                warn(f"AGENTS.md is tracked by the repo: {', '.join(others)} get no adorno instructions here "
                     f"(install --global so they read them from your home)")
        for path in tracked:
            if path not in ("CLAUDE.md", "AGENTS.md"):
                warn(f"{path} is tracked by the repo: adorno's instructions are not added to it "
                     f"(install --global so that tool reads them from your home)")

    perms = claude_permissions(dest, targets, args.global_)
    env = {str(k): str(v) for k, v in (ctx.MODELS.get("claude_env") or {}).items()} \
        if "claude" in targets and not args.global_ and ctx.MODELS.get("external") is not False else {}
    if args.global_ and any(isinstance(v, dict) and v.get("route") for v in (ctx.MODELS.get("agents") or {}).values()):
        warn("models.agents in your defaults send agents to external routes in every repo; set `external: false` "
             "on the repos whose data must stay with you")
    spath = settings_path(dest, args.global_)
    hooks = {settings_rel: [h] for settings_rel, h in guards(dest, args.global_, targets, plan).items()}
    for settings_rel, more in journal_hooks(dest, args.global_, targets, plan, gstate).items():
        hooks.setdefault(settings_rel, []).extend(more)
    for settings_rel in [r for r in hooks if in_git and not args.global_ and is_tracked(dest, r)]:
        warn(f"{settings_rel} is tracked by the repo: adorno's hooks are not added to it")
        del hooks[settings_rel]
    previous_hooks = owned_hooks(load_state(dest), dest, args.global_)
    if perms or env or load_state(dest).get("permissions") or load_state(dest).get("env"):
        read_settings(spath)  # fail before writing anything
    for settings_rel in set(hooks) | set(previous_hooks):
        read_settings(dest / settings_rel)
    state = load_state(dest)
    if args.dry_run:
        shown = str(spath).replace(str(Path.home()), "~", 1) if args.global_ else str(spath.relative_to(dest))
        for k, v in env.items():
            print(f"  ! {shown} env.{k}={v}")
        for kind, rules in perms.items():
            for r in rules:
                print(f"  ! {shown} permissions.{kind}: {r}")
        for settings_rel, hs in hooks.items():
            where = "~/" + settings_rel if args.global_ else settings_rel
            for h in hs:
                print(f"  ! {where} hooks.{h['event']}" + (f" ({h['matcher']})" if h.get("matcher") else "")
                      + f": adorno {'journal' if JOURNAL_NAME in h['command'] else 'guard'}")
        stale = sorted(set(state["files"]) - set(plan))
        print(f"would install {len(plan)} file(s) into {dest} for {', '.join(targets)}")
        for p in sorted(plan):
            print(f"  + {p}")
        for p in sorted(managed):
            print(f"  ~ {p} (managed block)")
        for p in stale:
            print(f"  - {p}")
        return

    new_files: dict[str, str] = {}
    for path, digest in state["files"].items():
        if path in (state.get("adopted") or []) and path not in plan:
            continue
        if path not in plan and not remove_owned(dest, path, digest, args.force):
            new_files[path] = digest
    written = skipped = 0
    adopted = [a for a in state.get("adopted") or [] if a in plan]
    for path, (data, exe, source) in sorted(plan.items()):
        p = dest / path
        ours = path in state["files"]
        if p.exists() or p.is_symlink():
            current = p.read_bytes() if p.exists() else b""
            if not ours and current != data and not args.force:
                warn(f"skipped {path}: exists and is not managed by kit (use --force)")
                skipped += 1
                continue
            if current == data and not p.is_symlink() and not args.link:
                if not ours:
                    adopted.append(path)  # yours already, identical: tracked, but never deleted by uninstall
                new_files[path] = sha(data)
                continue
            if ours and not p.is_symlink() and sha(current) != state["files"][path] and not args.force:
                warn(f"skipped {path}: you modified it since install (use --force)")
                new_files[path] = state["files"][path]
                skipped += 1
                continue
            p.unlink()
        p.parent.mkdir(parents=True, exist_ok=True)
        if args.link and source is not None:
            p.symlink_to(source)
        else:
            p.write_bytes(data)
            if exe:
                p.chmod(p.stat().st_mode | 0o111)
        new_files[path] = sha(data)
        written += 1

    new_managed: dict[str, bool] = {}
    for path in state["managed"]:
        if path not in managed:
            remove_block(dest / path, state["managed"][path], dest)
    for path, text in managed.items():
        created = state["managed"].get(path, not (dest / path).exists())
        upsert_block(dest / path, text)
        new_managed[path] = created

    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                            capture_output=True, text=True).stdout.strip() or None
    state_path = dest / STATE
    state_path.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "kit": cfg.manifest.get("name"), "version": cfg.manifest.get("version"), "commit": commit,
        "source": str(ROOT), "targets": targets, "mode": "link" if args.link else "copy",
        "local": local_on(),
        "installed": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "files": new_files, "managed": new_managed, "adopted": sorted(set(adopted)),
        "permissions": state.get("permissions") or {}, "env": state.get("env") or {}, "hook": state.get("hook"),
    }
    state_path.write_text(json.dumps(record, indent=2) + "\n")  # files are recorded before anything else can fail
    record["permissions"] = apply_permissions(spath, perms, state.get("permissions") or {}, dest)
    record["env"] = apply_env(spath, env, state.get("env") or {}, dest)
    owned = {}
    for settings_rel in sorted(set(hooks) | set(previous_hooks)):
        got = apply_hooks(dest / settings_rel, hooks.get(settings_rel) or [], previous_hooks.get(settings_rel) or [], dest)
        if got:
            owned[settings_rel] = got
    record["hook"] = owned
    state_path.write_text(json.dumps(record, indent=2) + "\n")
    if in_git:
        # every file holding our block that the repo does not track, yours included: the block is personal
        ours = [p for p in new_managed if not is_tracked(dest, p)]
        for p in ours:
            if not new_managed[p]:
                warn(f"{p} is yours, untracked, and now holds adorno's personal block: excluded from git")
        extra = [".adorno/"] + ([".claude/settings.local.json"] if spath.exists() and not args.global_ else []) \
            + [settings_rel for settings_rel in owned
               if settings_rel != ".claude/settings.local.json" and not is_tracked(dest, settings_rel)]
        update_exclude(dest, exclude_patterns(list(new_files) + ours, extra))
    # the registry follows your personal layer: every install with it rewrites it (a tightened max_level or deny
    # applies at once, a new repo is known at once)
    if args.global_ or local_on() or not (kit_home() / "registry.json").exists():
        write_registry()
    n_rules = sum(len(r) for r in perms.values())
    print(f"installed {written} file(s) + {len(managed)} managed block(s) into {dest} "
          f"for {', '.join(targets)}" + (f", {n_rules} permission rule(s)" if n_rules else "")
          + (f" ({skipped} skipped)" if skipped else ""))




def claude_permissions(dest: Path, targets: list[str], global_: bool) -> dict[str, list[str]]:
    """`permissions.claude` to write as native Claude Code rules: the defaults (public ones included: no direct
    `git push` or `gh` writes) for --global, the repo's resolved rules for a repo."""
    if "claude" not in targets:
        return {}
    reg = registry()
    conf = None
    if not global_:
        repo = github_repo(dest)
        conf = resolve_repo(reg, repo) if repo and local_on() else None
    if conf is None:
        conf = reg.get("defaults") or {}
    rules = (conf.get("permissions") or {}).get("claude") or {}
    out = {k: [str(r) for r in rules.get(k) or []] for k in CLAUDE_RULES if rules.get(k)}
    if global_ and out.get("deny"):
        # your user settings apply to every project, adorno or not: a shell write (git push, gh pr create…) asks
        # there instead of being refused; edits of adorno's own files stay denied
        shell = [r for r in out["deny"] if r.startswith("Bash(")]
        out["deny"] = [r for r in out["deny"] if not r.startswith("Bash(")]
        out["ask"] = sorted(set(out.get("ask", [])) | set(shell))
        out = {k: v for k, v in out.items() if v}
    return out


def write_settings(path: Path, data: dict, stop: Path) -> None:
    if data:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2) + "\n")
    elif path.exists():
        path.unlink()
        prune(path, stop)


def apply_permissions(path: Path, wanted: dict[str, list[str]], previous: dict[str, list[str]], stop: Path) -> dict:
    """Merge our rules into a Claude Code settings file, removing the ones a previous install added and no longer
    wants; never touches a rule we did not add. Returns what we own now."""
    if not wanted and not previous:
        return {}
    data = read_settings(path)
    block = data.setdefault("permissions", {})
    owned: dict[str, list[str]] = {}
    for kind in CLAUDE_RULES:
        cur = [r for r in block.get(kind) or [] if r not in (previous.get(kind) or [])]
        add = [r for r in wanted.get(kind) or [] if r not in cur]
        if cur or add:
            block[kind] = cur + add
        else:
            block.pop(kind, None)
        if add:
            owned[kind] = add
    if not block:
        data.pop("permissions")
    write_settings(path, data, stop)
    return owned


# Direct shell writes that must go through adorno's scripts (the guard hook reads them in full; these prefixes are
# for the tools' own confirmation rules in a global install)
SHELL_WRITES = [
    ["git", "push"], ["gh", "pr", ["create", "comment", "review", "merge", "close", "edit", "reopen"]],
    ["gh", "issue", ["create", "comment", "edit", "close"]], ["gh", "release"], ["gh", "api"],
]
GUARD_NAME = "adorno-github/scripts/guard_bash.py"
JOURNAL_NAME = "adorno-journal/scripts/journal.py"
# The Claude Code hooks that record a run (adorno-journal), and whether each runs without being waited for. A tool
# call is never slowed down; the others are rare and waited for, because a hook still running when a `claude -p`
# session ends is killed, and the end of the run would be lost.
JOURNAL_HOOKS = {"SessionStart": False, "UserPromptSubmit": False, "PostToolUse": True, "PostToolUseFailure": True,
                 "SubagentStart": False, "SubagentStop": False, "Stop": False, "PostCompact": False,
                 "SessionEnd": False}


def guard_path(plan: dict, target: str, name: str = GUARD_NAME) -> str | None:
    """Where the target's copy of the guard (or of another skill script) lands, relative to the install folder, or
    None."""
    for path, (_data, _exe, src) in plan.items():
        if path.endswith(name) and src is not None and str(src).startswith(str(DIST / target) + os.sep):
            return path
    return None


def journal_hooks(dest: Path, global_: bool, targets: list[str], plan: dict, gstate: dict) -> dict[str, list[dict]]:
    """The hooks that record a run, as {settings file: [{event, command, timeout, async}]}: Claude Code only. Open on
    failure, the opposite of the guard: without an open run, python3 or the script, nothing is recorded and the
    session goes on. A project next to a global install that already records adds none (every event would be
    written twice)."""
    script = guard_path(plan, "claude", JOURNAL_NAME) if "claude" in targets else None
    if not script:
        return {}
    if not global_ and any(JOURNAL_NAME in h.get("command", "")
                           for hs in owned_hooks(gstate, Path.home(), True).values() for h in hs):
        return {}
    command = f'ls "$HOME"/.adorno/runs/active/*.json >/dev/null 2>&1 || exit 0; python3 "{dest / script}" hook; exit 0'
    return {str(settings_path(dest, global_).relative_to(dest)): [
        {"event": event, "command": command, "timeout": 5, **({"async": True} if is_async else {})}
        for event, is_async in JOURNAL_HOOKS.items()]}


def guard_command(script: Path, mode: str, fmt: str) -> str:
    """The hook command. Closed on failure: without python3, or without the guard file, every shell command and
    every question (Claude Code) is refused (exit 2) rather than let through."""
    return (f'command -v python3 >/dev/null 2>&1 || {{ echo "adorno: python3 is missing, the guard blocks shell commands '
            f'and questions (install python3, or bin/kit uninstall)" >&2; exit 2; }}; '
            f'python3 "{script}" {mode} --format={fmt} || exit 2')


def guards(dest: Path, global_: bool, targets: list[str], plan: dict) -> dict[str, dict]:
    """The guard hook of each tool, as {settings file (relative to dest): {event, matcher, command, timeout}}.
    Claude: deny in a repo, ask in your user settings. Codex and Gemini refuse in a repo; their hooks cannot ask, so a
    global install gives them confirmation rules instead (global_rule_files)."""
    out: dict[str, dict] = {}
    if "claude" in targets and (g := guard_path(plan, "claude")):
        settings_rel = str(settings_path(dest, global_).relative_to(dest))
        out[settings_rel] = {"event": "PreToolUse", "matcher": "Bash|AskUserQuestion", "timeout": 10,
                    "command": guard_command(dest / g, "ask" if global_ else "deny", "claude")}
    if global_:
        return out
    if "codex" in targets and (g := guard_path(plan, "codex")):
        out[".codex/hooks.json"] = {"event": "PreToolUse", "matcher": "^Bash$", "timeout": 10,
                                    "command": guard_command(dest / g, "deny", "codex")}
    if "gemini" in targets and (g := guard_path(plan, "gemini")):
        out[".gemini/settings.json"] = {"event": "BeforeTool", "matcher": "run_shell_command", "timeout": 10000,
                                        "command": guard_command(dest / g, "deny", "gemini")}
    return out


def global_rule_files(targets: list[str]) -> dict[str, bytes]:
    """--global: confirmation rules in the tools' own formats (the guard hook asks only in Claude Code)."""
    files: dict[str, bytes] = {}
    why = "adorno: a direct write; agents publish through the adorno-github scripts"
    if "codex" in targets:
        lines = ["# Written by adorno (bin/kit install --global); removed by bin/kit uninstall --global.",
                 "# Codex asks before each direct write; agents publish through the adorno-github scripts.", ""]
        for pattern in SHELL_WRITES:
            lines.append(f"prefix_rule(pattern={json.dumps(pattern)}, decision=\"prompt\", "
                         f"justification={json.dumps(why)})")
        files[".codex/rules/adorno.rules"] = ("\n".join(lines) + "\n").encode()
    if "gemini" in targets:
        prefixes = []
        for pattern in SHELL_WRITES:
            head = " ".join(w for w in pattern if isinstance(w, str))
            tails = next((w for w in pattern if isinstance(w, list)), None)
            prefixes += [f"{head} {t}" for t in tails] if tails else [head]
        body = ["# Written by adorno (bin/kit install --global); removed by bin/kit uninstall --global.", "",
                "[[rule]]", 'toolName = "run_shell_command"', f"commandPrefix = {json.dumps(prefixes)}",
                'decision = "ask_user"', "priority = 900", ""]
        files[".gemini/policies/adorno.toml"] = "\n".join(body).encode()
    return files


def apply_hooks(path: Path, wanted: list[dict], previous: list[dict], stop: Path) -> list[dict]:
    """Our hooks (the guard, the journal) into a settings file (Claude Code, Codex hooks.json, Gemini): add them,
    remove the ones a previous install added, never touch a hook we did not add. Returns what we own."""
    if not wanted and not previous:
        return []
    data = read_settings(path)
    hooks = data.setdefault("hooks", {})
    ours = {h.get("command") for h in previous + wanted}
    for event in {h["event"] for h in previous + wanted}:
        entries = [e for e in hooks.get(event) or []
                   if not (isinstance(e, dict) and any(isinstance(x, dict) and x.get("command") in ours
                                                       for x in e.get("hooks") or []))]
        for h in wanted:
            if h["event"] == event:
                entries.append({**({"matcher": h["matcher"]} if h.get("matcher") else {}), "hooks": [
                    {"type": "command", "command": h["command"], "timeout": h["timeout"],
                     **({"async": True} if h.get("async") else {})}]})
        if entries:
            hooks[event] = entries
        else:
            hooks.pop(event, None)
    if not hooks:
        data.pop("hooks")
    write_settings(path, data, stop)
    return wanted


def owned_hooks(state: dict, dest: Path, global_: bool) -> dict[str, list[dict]]:
    """The hooks a previous install added, per settings file (older installs recorded one Claude command as a
    string, then one hook per file)."""
    h = state.get("hook")
    if isinstance(h, str):
        return {str(settings_path(dest, global_).relative_to(dest)): [{"event": "PreToolUse", "command": h}]}
    if not isinstance(h, dict):
        return {}
    return {settings_rel: [one] if isinstance(one, dict) else list(one) for settings_rel, one in h.items()}


def apply_env(path: Path, wanted: dict[str, str], previous: dict[str, str], stop: Path) -> dict:
    """`models.claude_env` into a Claude Code settings file › env: set ours, remove the ones a previous install set and
    no longer wants, never touch a variable we did not set. Returns what we own."""
    if not wanted and not previous:
        return {}
    data = read_settings(path)
    block = data.setdefault("env", {})
    for k, v in previous.items():
        if block.get(k) == v and k not in wanted:
            block.pop(k)
    owned = {}
    for k, v in wanted.items():
        if k in block and block[k] != v and k not in previous:
            warn(f"{path}: env.{k} is already set by you; kept yours")
            continue
        block[k] = v
        owned[k] = v
    if not block:
        data.pop("env")
    write_settings(path, data, stop)
    return owned


def cmd_uninstall(args) -> None:
    ctx.USE_LOCAL = True
    for dest in install_dests(args):
        uninstall_from(args, dest)


def uninstall_from(args, dest: Path) -> None:
    state = load_state(dest)
    if not state["files"] and not state["managed"]:
        die(f"nothing installed by kit in {dest}")
    adopted = set(state.get("adopted") or [])
    kept = {p: d for p, d in state["files"].items() if p not in adopted and not remove_owned(dest, p, d, args.force)}
    for path, created in state["managed"].items():
        remove_block(dest / path, created, dest)
    spath = settings_path(dest, dest == Path.home())
    apply_permissions(spath, {}, state.get("permissions") or {}, dest)
    apply_env(spath, {}, state.get("env") or {}, dest)
    for settings_rel, hs in owned_hooks(state, dest, dest == Path.home()).items():
        apply_hooks(dest / settings_rel, [], hs, dest)
    if dest != Path.home():
        update_exclude(dest, [])
    elif (kit_home() / "registry.json").exists():
        (kit_home() / "registry.json").chmod(0o600)
        (kit_home() / "registry.json").unlink()
    sp = dest / STATE
    if kept:
        state.update(files=kept, managed={}, permissions={}, env={}, hook=None)
        sp.write_text(json.dumps(state, indent=2) + "\n")
    else:
        sp.unlink()
        prune(sp, dest)
    print(f"uninstalled from {dest}" + (f" ({len(kept)} modified file(s) kept)" if kept else ""))


def cmd_journal(args) -> None:
    """`kit journal enrich RUN`: the skill's own writer does it (run-end starts it too; this runs it again)."""
    sys.exit(subprocess.run([sys.executable, str(ROOT / "src" / "skills" / JOURNAL_NAME), args.action, args.run]).returncode)


def cmd_serve(args) -> None:
    """`kit serve`: the local server of the run journals and their viewer (bin/kit_serve.py, standard library)."""
    import kit_serve
    sys.exit(kit_serve.serve(args.port, args.runs or str(kit_home() / "runs"), str(ROOT / "viewer")))
