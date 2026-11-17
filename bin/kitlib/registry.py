"""The personal layer (local/) and the registry: repos.yaml with local/adorno.yaml on top, resolved per repo."""

from __future__ import annotations

import glob
import copy
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

from kitlib import ctx
from kitlib.paths import LOCAL, LOCAL_CONF, RESOLVER, ROOT
from kitlib.util import deep_merge, die, load_yaml


def local_on() -> bool:
    return ctx.USE_LOCAL and LOCAL.is_dir()


def local_conf() -> dict:
    return load_yaml(LOCAL_CONF) if local_on() and LOCAL_CONF.exists() else {}


GITHUB_RE = re.compile(r"(?:git@github\.com:|ssh://git@github\.com(?::\d+)?/|https?://(?:[^@/]+@)?github\.com/)"
                       r"([\w.-]+/[\w.-]+?)(?:\.git)?/?$")


def github_repo(path: Path) -> str | None:
    """owner/repo of the git repository at `path` (its `origin` on GitHub), or None."""
    res = subprocess.run(["git", "-C", str(path), "config", "--get", "remote.origin.url"], capture_output=True, text=True)
    m = GITHUB_RE.search(res.stdout.strip()) if res.returncode == 0 else None
    return m.group(1) if m else None


def workspace_dirs(ws: dict) -> dict[str, Path]:
    """Local repositories under a workspace's `paths` (globs, `~` allowed), keyed by owner/repo."""
    found: dict[str, Path] = {}
    for pattern in ws.get("paths") or []:
        expanded = os.path.expanduser(str(pattern))
        base = Path(expanded)
        roots = [Path(p) for p in sorted(glob.glob(expanded))] if any(c in expanded for c in "*?[") \
            else ([base] if base.is_dir() else [])
        for root in roots:
            candidates = [root] if (root / ".git").exists() else \
                [d.parent for d in sorted(root.glob("*/.git"))] + [d.parent for d in sorted(root.glob("*/*/.git"))]
            for d in candidates:
                repo = github_repo(d)
                if repo:
                    found.setdefault(repo, d)
    return found


_REGISTRY_CACHE: dict = {}


def registry() -> dict:
    """Cached per layer state (it scans workspace folders): see _registry."""
    key = "local" if local_on() else "public"
    if key not in _REGISTRY_CACHE:
        _REGISTRY_CACHE[key] = _registry()
    return copy.deepcopy(_REGISTRY_CACHE[key])


def _registry() -> dict:
    """repos.yaml, with the personal layer (local/adorno.yaml) on top when it is active: `owner` and `defaults`
    merged into the defaults, `presets` (added to the public ones), `workspaces` (local `paths` turned into the repos
    found there), `repos`."""
    data = load_yaml(ROOT / "repos.yaml")
    loc = local_conf()
    if loc:
        defaults = dict(loc.get("defaults") or {})
        if loc.get("owner"):
            defaults["owner"] = loc["owner"]
        data = deep_merge(data, {"defaults": defaults, "repos": loc.get("repos") or {}})
        data["presets"] = {**(data.get("presets") or {}), **(loc.get("presets") or {})}  # a clash: validate_registry
        workspaces = {}
        for name, ws in (loc.get("workspaces") or {}).items():
            ws = dict(ws or {})
            ws["repos"] = list(dict.fromkeys(list(ws.get("repos") or []) + list(workspace_dirs(ws))))
            workspaces[name] = ws
        data["workspaces"] = workspaces
        # owner-level: the watches (workflow:slack:*, workflow:notion:*) and the run journal's settings
        for key in ("slack", "notion", "journal"):
            if loc.get(key):
                data[key] = loc[key]
        if loc.get("prices"):  # your own rates or models, over the public ones
            data["prices"] = deep_merge(data.get("prices") or {}, loc["prices"])
    return data


def resolve_repo(reg: dict, repo: str) -> dict | None:
    """The settings `repo` resolves to, through the same resolver as the adorno-github scripts (needs jq)."""
    if not shutil.which("jq"):
        die("jq is required to resolve repo settings (brew install jq)")
    res = subprocess.run(["jq", "--arg", "r", repo, "-f", str(RESOLVER)], input=json.dumps(reg),
                         capture_output=True, text=True)
    if res.returncode != 0:
        die(f"resolving {repo}: {res.stderr.strip()}")
    return json.loads(res.stdout) if res.stdout.strip() else None
