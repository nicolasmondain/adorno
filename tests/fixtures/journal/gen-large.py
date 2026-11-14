#!/usr/bin/env python3
"""Prints a large synthetic journal (JSON Lines on stdout): what a long run with many agents looks like, to check that
the viewer stays within its drawing budget. Standard library, fixed seed: the same journal every time.

Usage: gen-large.py [EVENTS] (default 10000)
"""
import json
import random
import sys

RUN, SESSION = "20260102T090000-2000-9", "sess-large"
AGENTS = 30


def stamp(ms):
    seconds, millis = divmod(ms, 1000)
    hours, rest = divmod(9 * 3600 + seconds, 3600)
    return f"2026-01-02T{hours:02d}:{rest // 60:02d}:{rest % 60:02d}.{millis:03d}Z"


def main(total):
    rng = random.Random(7)
    out = []

    def event(at, kind, actor="session", **fields):
        out.append({"v": 1, "t": stamp(at), "run": RUN, "session": SESSION, "actor": actor,
                    "parent": "session" if actor.startswith("agent:") else None, "type": kind, **fields})

    event(0, "run.begin", workflow="workflow:feature:build", mode="auto", level="L2", repos=["acme/large"], dir="/synthetic")
    per_agent = max(4, (total - 4 - 3 * AGENTS) // AGENTS)
    for n in range(AGENTS):
        name = f"agent:g{n:02d}"
        about = {"id": f"g{n:02d}", "type": "adorno-agent-feat-back" if n % 3 else "adorno-agent-review-code"}
        at = 1000 + n * 40000 + rng.randrange(2000)   # three agents alive at a time, give or take
        event(at, "agent.spawn", agent=about, tool="claude")
        # as the hooks record it: the model the instance runs on is on the session's Agent tool call
        event(at + 1, "tool.call", tool="Agent", input=f"{about['type']}: part {n}", dur=4, agent=about, model="claude-opus-5-5")
        for k in range(per_agent):
            at += rng.randrange(20, 240)
            if k % 9 == 0:
                event(at, "model.turn", actor=name, model="claude-opus-5-5", dur=rng.randrange(200, 2500), stop="tool_use",
                      tokens={"in": rng.randrange(200, 4000), "out": rng.randrange(20, 600), "cache_read": 0, "cache_write": 0})
            else:
                event(at, "tool.call", actor=name, tool=rng.choice(["Read", "Edit", "Bash", "Grep"]), input=f"src/file{k % 40}.ts",
                      dur=rng.randrange(5, 120))
        event(at + 500, "agent.return", actor=name, agent=about)
    # a question then a refusal of the guard at the same instant: drawn as one mark once the buckets widen
    for decision in ("ask", "deny"):
        event(600000, "guard", decision=decision, reason="adorno: outside the worktree", command="rm -r /synthetic")
    event(max(ms_of(e) for e in out) + 1000, "run.end", workflow="workflow:feature:build", outcome="ended")
    out.sort(key=lambda e: e["t"])
    for e in out:
        sys.stdout.write(json.dumps(e, separators=(",", ":")) + "\n")


def ms_of(e):
    hours, minutes, rest = e["t"][11:-1].split(":")
    return (int(hours) - 9) * 3600000 + int(minutes) * 60000 + int(float(rest) * 1000 + 0.5)


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 10000)
