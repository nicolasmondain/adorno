"""Items (skills, agents, workflows), the kit config, and how sources are collected, overlaid and extended."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from kitlib.paths import KINDS, LOCAL_SRC, ROOT, SRC, VENDOR, VISION, VISION_MAX_LINES
from kitlib.util import die, first_line, load_yaml, parse_md, rel, warn
from kitlib.registry import local_on


@dataclass
class Item:
    kind: str          # skill | agent | workflow
    name: str          # file-safe name: adorno-agent-perf-mongodb, adorno-pr-status
    meta: dict
    body: str
    path: Path         # SKILL.md for skills, the .md file otherwise
    origin: str        # "local" or the import name
    id: str = ""       # logical id: agent:perf:mongodb (defaults to name)
    expected: str = "" # name the file location implies
    base_dirs: tuple = ()  # extra skill folders merged under this one (extends)
    overlay_dirs: tuple = ()  # private skill folders laid over this one (local/src/skills/<name>/)

    def __post_init__(self) -> None:
        self.id = self.id or self.name
        self.expected = self.expected or self.name

    @property
    def description(self) -> str:
        return first_line(self.meta.get("description", ""))

    def overrides(self, target: str) -> dict:
        return dict((self.meta.get("targets") or {}).get(target) or {})


class Config:
    def __init__(self) -> None:
        self.manifest = load_yaml(ROOT / "kit.yaml")
        adapters = load_yaml(ROOT / "adapters" / "targets.yaml")
        self.targets: dict = adapters.get("targets", {})
        self.caps: list = adapters.get("capabilities", [])
        self.tiers: list = adapters.get("model_tiers", [])
        # native tool/model name -> neutral, used to normalise imported agents
        self.tool_reverse: dict[str, str] = {}
        self.model_reverse: dict[str, str] = {}
        for t in self.targets.values():
            for cap, names in (t.get("tools") or {}).items():
                for n in names or []:
                    self.tool_reverse.setdefault(n, cap)
            for tier, model in (t.get("models") or {}).items():
                self.model_reverse.setdefault(model, tier)

    def target(self, name: str) -> dict:
        if name not in self.targets:
            die(f"unknown target '{name}' (known: {', '.join(self.targets)})")
        return self.targets[name]

    @property
    def default_targets(self) -> list[str]:
        return list(self.manifest.get("targets") or ["claude", "codex"])


FAMILY_FILE = "_family.md"
# a folder's mermaid diagram, for readers of the source: never an item, never shipped
SCHEMA_FILE = "SCHEMA.md"
NOT_ITEMS = (FAMILY_FILE, SCHEMA_FILE)


def load_item(kind: str, path: Path, origin: str) -> Item:
    meta, body = parse_md(path)
    if kind == "skill":
        default = path.parent.name
        return Item(kind, str(meta.get("name") or default), meta, body, path, origin, expected=default)
    if kind == "agent" and path.parent.name == KINDS[kind] and origin in ("local", "private"):
        # a top-level agent of ours: src/agents/adorno.md -> agent:adorno
        meta.pop("name", None)
        return Item(kind, path.stem, meta, body, path, origin, id=f"agent:{path.stem}", expected=path.stem)
    if path.parent.name != KINDS[kind]:
        # nested: src/agents/<family>/<specialty>.md -> agent:<family>:<specialty>
        family, specialty = path.parent.name, path.stem
        logical = f"{kind}:{family}:{specialty}"
        # file names all start with `adorno-`: workflows are the commands you type, agents carry `agent-`
        name = f"adorno-{family}-{specialty}" if kind == "workflow" else f"adorno-agent-{family}-{specialty}"
        given = meta.get("name")
        base = path.parent / FAMILY_FILE
        if not base.exists():  # a private agent in a public family: the public family file applies
            base = SRC / KINDS[kind] / family / FAMILY_FILE
        if base.exists():
            fmeta, fbody = parse_md(base)
            merged = {k: v for k, v in fmeta.items() if k not in ("name", "description")}
            merged.update(meta)
            fbody = fbody.replace("{{family}}", family).replace("{{specialty}}", specialty)
            meta, body = merged, fbody.strip() + "\n\n" + body.strip()
        item = Item(kind, name, meta, body, path, origin, id=logical, expected=name)
        if given and given not in (logical, name):
            item.expected = f"{name} (or {logical})"
            item.name = str(given)
        meta.pop("name", None)
        return item
    default = path.stem
    return Item(kind, str(meta.get("name") or default), meta, body, path, origin, expected=default)


def scan(base: Path, origin: str) -> list[Item]:
    found = [load_item("skill", p, origin) for p in sorted((base / "skills").glob("*/SKILL.md"))]
    for kind in ("agent", "workflow"):
        root = base / KINDS[kind]
        paths = sorted(root.glob("*.md")) + sorted(root.glob("*/*.md"))
        found += [load_item(kind, p, origin) for p in paths if p.name not in NOT_ITEMS]
    return found


def collect() -> dict[str, dict[str, Item]]:
    items: dict[str, dict[str, Item]] = {k: {} for k in KINDS}
    vendor_index: dict[tuple[str, str, str], Item] = {}
    vendors = sorted(d for d in VENDOR.iterdir() if d.is_dir()) if VENDOR.exists() else []
    for d in vendors:
        for it in scan(d, d.name):
            vendor_index[(it.kind, it.origin, it.name)] = it
            prev = items[it.kind].get(it.name)
            if prev:
                die(f"{it.kind} '{it.name}' comes from both '{prev.origin}' and '{it.origin}'; "
                    f"set a prefix on one import in kit.yaml")
            items[it.kind][it.name] = it
    for it in scan(SRC, "local"):
        if it.meta.get("extends"):
            apply_extends(it, vendor_index, items)
        prev = items[it.kind].get(it.name)
        if prev and prev.origin != "local":
            warn(f"local {it.kind} '{it.name}' overrides the one imported from '{prev.origin}'")
        items[it.kind][it.name] = it
    if local_on():
        overlay_private(items)
        vision = vision_text()
        if vision:
            for it in items["agent"].values():
                it.body = it.body.rstrip() + "\n\n" + vision_section(vision, agent=True)
    return items


def overlay_private(items: dict) -> None:
    """local/src/: skill folders are laid over the public skill of the same name file by file (a SKILL.md there
    replaces its meta and body); agents, workflows and new skills are added or replace the public ones."""
    skills = LOCAL_SRC / "skills"
    for d in sorted(skills.iterdir()) if skills.is_dir() else []:
        if not d.is_dir():
            continue
        it = items["skill"].get(d.name)
        if it:
            it.overlay_dirs += (d,)
            if (d / "SKILL.md").exists():
                meta, body = parse_md(d / "SKILL.md")
                it.meta = {**it.meta, **{k: v for k, v in meta.items() if k != "name"}}
                it.body = body if body.strip() else it.body
            continue
        if not (d / "SKILL.md").exists():
            die(f"{d}: lays over no known skill and has no SKILL.md")
        new = load_item("skill", d / "SKILL.md", "private")
        items["skill"][new.name] = new
    for kind in ("agent", "workflow"):
        root = LOCAL_SRC / KINDS[kind]
        for p in sorted(root.glob("*.md")) + sorted(root.glob("*/*.md")):
            if p.name not in NOT_ITEMS:
                it = load_item(kind, p, "private")
                items[kind][it.name] = it


def vision_text() -> str:
    if not (local_on() and VISION.exists()):
        return ""
    text = re.sub(r"<!--.*?-->", "", VISION.read_text(encoding="utf-8"), flags=re.S).strip()
    if text.count("\n") + 1 > VISION_MAX_LINES:
        warn(f"{VISION}: {text.count(chr(10)) + 1} lines; it is copied into every agent, keep it under "
             f"{VISION_MAX_LINES}")
    return text


def vision_section(text: str, agent: bool = False) -> str:
    head = ("## The owner's vision (applies over this agent's defaults)" if agent
            else "## The owner's vision")
    note = ("It overrides your own instructions, the profile and the imported skills; only the repo's rules "
            "(CLAUDE.md, .claude/rules/) win on its code. A conflict with them: apply the repo's way and flag it."
            if agent else
            "It applies over every agent, skill and workflow; only the repo's rules (`CLAUDE.md`, "
            "`.claude/rules/`) win on its code. A conflict with them: apply the repo's way and flag it. The current "
            "repo's `vision` lines (`repo-conf`) are added to it.")
    return f"{head}\n\n> {note}\n\n{text}\n"


def apply_extends(it: Item, vendor_index: dict, items: dict) -> None:
    """`extends: <import>/<name>`: the imported item's meta and body come first, ours on top."""
    ref = str(it.meta.pop("extends"))
    if "/" not in ref:
        die(f"{rel(it.path)}: extends must be '<import>/<name>', got '{ref}'")
    origin, name = ref.split("/", 1)
    base = vendor_index.get((it.kind, origin, name))
    if not base:
        die(f"{rel(it.path)}: extends '{ref}' but no imported {it.kind} has that name (run `kit import`)")
    meta = {k: v for k, v in base.meta.items() if k != "name"}
    meta.update(it.meta)
    it.meta = meta
    it.body = base.body.strip() + "\n\n" + it.body.strip()
    if it.kind == "skill":
        it.base_dirs = (base.path.parent,)
    if items[it.kind].get(base.name) is base:
        del items[it.kind][base.name]  # consumed: only the extended version ships
