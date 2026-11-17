"""Helpers: errors, YAML and Markdown frontmatter, hashes, paths relative to the kit, git."""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

import yaml

from kitlib.paths import FM_RE, ROOT


def die(msg: str) -> None:
    print(f"kit: {msg}", file=sys.stderr)
    sys.exit(1)


def warn(msg: str) -> None:
    print(f"warning: {msg}", file=sys.stderr)


def load_yaml(path: Path) -> dict:
    if not path.exists():
        return {}
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def parse_md(path: Path) -> tuple[dict, str]:
    text = path.read_text(encoding="utf-8")
    m = FM_RE.match(text)
    if not m:
        return {}, text
    try:
        meta = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError as e:
        mark = getattr(e, "problem_mark", None)
        where = f" (frontmatter line {mark.line + 1})" if mark else ""
        die(f"{rel(path)}: invalid YAML{where}: {getattr(e, 'problem', e)} — quote values that contain ': '")
    if not isinstance(meta, dict):
        die(f"{path}: frontmatter must be a YAML mapping")
    return meta, m.group(2)


def dump_md(meta: dict, body: str) -> str:
    body = body.strip() + "\n"
    if not meta:
        return body
    fm = yaml.safe_dump(meta, sort_keys=False, allow_unicode=True, width=10_000).strip()
    return f"---\n{fm}\n---\n\n{body}"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def first_line(text: str) -> str:
    return " ".join(str(text).split())


def as_list(value) -> list | None:
    if value is None:
        return None
    if isinstance(value, str):
        return [v.strip() for v in value.split(",") if v.strip()]
    return list(value)


def deep_merge(a: dict, b: dict) -> dict:
    out = dict(a)
    for k, v in (b or {}).items():
        out[k] = deep_merge(out[k], v) if isinstance(out.get(k), dict) and isinstance(v, dict) else v
    return out


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def git(*args: str, cwd: Path | None = None) -> str:
    res = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if res.returncode != 0:
        die(f"git {' '.join(args)} failed: {res.stderr.strip()}")
    return res.stdout.strip()
