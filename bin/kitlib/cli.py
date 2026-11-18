"""Command line: the parser of every command."""

from __future__ import annotations

import argparse
import os
import sys

from kitlib.paths import KINDS
from kitlib.commands import cmd_build, cmd_check, cmd_conf, cmd_list, cmd_migrate, cmd_new
from kitlib.imports import cmd_import
from kitlib.install import cmd_install, cmd_journal, cmd_serve, cmd_uninstall


def main(doc: str) -> None:
    """`doc`: bin/kit's docstring, its first paragraph is the description of `kit --help`."""
    ap = argparse.ArgumentParser(prog="kit", description=doc.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("check", help="validate sources")
    p.add_argument("--dist", action="store_true", help="also fail if dist/ is stale")
    p.set_defaults(fn=cmd_check)

    p = sub.add_parser("list", help="list skills, agents and workflows")
    p.add_argument("--orphans", action="store_true", help="only the agents no area role, fallback or entry names")
    p.set_defaults(fn=cmd_list)
    p = sub.add_parser("migrate", help="print the conversion of a legacy setting (read-only)")
    p.add_argument("what", choices=["areas", "agents"])
    p.set_defaults(fn=cmd_migrate)
    p = sub.add_parser("conf", help="the settings a repo resolves to, with the scopes that matched")
    p.add_argument("repo", nargs="?", help="owner/repo (default: the current directory's repo)")
    p.set_defaults(fn=cmd_conf)
    sub.add_parser("build", help="generate dist/ for every target").set_defaults(fn=cmd_build)

    p = sub.add_parser("new", help="scaffold a skill, agent or workflow in src/")
    p.add_argument("kind", choices=list(KINDS))
    p.add_argument("name")
    p.set_defaults(fn=cmd_new)


    p = sub.add_parser("import", help="fetch imports declared in kit.yaml into vendor/")
    p.add_argument("names", nargs="*")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--update", action="store_true", help="move past the commits pinned in kit.lock")
    g.add_argument("--check", action="store_true",
                   help="show how far each import is behind its ref and which items would change; writes nothing. "
                        "Exits 0 when nothing to import, 1 when an imported item changed, the pin left its ref or an "
                        "import must be (re)imported, 3 when a check failed (git error, unreadable upstream content or an "
                        "unknown NAME; the other imports are still checked)")
    p.set_defaults(fn=cmd_import)

    for name, fn in (("install", cmd_install), ("uninstall", cmd_uninstall)):
        p = sub.add_parser(name, help=f"{name} into a project (or ~ with --global)")
        g = p.add_mutually_exclusive_group(required=True)
        g.add_argument("path", nargs="?")
        g.add_argument("--global", dest="global_", action="store_true")
        g.add_argument("--workspace", help="every local repo of a workspace of local/adorno.yaml")
        p.add_argument("--force", action="store_true", help="overwrite or remove files you modified")
        if name == "install":
            p.add_argument("--targets", help="comma-separated, default: kit.yaml targets")
            p.add_argument("--link", action="store_true", help="symlink to dist/ instead of copying")
            p.add_argument("--dry-run", action="store_true")
            p.add_argument("--public-only", action="store_true", help="ignore local/ (your personal layer)")
        p.set_defaults(fn=fn)

    p = sub.add_parser("journal", help="a run's journal (skill adorno-journal)")
    p.add_argument("action", choices=["enrich"], help="enrich: read the run's Claude Code transcripts again")
    p.add_argument("run", help="a run id, or the name of its folder under ~/.adorno/runs")
    p.set_defaults(fn=cmd_journal)
    p = sub.add_parser("serve", help="serve the run journals and their viewer on 127.0.0.1 (read-only)")
    p.add_argument("--port", type=int, default=8765, help="default 8765; 0: any free port")
    p.add_argument("--runs", help="the folder of the runs (default: ~/.adorno/runs)")
    p.set_defaults(fn=cmd_serve)

    args = ap.parse_args()
    try:
        args.fn(args)
    except BrokenPipeError:  # `kit list | head`
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
