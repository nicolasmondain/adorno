"""Rendering of each item and of the instructions for one target."""

from __future__ import annotations

import json
import os
import re

from kitlib import ctx
from kitlib.paths import ARGS_TOKEN, KINDS, LOCAL_SRC, NEUTRAL_AGENT_KEYS, ROOT, SRC, TIERS
from kitlib.util import as_list, die, dump_md, load_yaml
from kitlib.registry import local_on
from kitlib.model import Config, Item, SCHEMA_FILE, vision_section, vision_text
from kitlib.validate import cites

FileMap = dict[str, tuple[bytes, bool]]   # relative path -> (content, executable)


def map_tools(cfg: Config, tcfg: dict, tools) -> list[str] | None:
    tools = as_list(tools)
    if tools is None:
        return None
    native = tcfg.get("tools") or {}
    out: list[str] = []
    for tool in tools:
        cap = tool if tool in cfg.caps else cfg.tool_reverse.get(tool)
        mapped = native.get(cap) if cap and cap in native else [tool]
        for m in mapped or []:
            if m not in out:
                out.append(m)
    return out


def map_model(tcfg: dict, model, target: str | None = None) -> str | None:
    """A neutral tier -> the target's model: `models.tiers.<target>` of the personal layer first, then
    adapters/targets.yaml. Anything else is a native model id, passed through as-is (personal layer only)."""
    if model is None:
        return None
    mine = ((ctx.MODELS.get("tiers") or {}).get(target) or {}) if target else {}
    if model in mine:
        return str(mine[model])
    if model in (tcfg.get("models") or {}):
        return (tcfg.get("models") or {}).get(model)
    return None if model in TIERS else str(model)


def clean_skill_meta(it: Item, target: str, extra: dict | None = None) -> dict:
    meta = {k: v for k, v in it.meta.items() if k != "targets"}
    meta.update(extra or {})
    meta.update(it.overrides(target))
    return meta


def skill_data(cfg: Config, it: Item) -> FileMap:
    """kit.yaml `skill_data`: YAML files from the kit root shipped inside a skill as JSON."""
    out: FileMap = {}
    for dest, source in ((cfg.manifest.get("skill_data") or {}).get(it.name) or {}).items():
        src = ROOT / source
        if not src.exists():
            die(f"kit.yaml skill_data: {source} not found")
        # the public registry only: the personal one never lands in a project tree (see write_registry)
        data = load_yaml(ROOT / "repos.yaml") if source == "repos.yaml" else load_yaml(src)
        out[dest] = (json.dumps(data, indent=2, ensure_ascii=False, default=str).encode() + b"\n", False)
    return out


def skill_tree(cfg: Config, it: Item, target: str, extra: dict | None = None) -> FileMap:
    out: FileMap = {}
    for base in (*it.base_dirs, it.path.parent, *it.overlay_dirs):  # imported, ours, then private on top
        for f in sorted(base.rglob("*")):
            if f.is_dir() or f.name in (".DS_Store", SCHEMA_FILE):
                continue
            r = f.relative_to(base).as_posix()
            if r != "SKILL.md":
                out[r] = (f.read_bytes(), os.access(f, os.X_OK))
    out["SKILL.md"] = (dump_md(clean_skill_meta(it, target, extra), it.body).encode(), False)
    out.update(skill_data(cfg, it))
    return out


def as_skill(it: Item, target: str) -> FileMap:
    """Agents and workflows for tools that have no native equivalent."""
    if it.kind == "agent":
        desc = f"Role {it.id} — {it.description}"
        body = (f"# Role: {it.id}\n\n"
                f"When this skill is invoked, take on the role below for the current task, "
                f"then return to your normal behavior once the result is delivered.\n\n{it.body.strip()}")
    else:
        desc = f"{it.id} — {it.description}"
        body = (f"# {it.id}\n\n"
                f"Input: the user's request. Follow the steps in order.\n\n"
                f"{it.body.strip().replace(ARGS_TOKEN, 'the user’s request')}")
    meta = {"name": it.name, "description": desc[:1024]}
    meta.update(it.overrides(target))
    return {"SKILL.md": (dump_md(meta, body).encode(), False)}


def agent_command(it: Item, target: str, hidden: dict) -> Item:
    """A command that hands its input to the agent, so every agent can also be called by hand. The model already
    sees the agent itself: the command stays out of its list (target `hidden`)."""
    body = (f"Delegate the request below to the `{it.name}` sub-agent ({it.id}) and return its result "
            f"as is. If the sub-agent is not available, take on its role (skill or file "
            f"`{it.name}`) to handle the request.\n\nRequest: {ARGS_TOKEN}")
    meta = {"description": f"{it.id} — {it.description}"[:1024], "args": "<request>", "targets": {target: hidden}}
    return Item("workflow", it.name, meta, body, it.path, it.origin, id=it.id)


def render_agent(cfg: Config, it: Item, target: str, tcfg: dict, fmt: str) -> str:
    meta: dict = {"name": it.name, "description": it.description}
    tools = map_tools(cfg, tcfg, it.meta.get("tools"))
    model = map_model(tcfg, it.meta.get("model"), target)
    if fmt == "claude":
        if tools:
            meta["tools"] = ", ".join(tools)
        if model:
            meta["model"] = model
        if it.meta.get("effort"):
            meta["effort"] = it.meta["effort"]
        # keep Claude-specific keys from imported agents (color, permissionMode…)
        meta.update({k: v for k, v in it.meta.items() if k not in NEUTRAL_AGENT_KEYS})
    elif fmt == "gemini":
        if tools:
            meta["tools"] = tools
        if model:
            meta["model"] = model
    elif fmt == "copilot":
        if tools:
            meta["tools"] = tools
    else:
        die(f"unknown agent format '{fmt}'")
    meta.update(it.overrides(target))
    return dump_md(meta, it.body)


def toml_str(s: str) -> str:
    if "'''" not in s:
        return "'''\n" + s + "'''"
    return json.dumps(s, ensure_ascii=False)


def render_workflow(it: Item, target: str, fmt: str, tcfg: dict | None = None) -> str:
    body = it.body.strip()
    hint = it.meta.get("args")
    over = it.overrides(target)
    if fmt == "claude-command":
        meta = {"description": it.description}
        if hint:
            meta["argument-hint"] = hint
        model = map_model(tcfg or {}, it.meta.get("model"), target)
        if model:
            meta["model"] = model
        if it.meta.get("effort"):
            meta["effort"] = it.meta["effort"]
        meta.update(over)
        return dump_md(meta, body.replace(ARGS_TOKEN, "$ARGUMENTS"))
    if fmt == "gemini-command":
        desc = over.get("description", it.description)
        return f"description = {json.dumps(desc, ensure_ascii=False)}\nprompt = {toml_str(body + chr(10))}\n"
    if fmt == "copilot-prompt":
        meta = {"description": it.description, **over}
        return dump_md(meta, body.replace(ARGS_TOKEN, "${input:args}"))
    if fmt == "cursor-command":
        return f"# {it.name}\n\n{it.description}\n\n" + \
            body.replace(ARGS_TOKEN, "the text typed after the command") + "\n"
    die(f"unknown workflow format '{fmt}'")
    return ""


def render_instructions(cfg: Config, items: dict[str, dict[str, Item]]) -> str:
    files = {p.name: p for p in (SRC / "instructions").glob("*.md")}
    if local_on():
        files.update({p.name: p for p in (LOCAL_SRC / "instructions").glob("*.md")})
    parts = [files[n].read_text(encoding="utf-8").strip() for n in sorted(files)]
    vision = vision_text()
    if vision:
        parts.append(vision_section(vision).strip())
    if (cfg.manifest.get("instructions") or {}).get("catalog", True):
        # Agents and skills are discovered natively by every tool (sub-agents, skills); only the workflows, the
        # entry points, get a one-line index here — the full descriptions would cost tokens in every session.
        lines = ["## Workflows adorno", "",
                 "Each one is a command of the same name (without native commands: the skill of the same name).", ""]
        for it in sorted(items["workflow"].values(), key=lambda i: i.id):
            first = re.split(r"(?<=[.;—])\s", it.description.strip(), maxsplit=1)[0].rstrip(" .;—")
            lines.append(f"- `{it.id}` (`/{it.name}`) — {first[:110]}")
        parts.append("\n".join(lines).strip())
    return "\n\n".join(p for p in parts if p) + "\n"


def session_skills(cfg: Config, items: dict) -> set[str]:
    """The skills a workflow or the instructions name: the main session may need them. Every other imported skill is
    only read by a sub-agent (agents, areas, fallbacks) or called by hand, so its description stays out of the model's
    list (target `hidden`). The instructions are the ones shipped: private ones and the vision too when installing."""
    texts = [json.dumps(i.meta, default=str) + i.body for i in items["workflow"].values()]
    texts.append(render_instructions(cfg, items))
    corpus = "\n".join(texts)
    return {n for n in items["skill"] if cites(n, corpus)}


def build_target(cfg: Config, target: str, items) -> FileMap:
    tcfg = cfg.target(target)
    files: FileMap = {}
    skills_dir = tcfg["skills"]
    hidden = tcfg.get("hidden") or {}
    seen = session_skills(cfg, items)

    def put_skill(name: str, tree: FileMap) -> None:
        for r, v in tree.items():
            files[f"{skills_dir}/{name}/{r}"] = v

    for it in items["skill"].values():
        sub_agent_only = it.origin not in ("local", "private") and it.name not in seen
        put_skill(it.name, skill_tree(cfg, it, target, hidden if sub_agent_only else None))

    for kind in ("agent", "workflow"):
        spec = tcfg[KINDS[kind]]
        fmt = spec["format"]
        for it in items[kind].values():
            if fmt == "skill":
                put_skill(it.name, as_skill(it, target))
                continue
            path = f"{spec['dir']}/{it.name}{spec.get('ext', '.md')}"
            text = (render_agent(cfg, it, target, tcfg, fmt) if kind == "agent"
                    else render_workflow(it, target, fmt, tcfg))
            files[path] = (text.encode(), False)

    # each native agent also gets a command, so it can be called by hand
    wspec = tcfg["workflows"]
    if tcfg["agents"]["format"] != "skill" and wspec["format"] != "skill" and tcfg.get("agent_commands", True):
        for it in items["agent"].values():
            path = f"{wspec['dir']}/{it.name}{wspec.get('ext', '.md')}"
            files[path] = (render_workflow(agent_command(it, target, hidden), target, wspec["format"]).encode(), False)

    extras = SRC / "extras" / target
    if extras.is_dir():
        for f in sorted(extras.rglob("*")):
            if f.is_file() and f.name != ".DS_Store":
                files[f.relative_to(extras).as_posix()] = (f.read_bytes(), os.access(f, os.X_OK))
    return files


def managed_files(cfg: Config, target: str, instructions: str, global_: bool) -> dict[str, str]:
    """Files that get a managed block rather than being owned outright."""
    tcfg = cfg.target(target)
    if global_:
        path = (tcfg.get("global") or {}).get("instructions")
        return {path: instructions} if path else {}
    out = {"AGENTS.md": instructions}
    for path, kind in (tcfg.get("instructions") or {}).items():
        out[path] = "@AGENTS.md" if kind == "shim" else instructions
    return out


def global_path(tcfg: dict, path: str) -> str | None:
    """Where a project-relative file lives under ~ for this target (None = unsupported)."""
    g = tcfg.get("global") or {}
    if any(path == s or path.startswith(s + "/") for s in g.get("skip") or []):
        return None
    for src, dst in (g.get("map") or {}).items():
        if path == src or path.startswith(src + "/"):
            return dst + path[len(src):]
    return path
