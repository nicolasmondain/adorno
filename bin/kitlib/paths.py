"""The kit root, the paths derived from it and the constants every module shares."""

from __future__ import annotations

import os
import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent.parent   # bin/kitlib/paths.py -> the kit root
SRC, VENDOR, DIST = ROOT / "src", ROOT / "vendor", ROOT / "dist"
LOCAL = Path(os.environ.get("ADORNO_LOCAL") or ROOT / "local").expanduser().resolve()
LOCAL_CONF = LOCAL / "adorno.yaml"
LOCAL_SRC = LOCAL / "src"
VISION = LOCAL / "vision.md"
LEGACY_LOCAL = ROOT / "repos.local.yaml"
RESOLVER = ROOT / "src" / "skills" / "adorno-github" / "scripts" / "resolve.jq"
LEVELS = ("L0", "L1", "L2", "L3", "L4")
PONYTAIL_LEVELS = ("lite", "full", "ultra")
PRICE_KEYS = ("input", "cache_write_5m", "cache_write_1h", "cache_read", "output")  # repos.yaml › prices, read by run-usage
ACTIONS = ("push", "reply", "comment", "resolve", "rerequest", "review", "submit", "open_pr", "ci_rerun")
CLAUDE_RULES = ("allow", "ask", "deny")
VISION_MAX_LINES = 60
# neutral model tiers, declared once in adapters/targets.yaml (which also maps them per tool)
TIERS = tuple(yaml.safe_load((ROOT / "adapters" / "targets.yaml").read_text())["model_tiers"])
EFFORTS = ("low", "medium", "high", "max")   # reasoning effort an agent or workflow may declare (Claude Code)
SECRET_ENV_RE = re.compile(r"(KEY|TOKEN|SECRET|PASSWORD)", re.I)
LOCK = ROOT / "kit.lock"
STATE = ".adorno/installed.json"
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
FM_RE = re.compile(r"\A---[ \t]*\n(.*?)\n---[ \t]*(?:\n|\Z)(.*)\Z", re.S)
BEGIN = "<!-- adorno:begin (managed by kit — edits inside this block are overwritten) -->"
END = "<!-- adorno:end -->"
BLOCK_RE = re.compile(r"<!-- adorno:begin.*?-->.*?<!-- adorno:end -->\n?", re.S)
KINDS = {"skill": "skills", "agent": "agents", "workflow": "workflows"}
NEUTRAL_AGENT_KEYS = {"name", "description", "tools", "model", "effort", "targets", "delegable", "entry"}
ARGS_TOKEN = "{{args}}"
