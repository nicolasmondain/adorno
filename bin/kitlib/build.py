"""Writing the rendered targets to disk and comparing a tree with the committed one."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

from kitlib.paths import ROOT, SRC
from kitlib.util import die, sha
from kitlib.registry import local_on
from kitlib.model import Config
from kitlib.render import build_target, FileMap, render_instructions


def claude_plugin(cfg: Config, files: FileMap) -> FileMap:
    m = cfg.manifest
    out: FileMap = {}
    for path, v in files.items():
        for src, dst in ((".claude/skills/", "skills/"), (".claude/agents/", "agents/"),
                         (".claude/commands/", "commands/")):
            if path.startswith(src):
                out[dst + path[len(src):]] = v
    extras = SRC / "extras" / "claude-plugin"
    if extras.is_dir():
        for f in sorted(extras.rglob("*")):
            if f.is_file() and f.name != ".DS_Store":
                out[f.relative_to(extras).as_posix()] = (f.read_bytes(), os.access(f, os.X_OK))
    manifest = {"name": m["name"], "version": m.get("version", "0.0.0"),
                "description": m.get("description", "")}
    if m.get("author"):
        manifest["author"] = m["author"]
    out[".claude-plugin/plugin.json"] = (json.dumps(manifest, indent=2, ensure_ascii=False).encode() + b"\n", False)
    return out


def marketplace_json(cfg: Config) -> bytes:
    m = cfg.manifest
    data = {
        "name": m["name"],
        "owner": m.get("author") or {"name": m["name"]},
        "plugins": [{"name": m["name"], "source": "./dist/claude-plugin",
                     "description": m.get("description", ""), "version": m.get("version", "0.0.0")}],
    }
    return json.dumps(data, indent=2, ensure_ascii=False).encode() + b"\n"


def write_tree(base: Path, files: FileMap) -> None:
    for path, (data, exe) in files.items():
        p = base / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        if exe:
            p.chmod(p.stat().st_mode | 0o111)


def build_all(cfg: Config, items, out_root: Path) -> None:
    if local_on() and out_root == ROOT:
        die("refusing to write the personal layer (local/) into dist/ (its plugin is committed and public)")
    dist = out_root / "dist"
    if dist.exists():
        shutil.rmtree(dist)
    instructions = render_instructions(cfg, items)
    write_tree(dist, {"AGENTS.md": (instructions.encode(), False)})
    for target in cfg.default_targets:
        files = build_target(cfg, target, items)
        write_tree(dist / target, files)
        if target == "claude":
            write_tree(dist / "claude-plugin", claude_plugin(cfg, files))
    if "claude" in cfg.default_targets:
        write_tree(out_root, {".claude-plugin/marketplace.json": (marketplace_json(cfg), False)})


def tree_digest(base: Path) -> dict[str, str]:
    if not base.exists():
        return {}
    return {p.relative_to(base).as_posix(): sha(p.read_bytes())
            for p in sorted(base.rglob("*")) if p.is_file()}


def committed(digest: dict[str, str], prefix: str) -> dict[str, str]:
    """The entries of a digest that git does not ignore: git's ignore rules decide what of dist/ is committed."""
    res = subprocess.run(["git", "check-ignore", "-z", "--no-index", "--stdin"], cwd=ROOT, capture_output=True,
                         text=True, input="".join(f"{prefix}/{p}\0" for p in digest))
    if res.returncode not in (0, 1):   # 1: nothing ignored
        die(f"git check-ignore failed: {res.stderr.strip()}")
    ignored = set(res.stdout.split("\0"))
    return {p: h for p, h in digest.items() if f"{prefix}/{p}" not in ignored}
