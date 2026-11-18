"""Command `import`: fetch the imports of kit.yaml into vendor/, or check how far they are behind."""

from __future__ import annotations

import difflib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import traceback
from datetime import datetime, timezone
from pathlib import Path

import yaml

from kitlib.paths import FM_RE, KINDS, LOCK, NAME_RE, ROOT, SRC, VENDOR
from kitlib.util import as_list, die, dump_md, git, load_yaml, parse_md, rel, warn
from kitlib.model import Config, Item, scan
from kitlib.validate import cites, citing_texts
from kitlib.render import FileMap
from kitlib.build import write_tree


def resolve_source(source: str) -> tuple[str, bool]:
    if source.startswith("github:"):
        return f"https://github.com/{source[len('github:'):]}.git", False
    if re.match(r"^(https?|ssh|git|file)://|^git@", source):
        return source, False
    return str((ROOT / Path(source).expanduser()).resolve()), True


def fetch(url: str, ref: str | None, dest: Path) -> str:
    git("init", "-q", str(dest))
    git("remote", "add", "origin", url, cwd=dest)
    git("fetch", "-q", "--depth", "1", "origin", ref or "HEAD", cwd=dest)
    git("checkout", "-q", "FETCH_HEAD", cwd=dest)
    return git("rev-parse", "HEAD", cwd=dest)


def normalise_agent(cfg: Config, meta: dict) -> dict:
    meta = dict(meta)
    tools = as_list(meta.get("tools"))
    if tools is not None:
        caps: list[str] = []
        for t in tools:
            c = cfg.tool_reverse.get(t, t)
            if c not in caps:
                caps.append(c)
        meta["tools"] = caps
    model = meta.get("model")
    if model is not None and model not in cfg.tiers:
        tier = cfg.model_reverse.get(model)
        meta.pop("model")
        if tier:
            meta["model"] = tier
        else:
            meta.setdefault("targets", {}).setdefault("claude", {})["model"] = model
    return meta


def cmd_import(args) -> None:
    cfg = Config()
    imports = cfg.manifest.get("imports") or []
    if args.names:
        unknown = set(args.names) - {i["name"] for i in imports}
        if unknown:
            print(f"kit: not in kit.yaml: {', '.join(sorted(unknown))}", file=sys.stderr)
            sys.exit(3 if args.check else 1)  # under --check, 1 means "something to import"
        imports = [i for i in imports if i["name"] in args.names]
    if not imports:
        print("nothing to import (add entries under `imports:` in kit.yaml)")
        return
    lock = load_yaml(LOCK)
    ours = scan(SRC, "local")
    texts = citing_texts(ours)
    if args.check:
        moved = failed = False
        for imp in imports:
            try:
                moved |= check_import(cfg, imp, lock.get(imp["name"]) or {}, ours, texts)
            except (SystemExit, Exception) as e:  # the other imports are still checked
                if not isinstance(e, SystemExit):  # die() said why on stderr; a Python error (unreadable upstream) has not
                    traceback.print_exc()
                print(f"{imp['name']}: check failed")
                failed = True
        sys.exit(3 if failed else 1 if moved else 0)
    for imp in imports:
        name = imp["name"]
        if not NAME_RE.match(name):
            die(f"import name '{name}' must be lowercase-with-hyphens")
        url, local = resolve_source(imp["source"])
        locked = (lock.get(name) or {})
        pinned = None if args.update or locked.get("source") != imp["source"] else locked.get("commit")
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            if local:
                shutil.copytree(url, repo, ignore=shutil.ignore_patterns(".git"))
                commit = "local"
            else:
                commit = fetch(url, pinned or imp.get("ref"), repo)
            pulled = import_items(cfg, imp, repo)
            report = item_changes(name, vendored_files(name), item_files(pulled), ours, texts)
            out = VENDOR / name
            if out.exists():
                shutil.rmtree(out)
            for kind, entries in pulled.items():
                for item_name, payload in entries.items():
                    if kind == "skill":
                        write_tree(out / "skills" / item_name, payload)
                    else:
                        write_tree(out / KINDS[kind], {f"{item_name}.md": payload})
            out.mkdir(parents=True, exist_ok=True)
            for lic in sorted(repo.glob("LICEN[CS]E*")) + sorted(repo.glob("COPYING*")):
                shutil.copy2(lic, out / lic.name)
        same = commit != "local" and commit == locked.get("commit") and "fetched" in locked
        lock[name] = {
            "source": imp["source"], "ref": imp.get("ref"), "commit": commit,
            "fetched": locked["fetched"] if same else datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "items": sorted(f"{k}/{n}" for k, e in pulled.items() for n in e),
        }
        total = sum(len(e) for e in pulled.values())
        scripts = [p for p in (VENDOR / name).rglob("*") if p.is_file() and "LICEN" not in p.name
                   and (os.access(p, os.X_OK) or p.suffix not in (".md", ".txt", ""))]
        print(f"{name}: {total} item(s) @ {commit[:12]}" + (f" — {len(scripts)} script/asset file(s), review them" if scripts else ""))
        if report:
            print("\n".join(report) + f"\n  review: git diff -- {rel(out)}")
    LOCK.write_text("# generated by `kit import` — commit it\n" +
                    yaml.safe_dump(lock, sort_keys=True, allow_unicode=True), encoding="utf-8")


def import_items(cfg: Config, imp: dict, repo: Path) -> dict:
    prefix = imp.get("prefix", "")
    md_kind = imp.get("type", "agent")
    if md_kind not in ("agent", "workflow"):
        die(f"{imp['name']}: type must be agent or workflow")
    pulled: dict[str, dict] = {"skill": {}, "agent": {}, "workflow": {}}
    skill_dirs: list[Path] = []
    md_files: list[Path] = []
    for pattern in imp.get("include") or ["**/SKILL.md"]:
        matches = sorted(repo.glob(pattern))
        if not matches:
            warn(f"{imp['name']}: pattern '{pattern}' matched nothing")
        for m in matches:
            if ".git" in m.parts:
                continue
            if m.is_file() and m.name == "SKILL.md":
                skill_dirs.append(m.parent)
            elif m.is_dir() and (m / "SKILL.md").exists():
                skill_dirs.append(m)
            elif m.is_dir():
                skill_dirs += [p.parent for p in sorted(m.glob("*/SKILL.md"))]
            elif m.suffix == ".md":
                md_files.append(m)
    for d in dict.fromkeys(skill_dirs):
        meta, body = parse_md(d / "SKILL.md")
        new = prefix + str(meta.get("name") or d.name)
        tree: FileMap = {}
        for f in sorted(d.rglob("*")):
            if f.is_file() and f.name != ".DS_Store":
                tree[f.relative_to(d).as_posix()] = (f.read_bytes(), os.access(f, os.X_OK))
        tree["SKILL.md"] = (dump_md({**meta, "name": new}, body).encode(), False)
        pulled["skill"][new] = tree
    for f in dict.fromkeys(md_files):
        meta, body = parse_md(f)
        if not meta.get("description"):
            warn(f"{imp['name']}: skipped {f.relative_to(repo)} (no description in frontmatter)")
            continue
        new = prefix + str(meta.get("name") or f.stem)
        if md_kind == "agent":
            meta = normalise_agent(cfg, meta)
        pulled[md_kind][new] = (dump_md({**meta, "name": new}, body).encode(), False)
    return pulled


def item_files(pulled: dict) -> dict[str, FileMap]:
    """`import_items` output keyed like kit.lock (`skill/<name>`), each item's files as written under vendor/."""
    return {f"{k}/{n}": (p if k == "skill" else {f"{n}.md": p}) for k, e in pulled.items() for n, p in e.items()}


def vendored_files(name: str) -> dict[str, FileMap]:
    """What `kit import` last wrote for an import, in the shape of `item_files`."""
    base, out = VENDOR / name, {}
    for d in sorted(p.parent for p in (base / "skills").glob("*/SKILL.md")):
        out[f"skill/{d.name}"] = {f.relative_to(d).as_posix(): (f.read_bytes(), os.access(f, os.X_OK))
                                  for f in sorted(d.rglob("*")) if f.is_file() and f.name != ".DS_Store"}
    for kind in ("agent", "workflow"):
        for f in sorted((base / KINDS[kind]).glob("*.md")):
            out[f"{kind}/{f.stem}"] = {f.name: (f.read_bytes(), False)}
    return out


def front(data: bytes) -> dict:
    m = FM_RE.match(data.decode("utf-8", "replace"))
    meta = yaml.safe_load(m.group(1)) if m else {}
    return meta if isinstance(meta, dict) else {}


def item_changes(imp_name: str, old: dict[str, FileMap], new: dict[str, FileMap],
                 ours: list[Item], texts: list[tuple[str, str]]) -> list[str]:
    """What moves between two versions of an import, item by item: files (+/- lines), frontmatter keys and scripts
    (they decide when an item fires and what it may run), and the local items (`scan(SRC, "local")`, `extends`
    still set) that extend or cite it (`citing_texts`)."""
    lines: list[str] = []
    for key in sorted(old.keys() | new.keys()):
        a, b = old.get(key) or {}, new.get(key) or {}
        if a == b:
            continue
        kind, name = key.split("/", 1)
        if not b:
            lines.append(f"  - {key} (removed upstream)")
        else:
            files = []
            for f in sorted(a.keys() | b.keys()):
                if a.get(f) == b.get(f):
                    continue
                if f not in b:
                    files.append(f"{f} (removed)")
                    continue
                diff = list(difflib.unified_diff(a[f][0].decode("utf-8", "replace").splitlines() if f in a else [],
                                                 b[f][0].decode("utf-8", "replace").splitlines(), lineterm="", n=0))
                plus = sum(1 for d in diff if d.startswith("+") and not d.startswith("+++"))
                minus = sum(1 for d in diff if d.startswith("-") and not d.startswith("---"))
                files.append(f"{f} +{plus} -{minus}" if f in a else f"{f} (new) +{plus}")
            lines.append(f"  {'~' if a else '+'} {key}: " + ", ".join(files))
            main = "SKILL.md" if kind == "skill" else f"{name}.md"
            fa, fb = (front(a[main][0]) if main in a else {}), front(b[main][0]) if main in b else {}
            keys = sorted(k for k in fa.keys() | fb.keys() if fa.get(k) != fb.get(k))
            if a and keys:
                lines.append(f"      ⚠ frontmatter changed: {', '.join(keys)}")
            scripts = [f for f in sorted(b)
                       if a.get(f) != b[f] and (b[f][1] or Path(f).suffix not in (".md", ".txt", ""))]
            if scripts:
                lines.append(f"      ⚠ script added or changed: {', '.join(scripts)}")
        extended = [i.id for i in ours if i.kind == kind and i.meta.get("extends") == f"{imp_name}/{name}"]
        cited = [label for label, text in texts if label not in extended and cites(name, text)] if kind == "skill" else []
        for what, users in (("extended by" if b else "kit check will fail on", extended), ("cited by", cited)):
            if users:
                lines.append(f"      {what}: {', '.join(users)}")
    return lines


def check_import(cfg: Config, imp: dict, locked: dict, ours: list[Item], texts: list[tuple[str, str]]) -> bool:
    """`kit import --check`: how far an import is behind its `ref`, and what that would change in vendor/,
    without writing anything. True when an imported item would change."""
    name = imp["name"]
    url, local = resolve_source(imp["source"])
    if local:
        print(f"{name}: local source, nothing pinned")
        return False
    pinned = locked.get("commit")
    if not pinned:
        print(f"{name}: not imported yet (run `kit import {name}`)")
        return True
    if locked.get("source") != imp["source"]:
        print(f"{name}: source changed in kit.yaml (run `kit import {name}`)")
        return True
    ref = imp.get("ref") or "HEAD"
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        git("init", "-q", str(repo))
        git("remote", "add", "origin", url, cwd=repo)
        git("fetch", "-q", "--filter=blob:none", "origin", ref, cwd=repo)  # history, blobs only when read
        head = git("rev-parse", "FETCH_HEAD^{commit}", cwd=repo)  # an annotated tag: its commit, as fetch() pins
        if head == pinned:
            print(f"{name}: up to date ({pinned[:8]})")
            return False
        on_ref = subprocess.run(["git", "merge-base", "--is-ancestor", pinned, head], cwd=repo,
                                capture_output=True).returncode == 0
        behind = (f"{git('rev-list', '--count', f'{pinned}..{head}', cwd=repo)} commit(s) behind {ref}" if on_ref
                  else f"pinned commit is no longer on {ref}")
        git("checkout", "-q", head, cwd=repo)
        report = item_changes(name, vendored_files(name), item_files(import_items(cfg, imp, repo)), ours, texts)
    if on_ref and not report:
        print(f"{name}: {behind} ({pinned[:8]} → {head[:8]}), no imported item changed")
        return False
    print(f"{name}: {behind} ({pinned[:8]} → {head[:8]})" + ("\n" + "\n".join(report) if report else ""))
    return True
