"""Validation of the items and of the registry (areas, watches, models, Notion, after_pr)."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess

from kitlib import ctx
from kitlib.paths import (ACTIONS, CLAUDE_RULES, EFFORTS, LEGACY_LOCAL, LEVELS, NAME_RE, PONYTAIL_LEVELS,
                          PRICE_KEYS, ROOT, SECRET_ENV_RE, SRC, TIERS)
from kitlib.util import as_list, load_yaml, rel, warn
from kitlib.registry import local_conf, local_on, registry
from kitlib.model import Config, Item


def validate(cfg: Config, items: dict[str, dict[str, Item]]) -> list[str]:
    errors: list[str] = []
    owner: dict[str, str] = {}
    for kind, group in items.items():
        for name, it in sorted(group.items()):
            where = rel(it.path)
            if not NAME_RE.match(name) or len(name) > 64:
                errors.append(f"{where}: invalid name '{name}' (lowercase letters, digits, hyphens; max 64)")
            if name != it.expected:
                errors.append(f"{where}: name '{name}' must match '{it.expected}'")
            desc = it.meta.get("description")
            if not isinstance(desc, str) or not desc.strip():
                errors.append(f"{where}: missing description (it is what makes agents pick it)")
            elif len(desc) > 1024:
                errors.append(f"{where}: description longer than 1024 characters")
            if not it.body.strip():
                errors.append(f"{where}: empty body")
            if name in owner and owner[name] != kind:
                errors.append(f"{where}: '{name}' is also a {owner[name]} name; agents and workflows "
                              f"become skills on some targets, so names must be unique across kinds")
            owner.setdefault(name, kind)

            if kind == "agent":
                for tool in as_list(it.meta.get("tools")) or []:
                    if tool not in cfg.caps and tool not in cfg.tool_reverse:
                        warn(f"{where}: tool '{tool}' is not a known capability; passed through as-is")
                model = it.meta.get("model")
                if model is not None and model not in cfg.tiers:
                    errors.append(f"{where}: model '{model}' must be one of {cfg.tiers} "
                                  f"(put native model names under targets.<tool>.model)")
                entry = it.meta.get("entry")
                if entry is not None and not (isinstance(entry, list) and all(isinstance(x, str) for x in entry)):
                    errors.append(f"{where}: entry must be a list of workflow ids")
                for wf in entry if isinstance(entry, list) else []:
                    target = next((w for w in items["workflow"].values() if w.id == wf), None)
                    if target is None:
                        errors.append(f"{where}: entry names unknown workflow '{wf}'")
                    elif it.id not in ((target.meta.get("uses") or {}).get("agents") or []):
                        errors.append(f"{where}: entry '{wf}' does not list {it.id} in its uses.agents")
            effort = it.meta.get("effort")
            if kind != "skill" and effort is not None and effort not in EFFORTS:
                errors.append(f"{where}: effort '{effort}' must be one of {list(EFFORTS)}")
            if kind == "workflow":
                if it.meta.get("model") is not None and it.meta["model"] not in cfg.tiers:
                    errors.append(f"{where}: model '{it.meta['model']}' must be one of {cfg.tiers}")
                uses = it.meta.get("uses") or {}
                for key in ("skills", "agents", "workflows"):
                    known = {i.id for i in items[key[:-1]].values()} | set(items[key[:-1]])
                    for ref in uses.get(key) or []:
                        if ref not in known:
                            errors.append(f"{where}: uses unknown {key[:-1]} '{ref}'")
    for tgt in cfg.default_targets:
        cfg.target(tgt)

    delegable = {i.id for i in items["agent"].values() if i.meta.get("delegable")}
    reg = registry()
    agent_ids = {i.id for i in items["agent"].values()} | set(items["agent"])
    errors += validate_registry(reg, agent_ids, delegable,
                                {i.name for i in items["skill"].values()} | set(items["skill"]),
                                {w.id for w in items["workflow"].values()})
    errors += validate_roles(reg, items, agent_ids)
    if not local_on():   # the public registry must leave no agent unreachable
        for orphan in orphan_agents(reg, items):
            errors.append(f"orphan agent '{orphan}': no area role, fallback or entry names it")
        errors += orphan_skills(cfg, items)
    return errors


# agent roles of an area, and the agent families each may come from (single place)
ROLE_FAMILIES = {"build": ("feat", "test", "docs", "chore"), "fix": ("fix", "test", "refactor", "ci", "docs", "chore"),
                 "perf": ("perf",), "review": ("review",), "qa": ("test",)}
AREA_KEYS = {"paths", "content", *ROLE_FAMILIES, "skills", "sub"}
# the families a fallback may come from: a nit is a fix, a missing test a test, a perf point a perf agent, or a fixer
# with the perf skill (the neutral default: perf agents are stack-specific)
FALLBACK_FAMILIES = {"nit": ROLE_FAMILIES["fix"], "test": ("test",), "perf": ROLE_FAMILIES["perf"] + ("fix",)}
AREA_REVIEWERS_MSG = ("`area_reviewers` is replaced by `areas.<area>.review`: run the adorno-setup skill (mode repo) "
                      "to migrate; `bin/kit migrate areas` prints the conversion")
# agents merged into another one: old id -> the id that took over its checks (`bin/kit migrate agents`)
AGENT_RENAMES = {"agent:review:perf": "agent:review:front", "agent:review:perf-back": "agent:review:back"}


def unknown_agent(name: str) -> str:
    if name in AGENT_RENAMES:
        return (f"names unknown agent '{name}' (merged into '{AGENT_RENAMES[name]}': "
                f"`bin/kit migrate agents` prints the conversion)")
    return f"names unknown agent '{name}'"


def area_refs(conf: dict) -> list[tuple[str, str]]:
    """(path, agent ref) of every role of `areas` and `fallbacks`; a leading `-` (removal) is stripped."""
    refs: list[tuple[str, str]] = []

    def one(path: str, value) -> None:
        for v in value if isinstance(value, list) else [value]:
            if isinstance(v, str):
                refs.append((path, v[1:] if v.startswith("-") else v))

    def area(path: str, a: dict) -> None:
        for role in ROLE_FAMILIES:
            one(f"{path}.{role}", a.get(role))
        for name, sub in (a.get("sub") or {}).items():
            if isinstance(sub, dict):
                area(f"{path}.sub.{name}", sub)

    for name, a in (conf.get("areas") or {}).items():
        if isinstance(a, dict):
            area(f"areas.{name}", a)
    for key, v in (conf.get("fallbacks") or {}).items():
        one(f"fallbacks.{key}", v.get("agent") if isinstance(v, dict) else v)
    return refs


def validate_roles(reg: dict, items: dict, known: set) -> list[str]:
    """`roles:` of a dispatcher workflow: known roles, and `uses.agents` covers every agent the areas give them."""
    errors: list[str] = []
    scopes = [reg.get("defaults") or {}, *(c or {} for c in (reg.get("presets") or {}).values()),
              *(c or {} for c in (reg.get("workspaces") or {}).values()), *(c or {} for c in (reg.get("repos") or {}).values())]
    # an unknown agent is validate_areas' error, with its migration hint
    refs = [(path, ref) for conf in scopes if isinstance(conf, dict) for path, ref in area_refs(conf) if ref in known]
    for it in sorted(items["workflow"].values(), key=lambda w: w.id):
        roles = it.meta.get("roles")
        if roles is None:
            continue
        where = rel(it.path)
        if not (isinstance(roles, list) and all(isinstance(r, str) for r in roles)):
            errors.append(f"{where}: roles must be a list of roles")
            continue
        for r in roles:
            if r not in ROLE_FAMILIES:
                errors.append(f"{where}: roles: unknown role '{r}' (known: {', '.join(ROLE_FAMILIES)})")
        used = set((it.meta.get("uses") or {}).get("agents") or [])
        for r in (r for r in roles if r in ROLE_FAMILIES):
            wanted = {ref for path, ref in refs if path.endswith(f".{r}")}
            if r in ("fix", "perf"):
                wanted |= {ref for path, ref in refs if path.startswith("fallbacks.")}
            for ref in sorted(wanted - used):
                errors.append(f"{it.id} dispatches role '{r}' but uses.agents lacks '{ref}' ({where})")
    return errors


def orphan_agents(reg: dict, items: dict) -> list[str]:
    """Agents no public area role, fallback or stack preset names, and without an `entry`."""
    public = load_yaml(ROOT / "repos.yaml").get("presets") or {}
    scopes = [reg.get("defaults") or {}, *(c or {} for c in public.values())]
    reached = {ref for conf in scopes if isinstance(conf, dict) for _, ref in area_refs(conf)}
    return sorted(i.id for i in items["agent"].values() if i.id not in reached and not i.meta.get("entry"))


def cites(name: str, text: str) -> bool:
    """`text` names the skill `name` exactly (not as part of a longer name)."""
    return bool(re.search(rf"(?<![\w-]){re.escape(name)}(?![\w-])", text))


def citing_texts(local: list[Item]) -> list[tuple[str, str]]:
    """What can cite an imported skill, as (label, text): our items (frontmatter and body), the instructions and
    repos.yaml."""
    texts = [(i.id, json.dumps(i.meta, default=str) + i.body) for i in local]
    texts += [(rel(p), p.read_text(encoding="utf-8")) for p in sorted((SRC / "instructions").glob("*.md"))]
    if (ROOT / "repos.yaml").exists():
        texts.append(("repos.yaml", (ROOT / "repos.yaml").read_text(encoding="utf-8")))
    return texts


def orphan_skills(cfg: Config, items: dict) -> list[str]:
    """An imported skill ships everywhere and its description can trigger it alone: one that no item of ours,
    instruction or repos.yaml names must be listed in its import's `uncited` (called by hand)."""
    local = [i for g in items.values() for i in g.values() if i.origin == "local"]
    corpus = "\n".join(text for _, text in citing_texts(local))
    errors: list[str] = []
    for imp in cfg.manifest.get("imports") or []:
        uncited = imp.get("uncited") or []
        if not isinstance(uncited, list):
            errors.append(f"kit.yaml: import {imp.get('name')}: uncited must be a list of skill names")
            continue
        mine = {i.name for i in items["skill"].values() if i.origin == imp.get("name")}
        errors += [f"kit.yaml: import {imp.get('name')}: uncited '{n}' is not one of its skills"
                   for n in uncited if n not in mine]
        errors += [f"orphan skill '{n}' (import {imp.get('name')}): no item cites it; cite it or list it in uncited"
                   for n in sorted(mine - set(uncited)) if not cites(n, corpus)]
    return errors


def validate_areas(conf: dict, where: str, scope: str, agent_ids: set, skill_names: set) -> list[str]:
    """`areas` and `fallbacks`: known keys, agents and skills that exist, one family set per role."""
    errors: list[str] = []
    if "area_reviewers" in conf:
        errors.append(f"{where}: {scope}: {AREA_REVIEWERS_MSG}")

    def regex(path: str, rx) -> None:
        if not isinstance(rx, str):
            errors.append(f"{where}: {path} must be a regex string")
        else:  # the engine pr-areas runs: awk, POSIX ERE
            res = subprocess.run(["awk", 'BEGIN { if ("" ~ ENVIRON["AREA_RE"]) {} }'],
                                 env={**os.environ, "AREA_RE": rx}, capture_output=True, text=True)
            if res.returncode != 0:
                errors.append(f"{where}: {path} is an invalid regex (not a valid awk POSIX ERE): {res.stderr.strip()[:200]}")

    def agent(path: str, ref, families: tuple | None) -> None:
        if not isinstance(ref, str):
            errors.append(f"{where}: {path} must name an agent")
            return
        name = ref[1:] if ref.startswith("-") else ref
        if name not in agent_ids:
            errors.append(f"{where}: {path} {unknown_agent(name)}")
        elif families and name.split(":")[1:2] and name.split(":")[1] not in families:
            errors.append(f"{where}: {path}: '{name}' is not a {'/'.join(families)} agent")

    def skills(path: str, value) -> None:
        if not isinstance(value, list):
            errors.append(f"{where}: {path} must be a list of skills")
            return
        for sk in value:
            name = sk[1:] if isinstance(sk, str) and sk.startswith("-") else sk
            if name not in skill_names:
                errors.append(f"{where}: {path} names unknown skill '{name}'")

    def role(path: str, a: dict, role: str) -> None:
        value = a.get(role)
        if value is None:
            return
        if role == "skills":
            skills(path, value)
        elif role == "review":
            if not isinstance(value, list):
                errors.append(f"{where}: {path} must be a list of agents")
            for ref in value if isinstance(value, list) else []:
                agent(path, ref, ROLE_FAMILIES[role])
        else:
            agent(path, value, ROLE_FAMILIES[role])

    def area(path: str, a, keys: set) -> None:
        if not isinstance(a, dict):
            errors.append(f"{where}: {path} must be a mapping")
            return
        for key in a:
            if key not in keys:
                errors.append(f"{where}: {path}.{key}: unknown key (known: {', '.join(sorted(keys))})")
        if a.get("paths") is not None and not (isinstance(a["paths"], list)
                                               and all(isinstance(x, str) for x in a["paths"])):
            errors.append(f"{where}: {path}.paths must be a list of strings")
        if a.get("content") is not None:
            regex(f"{path}.content", a["content"])
        for r in (*ROLE_FAMILIES, "skills"):
            if r in keys:
                role(f"{path}.{r}", a, r)

    areas = conf.get("areas")
    if areas is not None and not isinstance(areas, dict):
        errors.append(f"{where}: {scope}.areas must be a mapping")
        areas = {}
    for name, a in (areas or {}).items():
        p = f"{scope}.areas.{name}"
        if name == "always":
            area(p, a, {"review", "skills"})
            continue
        area(p, a, AREA_KEYS)
        if isinstance(a, dict) and a.get("sub") is not None:
            if not isinstance(a["sub"], dict):
                errors.append(f"{where}: {p}.sub must be a mapping")
                continue
            for sname, sub in a["sub"].items():
                area(f"{p}.sub.{sname}", sub, AREA_KEYS - {"sub"})
    fb = conf.get("fallbacks")
    if fb is not None and not isinstance(fb, dict):
        errors.append(f"{where}: {scope}.fallbacks must be a mapping")
        fb = {}
    for key, v in (fb or {}).items():
        p = f"{scope}.fallbacks.{key}"
        if key not in FALLBACK_FAMILIES:
            errors.append(f"{where}: {p}: unknown key (known: {', '.join(FALLBACK_FAMILIES)})")
        elif key == "perf" and isinstance(v, dict):
            for k in v:
                if k not in ("agent", "skills"):
                    errors.append(f"{where}: {p}.{k}: unknown key (known: agent, skills)")
            agent(f"{p}.agent", v.get("agent"), FALLBACK_FAMILIES[key])
            if v.get("skills") is not None:
                skills(f"{p}.skills", v["skills"])
        else:
            agent(p, v, FALLBACK_FAMILIES[key])
    return errors


WATCH_NOTIFY = ("dm", "draft", "none")
SINCE_RE = re.compile(r"^(\d+[mhd]|\d{4}-\d{2}-\d{2}(T[\d:]+Z?)?)$")


def validate_journal(reg: dict, where: str) -> list[str]:
    """`journal` of the personal layer: what the run journal keeps (adorno-journal/scripts/journal.py › DEFAULTS)."""
    conf = reg.get("journal")
    if conf is None:
        return []
    if not isinstance(conf, dict):
        return [f"{where}: journal must be a mapping"]
    errors = [f"{where}: journal.{k}: unknown setting (known: reasoning, retention_days, max_mb)"
              for k in conf if k not in ("reasoning", "retention_days", "max_mb")]
    if "reasoning" in conf and not isinstance(conf["reasoning"], bool):
        errors.append(f"{where}: journal.reasoning must be true or false")
    for k in ("retention_days", "max_mb"):
        if k in conf and not (isinstance(conf[k], int) and not isinstance(conf[k], bool) and conf[k] > 0):
            errors.append(f"{where}: journal.{k} must be a positive integer")
    return errors


def validate_watches(reg: dict, where: str, agent_ids: set) -> list[str]:
    """`slack` and `notion` sections of the personal layer (workflow:slack:*, workflow:notion:*)."""
    errors: list[str] = []

    def common(scope: str, conf: dict) -> None:
        if conf.get("since") is not None and not SINCE_RE.match(str(conf["since"])):
            errors.append(f"{where}: {scope}.since must look like 90m, 24h, 7d or 2026-11-01")
        if conf.get("max_messages") is not None and not (isinstance(conf["max_messages"], int)
                                                         and conf["max_messages"] > 0):
            errors.append(f"{where}: {scope}.max_messages must be a positive integer")
        if conf.get("notify") is not None and conf["notify"] not in WATCH_NOTIFY:
            errors.append(f"{where}: {scope}.notify must be one of {', '.join(WATCH_NOTIFY)}")
        lvl = (conf.get("action") or {}).get("level", conf.get("level"))
        if lvl is not None and lvl not in LEVELS:
            errors.append(f"{where}: {scope} level must be one of {', '.join(LEVELS)}")

    slack = reg.get("slack") or {}
    if slack:
        common("slack", slack)
        for name, w in (slack.get("watches") or {}).items():
            scope = f"slack.watches.{name}"
            if not isinstance(w, dict):
                errors.append(f"{where}: {scope} must be a mapping")
                continue
            common(scope, w)
            if not w.get("channels"):
                errors.append(f"{where}: {scope} needs `channels`")
            if not (w.get("includes") or w.get("regex")):
                errors.append(f"{where}: {scope} needs `includes` (words) or `regex`")
            if w.get("regex"):
                # the scripts match with jq (Oniguruma): validate with the same engine when it is here
                if shutil.which("jq"):
                    res = subprocess.run(["jq", "-n", "--arg", "r", str(w["regex"]), '"" | test($r)'],
                                         capture_output=True, text=True)
                    if res.returncode != 0:
                        errors.append(f"{where}: {scope}.regex is invalid: {res.stderr.strip()[:200]}")
                else:
                    try:
                        re.compile(str(w["regex"]))
                    except re.error as e:
                        errors.append(f"{where}: {scope}.regex is invalid: {e}")
            action = w.get("action") or {}
            if action.get("agent") and action["agent"] not in agent_ids:
                errors.append(f"{where}: {scope}.action.agent {unknown_agent(action['agent'])}")
            if action and not (action.get("agent") or action.get("workflow") or action.get("prompt")):
                errors.append(f"{where}: {scope}.action needs `agent`, `workflow` or `prompt`")
        if slack.get("mentions") is not None:
            common("slack.mentions", slack["mentions"] or {})
    notion = reg.get("notion") or {}
    if notion.get("assigned") is not None:
        a = notion["assigned"] or {}
        common("notion.assigned", a)
        if a.get("mode") is not None and a["mode"] not in ("report", "run"):
            errors.append(f"{where}: notion.assigned.mode must be report or run")
        for db, target in (a.get("agents") or {}).items():
            if isinstance(target, str) and target.startswith("agent:") and target not in agent_ids:
                errors.append(f"{where}: notion.assigned.agents.{db} {unknown_agent(target)}")
    return errors




def validate_models(m, where: str, agent_ids: set, delegable: set) -> list[str]:
    """`models`: tiers per target, per-agent / per-workflow choice, external routes, Claude Code env."""
    if m is None:
        return []
    if not isinstance(m, dict):
        return [f"{where} must be a mapping"]
    errors: list[str] = []
    for target, tiers in (m.get("tiers") or {}).items():
        for tier in (tiers or {}):
            if tier not in TIERS:
                errors.append(f"{where}.tiers.{target}.{tier}: tiers are {', '.join(TIERS)}")
    routes = m.get("routes") or {}
    for name, r in routes.items():
        if not isinstance(r, dict) or not r.get("base_url") or not r.get("model"):
            errors.append(f"{where}.routes.{name} needs `base_url` and `model`")
        elif not re.match(r"^(https://[A-Za-z0-9.-]+|http://(localhost|127\.0\.0\.1))(:\d{1,5})?(/[^@\s]*)?$",
                          str(r["base_url"])):
            errors.append(f"{where}.routes.{name}.base_url must be https://host[/path] (plain http for localhost only)")
        elif r.get("api_key_env") and not re.match(r"^[A-Z][A-Z0-9_]*_(API_KEY|LLM_KEY)$", str(r["api_key_env"])):
            errors.append(f"{where}.routes.{name}.api_key_env must name a model key variable (…_API_KEY or …_LLM_KEY)")
        if isinstance(r, dict) and r.get("api_key"):
            errors.append(f"{where}.routes.{name}: never put a key here; use `api_key_env` (a variable name)")
    for key in ("agents", "workflows"):
        for ref, spec in (m.get(key) or {}).items():
            if key == "agents" and ref not in agent_ids:
                errors.append(f"{where}.agents {unknown_agent(ref)}")
            if isinstance(spec, dict):
                if spec.get("route") and key == "workflows":
                    errors.append(f"{where}.workflows.{ref}: only agents can be sent to a route")
                if spec.get("route") and key == "agents" and ref not in delegable:
                    errors.append(f"{where}.agents.{ref}: not `delegable` (it needs tools while it thinks), "
                                  f"it cannot go to a route")
                if spec.get("route") and spec["route"] not in routes:
                    # the route may come from another scope: checked again at install
                    warn(f"{where}.{key}.{ref}: route '{spec['route']}' is not defined in this scope")
            elif not isinstance(spec, str):
                errors.append(f"{where}.{key}.{ref} must be a tier, a model id or {{route: …}}")
    for k in (m.get("claude_env") or {}):
        if SECRET_ENV_RE.search(str(k)):
            errors.append(f"{where}.claude_env.{k}: secrets stay in your shell profile, never in this file")
        if k == "CLAUDE_CODE_SUBAGENT_MODEL":
            errors.append(f"{where}.claude_env.{k} would override every agent's model; set tiers instead")
    return errors


NOTION_STEPS = ("start", "pr_opened")  # the steps adorno-github/scripts/notion-step knows


def validate_notion_spec(spec, where: str) -> list[str]:
    """`notion_spec`: per workflow step, the properties set on the Notion page used as the spec."""
    if spec is None:
        return []
    if not isinstance(spec, dict):
        return [f"{where} must be a mapping of steps ({', '.join(NOTION_STEPS)})"]
    errors: list[str] = []
    for step, props in spec.items():
        if step not in NOTION_STEPS:
            errors.append(f"{where}: unknown step '{step}' (known: {', '.join(NOTION_STEPS)})")
            continue
        if props is None:
            continue
        if not isinstance(props, dict):
            errors.append(f"{where}.{step} must map property names to values")
            continue
        for name, value in props.items():
            if value is not None and not isinstance(value, (str, int, float, bool)):
                errors.append(f"{where}.{step}.{name} must be a string, a number, a boolean or null")
            elif isinstance(value, str) and set(re.findall(r"\{\{(.*?)\}\}", value)) - {"today", "pr_url"}:
                errors.append(f"{where}.{step}.{name}: unknown placeholder (known: {{{{today}}}}, {{{{pr_url}}}})")
            elif step != "pr_opened" and isinstance(value, str) and "{{pr_url}}" in value:
                errors.append(f"{where}.{step}.{name}: {{{{pr_url}}}} only exists once the PR is open (pr_opened)")
    return errors


AFTER_PR_NEEDS = ("notion",)  # what an after_pr entry can require of the run


def validate_after_pr(entries, where: str, workflow_ids: set) -> list[str]:
    """`after_pr`: repo skills run once the PR exists, each for the workflows that trigger it."""
    if entries is None:
        return []
    if not isinstance(entries, list):
        return [f"{where} must be a list of {{skill, workflows, needs}}"]
    errors: list[str] = []
    seen: set = set()
    for i, e in enumerate(entries):
        at = f"{where}[{i}]"
        if not isinstance(e, dict):
            errors.append(f"{at} must be a mapping with skill and workflows")
            continue
        for key in e.keys() - {"skill", "workflows", "needs"}:
            errors.append(f"{at}: unknown key '{key}' (known: skill, workflows, needs)")
        if not (isinstance(e.get("skill"), str) and re.fullmatch(r"/?[A-Za-z0-9:_-]+", e["skill"])):
            errors.append(f"{at}.skill must be a skill or command name (like /acme-notion-fields)")
        elif e["skill"] in seen:
            errors.append(f"{at}.skill '{e['skill']}' is already listed: list several workflows in one entry")
        else:
            seen.add(e["skill"])
        wf = e.get("workflows")
        if not (isinstance(wf, list) and wf and all(isinstance(w, str) and re.fullmatch(r"workflow:[a-z0-9]+:[a-z0-9-]+", w) for w in wf)):
            errors.append(f"{at}.workflows must be a non-empty list of workflow ids (like workflow:issue:fix)")
        else:
            errors += [f"{at}.workflows: unknown workflow '{w}'" for w in wf if w not in workflow_ids]
        if e.get("needs") is not None and e["needs"] not in AFTER_PR_NEEDS:
            errors.append(f"{at}.needs must be one of {', '.join(AFTER_PR_NEEDS)}")
    return errors


def validate_registry(reg: dict, agent_ids: set, delegable: set, skill_names: set,
                      workflow_ids: set) -> list[str]:
    """repos.yaml and the personal layer: references, levels, permissions, shapes."""
    errors: list[str] = []
    if ctx.USE_LOCAL and LEGACY_LOCAL.exists():
        errors.append(f"{rel(LEGACY_LOCAL)} is replaced by local/adorno.yaml: move it there "
                      f"(`owner` goes top-level; see local.example/)")
    where = "local/adorno.yaml" if local_on() else "repos.yaml"
    presets = reg.get("presets") or {}
    if local_on():
        public = set(load_yaml(ROOT / "repos.yaml").get("presets") or {})
        for name in sorted(public & set(local_conf().get("presets") or {})):
            errors.append(f"{where}: presets.{name} reuses the name of a public preset (repos.yaml): give yours "
                          f"another name and `use: [{name}]` in it, then add your keys")
    scopes = [("defaults", reg.get("defaults") or {})]
    scopes += [(f"presets.{n}", c or {}) for n, c in presets.items()]
    scopes += [(f"workspaces.{n}", c or {}) for n, c in (reg.get("workspaces") or {}).items()]
    scopes += [(f"repos.{r}", c or {}) for r, c in (reg.get("repos") or {}).items()]
    for scope, conf in scopes:
        if not isinstance(conf, dict):
            errors.append(f"{where}: {scope} must be a mapping")
            continue
        errors += validate_areas(conf, where, scope, agent_ids, skill_names)
        for ref in conf.get("use") or []:
            if ref not in presets:
                errors.append(f"{where}: {scope}.use names unknown preset '{ref}'")
        if conf.get("max_level") is not None and conf["max_level"] not in LEVELS:
            errors.append(f"{where}: {scope}.max_level must be one of {', '.join(LEVELS)}")
        if conf.get("ponytail") is not None and conf["ponytail"] not in PONYTAIL_LEVELS:
            errors.append(f"{where}: {scope}.ponytail must be one of {', '.join(PONYTAIL_LEVELS)}")
        for key in ("context", "vision"):
            if conf.get(key) is not None and not (isinstance(conf[key], list)
                                                  and all(isinstance(x, str) for x in conf[key])):
                errors.append(f"{where}: {scope}.{key} must be a list of lines")
        errors += validate_models(conf.get("models"), f"{where}: {scope}.models", agent_ids, delegable)
        imp = conf.get("impact")
        if imp is not None:
            if not isinstance(imp, dict):
                errors.append(f"{where}: {scope}.impact must be a mapping")
            else:
                for k in ("window", "min_age"):
                    if imp.get(k) is not None and not re.match(r"^\d+[hd]$", str(imp[k])):
                        errors.append(f"{where}: {scope}.impact.{k} must look like 48h or 7d")
                if imp.get("post") is not None and imp["post"] not in ("comment", "none"):
                    errors.append(f"{where}: {scope}.impact.post must be comment or none")
                if imp.get("sources") is not None and not isinstance(imp["sources"], list):
                    errors.append(f"{where}: {scope}.impact.sources must be a list")
        for key in ("commit_skill", "pr_skill", "setup_skill"):
            if conf.get(key) is not None and not (isinstance(conf[key], str)
                                                  and re.fullmatch(r"/?[A-Za-z0-9:_-]+", conf[key])):
                errors.append(f"{where}: {scope}.{key} must be a skill or command name (like adorno-commit or /acme-pr)")
        errors += validate_notion_spec(conf.get("notion_spec"), f"{where}: {scope}.notion_spec")
        errors += validate_after_pr(conf.get("after_pr"), f"{where}: {scope}.after_pr", workflow_ids)
        if conf.get("voice") is not None and not isinstance(conf["voice"], dict):
            errors.append(f"{where}: {scope}.voice must be a mapping")
        perms = conf.get("permissions")
        if perms is not None:
            if not isinstance(perms, dict):
                errors.append(f"{where}: {scope}.permissions must be a mapping")
                continue
            for a in perms.get("deny") or []:
                if a not in ACTIONS:
                    errors.append(f"{where}: {scope}.permissions.deny: unknown action '{a}' (known: {', '.join(ACTIONS)})")
            for key in (perms.get("claude") or {}):
                if key not in CLAUDE_RULES:
                    errors.append(f"{where}: {scope}.permissions.claude.{key}: expected {', '.join(CLAUDE_RULES)}")
        if scope.startswith("workspaces.") and not (conf.get("repos") or conf.get("paths")):
            errors.append(f"{where}: {scope} needs `repos` (GitHub globs) or `paths` (local folders)")
    errors += validate_watches(reg, where, agent_ids)
    errors += validate_journal(reg, where)
    prices = reg.get("prices")
    if prices is not None and not isinstance(prices, dict):
        errors.append(f"{where}: prices must be a mapping of model id to rates")
    for model, rates in (prices or {}).items() if isinstance(prices, dict) else ():
        if not (isinstance(rates, dict) and set(rates) == set(PRICE_KEYS) and all(
                isinstance(v, (int, float)) and not isinstance(v, bool) and v >= 0 for v in rates.values())):
            errors.append(f"{where}: prices.{model}: numbers >= 0 ($ per million tokens) for all of {', '.join(PRICE_KEYS)}")
    # presets that use each other must not loop
    def walk(name: str, seen: tuple) -> None:
        if name in seen:
            errors.append(f"{where}: presets loop: {' -> '.join((*seen, name))}")
            return
        for ref in (presets.get(name) or {}).get("use") or []:
            if ref in presets:
                walk(ref, (*seen, name))
    for name in presets:
        walk(name, ())
    return list(dict.fromkeys(errors))
