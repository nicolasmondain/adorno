"""Commands: check, doctor, conf, list, migrate, build, new."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

from kitlib import ctx
from kitlib.paths import DIST, KINDS, LEGACY_LOCAL, LOCAL, LOCAL_CONF, NAME_RE, ROOT, SRC, VISION
from kitlib.util import deep_merge, die, load_yaml, rel
from kitlib.registry import github_repo, local_conf, registry, resolve_repo
from kitlib.model import collect, Config
from kitlib.validate import AGENT_RENAMES, orphan_agents, ROLE_FAMILIES, validate
from kitlib.build import build_all, committed, tree_digest


def load_valid() -> tuple[Config, dict]:
    cfg = Config()
    items = collect()
    errors = validate(cfg, items)
    if errors:
        print("\n".join(f"error: {e}" for e in errors), file=sys.stderr)
        die(f"{len(errors)} error(s); fix them before building")
    return cfg, items


def cmd_check(args) -> None:
    ctx.USE_LOCAL = False
    cfg, items = load_valid()
    counts = ", ".join(f"{len(items[k])} {KINDS[k]}" for k in KINDS)
    print(f"ok: public — {counts}")
    if LOCAL.is_dir() or LEGACY_LOCAL.exists():
        ctx.USE_LOCAL = True
        _, private = load_valid()
        loc = local_conf()
        extra = sum(1 for k in private for i in private[k].values() if i.origin == "private" or i.overlay_dirs)
        print(f"ok: with {rel(LOCAL)} — {len(loc.get('repos') or {})} repo entr(ies), "
              f"{len(loc.get('workspaces') or {})} workspace(s), {len(loc.get('presets') or {})} preset(s), "
              f"{extra} private or overlaid item(s)" + (", vision" if VISION.exists() else ""))
        ctx.USE_LOCAL = False
    if args.dist:
        with tempfile.TemporaryDirectory() as tmp:
            build_all(cfg, items, Path(tmp))
            fresh = committed(tree_digest(Path(tmp) / "dist"), "dist")
            fresh_mp = tree_digest(Path(tmp) / ".claude-plugin")
        if fresh != committed(tree_digest(DIST), "dist") or fresh_mp != tree_digest(ROOT / ".claude-plugin"):
            die("dist/ is out of date — run `bin/kit build` and commit the result")
        print("ok: dist/ is up to date")


# tool -> (minimum, what needs it); README.md and docs/setup.md state the same minimums (tests/kit.test.sh checks it)
PREREQUISITES = {
    "jq": ("1.7.1", "the scripts and tests fail on 1.6"),
    "python3": ("3.9", "the guard hook, the journal and the bench run on the PATH python3"),
    "gh": ("2.99.0", "--attach on gh pr create/edit/comment"),
    "uv": ("0.4.19", "uv run --script, which runs bin/kit"),
}


def cmd_doctor(args) -> None:
    errors = 0
    # `uv run` puts kit's own environment (python3 >= 3.11) first in PATH: look past it, at the user's PATH
    own = os.path.join(sys.prefix, "bin") if sys.prefix != sys.base_prefix else None
    search = os.pathsep.join(d for d in os.environ.get("PATH", "").split(os.pathsep) if d != own)
    for tool, (minimum, why) in PREREQUISITES.items():
        path = shutil.which(tool, path=search)
        if not path:
            print(f"error: {tool} not found on PATH; needs >= {minimum}: {why}", file=sys.stderr)
            errors += 1
            continue
        try:
            res = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired) as e:
            print(f"error: {tool}: cannot run `{path} --version` ({e}); needs >= {minimum}: {why}", file=sys.stderr)
            errors += 1
            continue
        m = re.search(r"\d+(\.\d+)+", res.stdout + res.stderr)
        if not m:
            print(f"error: {tool}: no version in `{tool} --version` (exit {res.returncode}); needs >= {minimum}: {why}",
                  file=sys.stderr)
            errors += 1
        elif tuple(map(int, m.group().split("."))) < tuple(map(int, minimum.split("."))):
            print(f"error: {tool} {m.group()} is too old; needs >= {minimum}: {why}", file=sys.stderr)
            errors += 1
        else:
            print(f"ok: {tool} {m.group()} (>= {minimum})")
    if errors:
        die(f"{errors} prerequisite(s) missing or too old")


def cmd_conf(args) -> None:
    ctx.USE_LOCAL = True
    reg = registry()
    repo = args.repo or github_repo(Path.cwd())
    if not repo:
        print("scopes (weakest first; `kit conf owner/repo` for one repo):")
        print("  defaults")
        for name, ws in (reg.get("workspaces") or {}).items():
            print(f"  workspaces.{name}: {', '.join(ws.get('repos') or []) or '(no repo found)'}")
        for key in reg.get("repos") or {}:
            print(f"  repos.{key}")
        for name in reg.get("presets") or {}:
            print(f"  presets.{name} (used with `use:`)")
        return
    conf = resolve_repo(reg, repo)
    if conf is None:
        die(f"{repo} is not declared in {rel(LOCAL_CONF)} (repos, workspaces)")
    print(json.dumps(conf, indent=2, ensure_ascii=False))


def cmd_list(args) -> None:
    ctx.USE_LOCAL = True
    items = collect()
    if args.orphans:
        for orphan in orphan_agents(registry(), items):
            print(orphan)
        return
    for kind in KINDS:
        print(f"{KINDS[kind]}:")
        for it in sorted(items[kind].values(), key=lambda i: i.id):
            print(f"  {it.id:<34} [{it.origin}] {it.description[:60]}")


def migrate_areas(public: dict, loc: dict) -> list[dict]:
    """Additive equivalent of each legacy `area_reviewers` of the personal layer against the public `areas`."""
    public_areas = (public.get("defaults") or {}).get("areas") or {}
    # the legacy `mongodb` area is now the `mongodb` stack preset, on top of the neutral areas
    mongo_areas = deep_merge(public_areas, ((public.get("presets") or {}).get("mongodb") or {}).get("areas") or {})
    out: list[dict] = []
    scopes = [("defaults", loc.get("defaults"))]
    for group in ("presets", "workspaces", "repos"):
        scopes += [(f"{group}.{n}", c) for n, c in (loc.get(group) or {}).items()]
    for scope, conf in scopes:
        legacy = (conf or {}).get("area_reviewers") or {}
        for area, old in legacy.items():
            old = list(old or [])
            preset = area == "mongodb" and "mongodb" not in public_areas
            parts = ["back", "sub", "mongodb"] if preset else [area]
            node = mongo_areas if preset else public_areas
            inherited: list = []
            for part in parts:
                node = (node.get(part) if isinstance(node, dict) else None) or {}
                if part == "sub":
                    inherited = list(parent.get("review") or [])
                parent = node
            pub = list(node.get("review") or []) if isinstance(node, dict) else []
            new = [x for x in old if x not in inherited + pub] + ["-" + x for x in pub if x not in old]
            # the scope's own `use:` stays, the preset is appended: pasting the snippet must not drop one
            use = list((conf or {}).get("use") or [])
            out.append({"scope": scope, "area_path": "areas." + ".".join(parts) + ".review",
                        "old": old, "public": pub, "new": new,
                        **({"use": use + ([] if "mongodb" in use else ["mongodb"])} if preset else {})})
    return out


def rename_refs(old) -> tuple:
    """A role value (one ref or a list) with every merged id renamed, duplicates dropped: (new, decision or None).
    A removal `-old` would become `-new` and drop the surviving agent entirely, and `old` next to `-new` would go with
    it: both left out, for a human to decide."""
    vals = old if isinstance(old, list) else [old]
    new: list = []
    notes: list[str] = []
    for v in vals:
        neg = isinstance(v, str) and v.startswith("-")
        name = v[1:] if neg else v
        if name in AGENT_RENAMES:
            target = AGENT_RENAMES[name]
            if neg and "-" + target not in vals:
                notes.append(f"`{v}` removed only {name}, whose checks are now in {target}; `-{target}` would remove "
                             f"{target} entirely: keep {target} (proposed: the entry is dropped) or add `-{target}`")
                continue
            if not neg and "-" + target in vals:
                notes.append(f"`{v}` kept only the perf checks of {target}, which this list removes: keep `-{target}` "
                             f"(the perf checks go too; proposed: the entry is dropped) or drop `-{target}` (the whole review comes back)")
                continue
            v = ("-" if neg else "") + target
        if v not in new:
            new.append(v)
    return (new if isinstance(old, list) else (new or [None])[0]), (" ".join(notes) or None)


def migrate_agents(loc: dict) -> list[dict]:
    """Every setting of the personal layer that names a merged agent id (AGENT_RENAMES), and what it becomes."""
    out: list[dict] = []

    def ref(scope: str, keys: list, old) -> None:
        vals = old if isinstance(old, list) else [old]
        if any(isinstance(v, str) and v.lstrip("-") in AGENT_RENAMES for v in vals):
            new, decision = rename_refs(old)
            out.append({"scope": scope, "path": ".".join(keys), "keys": keys, "old": old, "new": new,
                        **({"decision": decision} if decision else {})})

    def area(scope: str, keys: list, a: dict) -> None:
        for role in ROLE_FAMILIES:
            ref(scope, [*keys, role], a.get(role))
        for name, sub in (a.get("sub") or {}).items():
            if isinstance(sub, dict):
                area(scope, [*keys, "sub", name], sub)

    scopes = [("defaults", loc.get("defaults"))]
    for group in ("presets", "workspaces", "repos"):
        scopes += [(f"{group}.{n}", c) for n, c in (loc.get(group) or {}).items()]
    for scope, conf in scopes:
        if not isinstance(conf, dict):
            continue
        for name, a in (conf.get("areas") or {}).items():
            if isinstance(a, dict):
                area(scope, ["areas", name], a)
        for old in (conf.get("models") or {}).get("agents") or {}:
            if old in AGENT_RENAMES:
                out.append({"scope": scope, "path": f"models.agents.{old}", "old": old, "new": None,
                            "decision": f"remove it; {AGENT_RENAMES[old]} now runs the whole review: give it a tier yourself if you want one"})
    for name, w in ((loc.get("slack") or {}).get("watches") or {}).items():
        ref("slack", ["watches", name, "action", "agent"], ((w or {}).get("action") or {}).get("agent"))
    for db, target in (((loc.get("notion") or {}).get("assigned") or {}).get("agents") or {}).items():
        ref("notion", ["assigned", "agents", db], target)
    return out


def nest(keys: list, value) -> dict:
    for key in reversed(keys):
        value = {key: value}
    return value


def cmd_migrate(args) -> None:
    """Read-only, and works when `check` fails: it reads the two files directly."""
    loc = load_yaml(LOCAL_CONF) if LOCAL_CONF.exists() else {}
    agents = args.what == "agents"
    rows = migrate_agents(loc) if agents else migrate_areas(load_yaml(ROOT / "repos.yaml"), loc)
    print(json.dumps(rows, indent=2, ensure_ascii=False))
    for scope in dict.fromkeys(r["scope"] for r in rows):
        snippet: dict = {}
        notes: list[str] = []
        for r in (r for r in rows if r["scope"] == scope):
            if not agents:
                if r.get("use"):
                    snippet["use"] = r["use"]
                snippet = deep_merge(snippet, nest(r["area_path"].split("."), r["new"]))
                continue
            if r["path"].startswith("models.agents."):
                notes.append(f"remove {r['path']}")
            else:
                snippet = deep_merge(snippet, nest(r["keys"], r["new"]))
            if r.get("decision"):
                notes.append(f"decide ({r['path']}): {r['decision']}")
        group, _, name = scope.partition(".")
        head = {group: {name: snippet}} if name else {group: snippet}
        title = "renamed agents" if agents else "replaces area_reviewers"
        print(f"# {scope}: {title}\n" + "".join(f"# {n}\n" for n in notes)
              + yaml.safe_dump(head, sort_keys=False), file=sys.stderr)


def cmd_build(args) -> None:
    cfg, items = load_valid()
    build_all(cfg, items, ROOT)
    print(f"built dist/ for {', '.join(cfg.default_targets)}")


TEMPLATES = {
    "skill": """---
name: {name}
description: What this skill does and WHEN to use it (this text is what triggers the skill).
---

# {title}

## When to use

## Steps

1.
""",
    "agent": """---
name: {name}
description: The agent's specialty and WHEN to delegate a task to it.
tools: [read, search]        # read, write, edit, search, shell, web, agent — omit to allow everything
model: inherit               # inherit, fast, balanced, deep, frontier (docs/models.md)
# effort: low                # optional: low, medium, high, max (Claude Code; default: the model's)
---

You are …

## Method

## What you return
""",
    "workflow": """---
name: {name}
description: What this workflow accomplishes end to end.
args: "<expected input>"
model: balanced              # the session that orchestrates: balanced; fast for a script and a table (docs/models.md)
uses:
  skills: []
  agents: []
---

Input: {{{{args}}}}

1.
""",
}


def cmd_new(args) -> None:
    """kit new skill <name> | kit new agent <family>:<specialty> | kit new workflow <domain>:<action>"""
    parts = args.name.split(":")
    if not all(NAME_RE.match(p) for p in parts) or len(parts) > 2 or (args.kind == "skill" and len(parts) > 1):
        die("name: lowercase-with-hyphens, or <group>:<name> for agents and workflows")
    base = SRC / KINDS[args.kind]
    if args.kind == "skill":
        path, name = base / args.name / "SKILL.md", args.name
    elif len(parts) == 2:
        path, name = base / parts[0] / f"{parts[1]}.md", f"{args.kind}-{parts[0]}-{parts[1]}"
    else:
        path, name = base / f"{args.name}.md", args.name
    if path.exists():
        die(f"{rel(path)} already exists")
    path.parent.mkdir(parents=True, exist_ok=True)
    text = TEMPLATES[args.kind].format(name=name, title=name.replace("-", " ").capitalize())
    if len(parts) == 2:
        text = re.sub(r"^name: .*\n", "", text, count=1, flags=re.M)  # derived from the path
    path.write_text(text, encoding="utf-8")
    print(f"created {rel(path)}")
