#!/usr/bin/env python3
"""Claude Code PreToolUse hook for Bash: stops the writes that must go through adorno's scripts.

Usage (bin/kit install writes it into your Claude Code settings):  guard_bash.py deny|ask
Reads the hook event on stdin. A command that pushes, publishes on GitHub, edits adorno's registry or runs, or moves
HOME for an adorno script gets `deny` (in a repo install) or `ask` (in a global install, which applies to every
project). Permission rules only compare the start of a command; this reads it the way a shell does: chained
commands (; && || |), subshells, `bash -c '…'`, `eval`, `env`/`sudo`/`command` wrappers, `git -C dir`, quotes.
A command it cannot read asks. Anything else passes untouched (no output, exit 0).
"""
import json
import re
import shlex
import sys

WRAPPERS = {"command", "exec", "builtin", "nohup", "time", "sudo", "doas", "nice", "xargs", "stdbuf", "setsid"}
WRAPPER_ARGS = {"timeout": 1}
WRAPPER_OPTS_WITH_VALUE = {"-u", "--user", "-g", "--group", "-n", "--adjustment", "-s", "--signal", "-k", "--kill-after",
                           "-C", "--chdir", "-h", "--host", "-p", "--prompt", "-I", "-L", "-P", "-i", "-o", "-e"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "fish"}
READ_ONLY = {"cat", "jq", "ls", "head", "tail", "less", "more", "grep", "rg", "wc", "stat", "file", "test", "[", "echo",
             "printf", "diff", "cmp", "realpath", "dirname", "basename", "find"}
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
GH_OPTS_WITH_VALUE = {"-R", "--repo", "--hostname"}
GH_WRITES = {
    "pr": {"create", "comment", "review", "merge", "close", "edit", "ready", "reopen", "lock", "unlock"},
    "issue": {"create", "comment", "edit", "close", "reopen", "delete", "transfer", "lock", "pin"},
    "release": None, "repo": {"create", "delete", "edit", "rename", "archive", "fork", "sync"},
    "workflow": {"run", "enable", "disable"}, "run": {"rerun", "cancel", "delete"},
    "label": None, "secret": None, "variable": None, "gist": None, "ruleset": None,
}
ADORNO_STATE = re.compile(r"\.adorno/(registry\.json|runs(/|$))")
OPS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;", "\n"}

MESSAGES = {
    "push": "push with adorno-github/scripts/git-push (a branch without PR) or pr-push (a PR's branch): they check the "
            "run's level and the repo's rights",
    "gh": "publish on GitHub with the adorno-github scripts (pr-comment, pr-reply, pr-review-submit, pr-open, "
          "ci-rerun…): they check the run's level and the repo's rights",
    "api": "`gh api` that writes (-f, -F, --input, -X POST…): use the adorno-github scripts",
    "curl": "a write to api.github.com: use the adorno-github scripts",
    "state": "adorno's registry and runs are written by bin/kit install and run-begin / run-end only",
    "home": "an adorno script reads its registry and runs from your real ~/.adorno: do not move HOME for it",
}


def words(command):
    lex = shlex.shlex(command.replace("\r", " ").replace("\n", " ; "), posix=True, punctuation_chars=";&|()<>")
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def simple_commands(tokens):
    cur = []
    for t in tokens:
        if t in OPS or set(t) <= set(";&|()"):
            if cur:
                yield cur
            cur = []
        else:
            cur.append(t)
    if cur:
        yield cur


def strip(cmd):
    """Leading assignments and wrappers off -> (assignments, the real command words)."""
    env, i = [], 0
    while i < len(cmd):
        w = cmd[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w):
            env.append(w); i += 1
        elif w == "env":
            i += 1
            while i < len(cmd) and (cmd[i].startswith("-") or "=" in cmd[i]):
                if cmd[i] in ("-u", "--unset", "-C", "--chdir", "-S", "--split-string"):
                    i += 1
                elif "=" in cmd[i] and not cmd[i].startswith("-"):
                    env.append(cmd[i])
                i += 1
        elif w in WRAPPERS or w in WRAPPER_ARGS:
            i += 1
            while i < len(cmd) and cmd[i].startswith("-"):
                i += 2 if cmd[i] in WRAPPER_OPTS_WITH_VALUE else 1
            i += WRAPPER_ARGS.get(w, 0)
        else:
            break
    return env, cmd[i:]


def program(word):
    return word.rsplit("/", 1)[-1]


def git_sub(args):
    i = 0
    while i < len(args):
        a = args[i]
        if a in GIT_OPTS_WITH_VALUE:
            i += 2
        elif a.startswith("-"):
            i += 1
        else:
            return a
    return None


def gh_verdict(args):
    rest, i = [], 0
    while i < len(args):
        if args[i] in GH_OPTS_WITH_VALUE:
            i += 2
            continue
        rest.append(args[i]); i += 1
    if not rest:
        return None
    group = rest[0]
    if group == "api":
        flags = rest[1:]
        if "graphql" in flags:
            # GraphQL always POSTs: only a mutation (or a body read from a file) writes
            body = " ".join(flags)
            return "api" if re.search(r"\bmutation\b", body, re.I) or "--input" in flags else None
        for j, f in enumerate(flags):
            if f in ("-f", "-F", "--field", "--raw-field", "--input") or re.match(r"^(-[fF].|--(raw-)?field=|--input=)", f):
                return "api"
            method = None
            if f in ("-X", "--method") and j + 1 < len(flags):
                method = flags[j + 1]
            elif re.match(r"^(-X|--method=)", f):
                method = re.sub(r"^(-X|--method=)", "", f)
            if method and method.upper() not in ("GET", "HEAD"):
                return "api"
        return None
    if group in GH_WRITES:
        subs = GH_WRITES[group]
        verb = next((w for w in rest[1:] if not w.startswith("-")), None)
        if subs is None:
            return "gh" if verb not in (None, "list", "view", "download") else None
        return "gh" if verb in subs else None
    return None


def check(command, depth=0):
    """-> a MESSAGES key, or None. Raises ValueError on a command it cannot read."""
    if depth > 4:
        raise ValueError("nested too deep")
    tokens = words(command)
    whole_mentions_adorno = "adorno" in command
    for cmd in simple_commands(tokens):
        env, words_ = strip(cmd)
        moved_home = any(e.startswith("HOME=") for e in env) or (
            words_[:1] == ["export"] and any(w.startswith("HOME=") for w in words_[1:]))
        if moved_home and whole_mentions_adorno:
            return "home"
        if not words_:
            continue
        prog, args = program(words_[0]), words_[1:]
        if prog in SHELLS:
            for j, a in enumerate(args):
                if re.match(r"^-[a-z]*c[a-z]*$", a) and j + 1 < len(args):
                    found = check(args[j + 1], depth + 1)
                    if found:
                        return found
                    break
            continue
        if prog == "eval":
            found = check(" ".join(args), depth + 1)
            if found:
                return found
            continue
        if prog == "git" and git_sub(args) == "push":
            return "push"
        if prog == "gh":
            found = gh_verdict(args)
            if found:
                return found
        if prog == "curl" and any("api.github.com" in a for a in args) and any(
                re.match(r"^(-d|--data.*|-F|--form.*|-T|--upload-file|--json)$", a)
                or re.match(r"^-X(?!GET$)(?!HEAD$).+", a)
                or (a in ("-X", "--request") and j + 1 < len(args) and args[j + 1].upper() not in ("GET", "HEAD"))
                for j, a in enumerate(args)):
            return "curl"
        writes_state = any(ADORNO_STATE.search(a) for a in args)
        redirected = any(t in (">", ">>") for t in cmd) and any(
            ADORNO_STATE.search(cmd[k + 1]) for k, t in enumerate(cmd[:-1]) if t in (">", ">>"))
        if redirected or (writes_state and prog not in READ_ONLY and not prog.startswith("run-")
                          and "adorno-github/scripts/" not in words_[0]):
            return "state"
    return None


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] in ("deny", "ask") else "deny"
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    if event.get("tool_name") != "Bash":
        return 0
    command = str((event.get("tool_input") or {}).get("command") or "")
    try:
        found = check(command)
        decision, reason = (mode, MESSAGES[found]) if found else (None, None)
    except ValueError as e:
        decision, reason = "ask", f"adorno could not read this command ({e}): check it is not a direct write"
    if decision:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": decision,
            "permissionDecisionReason": "adorno: " + reason}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
