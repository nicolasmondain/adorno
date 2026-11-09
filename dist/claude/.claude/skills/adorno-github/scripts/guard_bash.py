#!/usr/bin/env python3
"""Claude Code PreToolUse hook for Bash: stops the writes that must go through adorno's scripts.

Usage (bin/kit install writes it into the settings of Claude Code, Codex and Gemini CLI):
    guard_bash.py deny|ask [--format=claude|codex|gemini]
Reads the hook event on stdin. A command that pushes, publishes on GitHub, edits adorno's registry or runs, or moves
HOME for an adorno script gets `deny` (in a repo install) or `ask` (in a global install, which applies to every
project). Permission rules only compare the start of a command; this reads it the way a shell does: chained
commands (; && || |), subshells, $( … ) and backticks, `bash -c '…'`, `eval`, `env`/`sudo`/`command` wrappers,
`git -C dir`, git aliases, quotes, heredocs; it reads the code given to python -c / node -e and the local scripts a command
runs (./x.sh, bash x.sh, python3 x.py). A command it cannot read (a variable as program, unbalanced quotes) asks, and
so does a bug in the guard. Anything else passes untouched (no output, exit 0).

Inside a run (Claude Code only), the end of a workflow goes through without a prompt: a command made only of
`git add` / `git commit` with listed flags (never --no-verify, -f, a message read from outside the repo),
`git push origin BRANCH|HEAD` (never forced, never the base), `gh pr create` for the current branch, `gh pr
edit|ready N` on your own open PR (listed flags, a body file inside the repo), a closed list of adorno-github scripts
(never run-begin: opening a run stays the owner's call), `cd` and read-only commands gets `allow` when the session's
open run covers the repo at the level each needs (run-check, git-push --check: max_level, permissions.deny, denied
actions, no dry run). That is how a repo's own commit_skill and pr_skill push and open a PR (workflow:pr:ship). Any
other flag or shape: the decision above, unchanged.
"""
import glob
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

WRAPPERS = {"command", "exec", "builtin", "nohup", "time", "sudo", "doas", "nice", "xargs", "stdbuf", "setsid"}
WRAPPER_ARGS = {"timeout": 1}
WRAPPER_OPTS_WITH_VALUE = {"-u", "--user", "-g", "--group", "-n", "--adjustment", "-s", "--signal", "-k", "--kill-after",
                           "-C", "--chdir", "-h", "--host", "-p", "--prompt", "-I", "-L", "-P", "-i", "-o", "-e"}
KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "!", "{", "}", "done", "fi"}
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
    "session": "a run belongs to the session that opened it: CLAUDE_CODE_SESSION_ID is set by Claude Code, not by "
               "a command",
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
        elif w in KEYWORDS:
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


INTERPRETERS = {"python", "python3", "python2", "node", "nodejs", "deno", "bun", "perl", "ruby", "php", "osascript"}
INLINE_FLAGS = {"-c", "-e", "-E", "--eval", "-p", "--print", "-r"}
SCRIPT_LIMIT = 256 * 1024
# what a file or inline code must not contain (it is read as text, not run)
CODE_WRITES = [
    (re.compile(r"\bgit\b[^\n;|&]*\bpush\b"), "push"),
    (re.compile(r"\bgh\b[^\n;|&]*\b(pr|issue)\b[^\n;|&]*\b(create|comment|review|merge|close|edit|reopen)\b"), "gh"),
    (re.compile(r"\bgh\b[^\n;|&]*\brelease\b[^\n;|&]*\b(create|upload|edit|delete)\b"), "gh"),
    (re.compile(r"\bgh\b[^\n;|&]*\bapi\b[^\n;|&]*(\s-[fFX]|\s--(field|raw-field|input|method)\b)"), "api"),
    (re.compile(r"api\.github\.com"), "curl"),
    (re.compile(r"\.adorno/(registry\.json|runs/)"), "state"),
]
MESSAGES.update({
    "script": "this script would push or publish on GitHub itself: use the adorno-github scripts",
    "alias": "this git alias pushes: push with adorno-github/scripts/git-push or pr-push",
})


HEREDOC = re.compile(r"(?<!<)<<(-?)[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")


def heredocs(command):
    """-> (the command without its heredoc bodies, [(program fed by the heredoc, body, quoted)]). A body is the stdin of
    one command: data for `cat > f`, code for a shell or an interpreter (python3 - <<EOF), so the caller checks it
    accordingly. An unquoted body is still expanded by the shell ($( … ) inside it runs).
    Read the way the shell reads it: a `<<` inside quotes is text, not an operator (`-m "a;git <<'EOF'"` must not hide
    the next lines), one inside $( … ) or backticks is code. The operators are removed from the command: the body is
    checked apart, and the operator alone would read as unterminated."""
    if "<<" in command and any(t in command for t in ("${", "((", "<(", ">(", "[[", "$'", '$"', "\\\n")):
        # forms this lexer does not model (parameter expansion, arithmetic, process substitution, ANSI-C quotes,
        # line continuations): with a heredoc around, which lines are body is not certain, so it asks
        raise ValueError("a heredoc next to an expansion this guard does not read")
    lines, out, bodies, stack, i = command.split("\n"), [], [], [], 0
    while i < len(lines):
        line = lines[i]; i += 1
        ops, j, n, seg = [], 0, len(line), 0  # seg: where the current simple command starts on this line
        while j < n:
            c, top = line[j], (stack[-1] if stack else None)
            if top == "'":
                if c == "'":
                    stack.pop()
                j += 1; continue
            if c == "\\":
                j += 2; continue
            if top == '"':
                if c == '"':
                    stack.pop()
                elif line.startswith("$(", j):
                    stack.append("$("); j += 2; seg = j; continue
                elif c == "`":
                    stack.append("`"); seg = j + 1
                j += 1; continue
            # code: top level, $( … ), ( … ) or backticks
            if c in "'\"":
                stack.append(c); j += 1; continue
            if c == "`":
                stack.pop() if top == "`" else stack.append("`")
                j += 1; seg = j; continue
            if line.startswith("$(", j):
                stack.append("$("); j += 2; seg = j; continue
            if c == "(":
                stack.append("("); j += 1; seg = j; continue
            if c == ")" and top in ("$(", "("):
                stack.pop(); j += 1; seg = j; continue
            if c in ";&|":
                j += 1; seg = j; continue
            if c == "#" and (j == 0 or line[j - 1] in " \t;&|("):
                break  # a comment: nothing after it is an operator
            if line.startswith("<<", j) and not line.startswith("<<<", j):
                m = HEREDOC.match(line, j)
                if not m:
                    raise ValueError("unreadable heredoc")
                # only where bash surely reads an operator: top level, or right inside $( … ) (even within "…")
                if stack and (stack[-1] != "$(" or any(x not in ("$(", '"') for x in stack)):
                    raise ValueError("a heredoc inside an expansion")
                ops.append((m.start(), m.end(), m.group(1) == "-", bool(m.group(2)), m.group(3), seg))
                j = m.end(); continue
            j += 1
        if ops and stack and stack[-1] in ("'", '"'):
            raise ValueError("a heredoc on a line that ends inside quotes")
        kept, prev = [], 0
        for start, end, *_ in ops:
            kept += [line[prev:start], " "]; prev = end
        out.append("".join(kept) + line[prev:])
        for start, end, tabs, quoted, delim, seg_start in ops:
            body = []
            while i < len(lines) and (lines[i].lstrip("\t") if tabs else lines[i]) != delim:
                body.append(lines[i]); i += 1
            if i >= len(lines):
                raise ValueError("unterminated heredoc")
            i += 1
            try:
                env, ws = strip(words(line[seg_start:start]))
            except ValueError:
                ws = []
            bodies.append((program(ws[0]) if ws else "", "\n".join(body), quoted))
    return "\n".join(out), bodies


def substitutions(command):
    """The commands inside $( … ) and ` … ` (nested ones included), which the shell runs before the rest."""
    out, i, n = [], 0, len(command)
    while i < n:
        if command.startswith("$(", i) and not command.startswith("$((", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if command.startswith("$(", j):
                    depth += 1; j += 2; continue
                if command[j] == ")":
                    depth -= 1
                j += 1
            if depth:
                raise ValueError("unbalanced $(")
            out.append(command[i + 2:j - 1]); i = j
        elif command[i] == "`":
            j = command.find("`", i + 1)
            if j < 0:
                raise ValueError("unbalanced backtick")
            out.append(command[i + 1:j]); i = j + 1
        else:
            i += 1
    return out


def scan_code(text):
    for pattern, key in CODE_WRITES:
        if pattern.search(text):
            return key
    return None


def git_alias(args, cwd):
    """-> what a git alias expands to ('push -f', '!sh …'), or None when the subcommand is not an alias."""
    sub = git_sub(args)
    if not sub:
        return None
    for j, a in enumerate(args):  # git -c alias.p=push p
        if a == "-c" and j + 1 < len(args) and args[j + 1].startswith(f"alias.{sub}="):
            return args[j + 1].split("=", 1)[1]
    where = cwd
    for j, a in enumerate(args):
        if a == "-C" and j + 1 < len(args):
            where = os.path.join(where or ".", os.path.expanduser(args[j + 1]))
    try:
        r = subprocess.run(["git", "config", "--get", f"alias.{sub}"], cwd=where or None, capture_output=True,
                           text=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() or None


def script_file(prog_word, args, prog, cwd):
    """-> the path of a local file this command runs (./x.sh, bash x.sh, python3 x.py), or None."""
    candidates = []
    if "/" in prog_word:
        candidates.append(prog_word)
    if prog in SHELLS | INTERPRETERS:
        rest = [a for a in args if not a.startswith("-")]
        if rest:
            candidates.append(rest[0])
    for c in candidates:
        path = os.path.join(cwd or ".", os.path.expanduser(c))
        if os.path.isfile(path):
            return path
    return None


def adorno_source(path):
    """adorno's own bin/kit and tests (they name these commands on purpose), inside an adorno source tree."""
    real = os.path.realpath(path)
    parts = real.split(os.sep)
    for k in range(len(parts) - 1, 0, -1):
        root = os.sep.join(parts[:k]) or os.sep
        rel = os.sep.join(parts[k:])
        if not (rel == os.path.join("bin", "kit") or re.match(r"^tests/[A-Za-z0-9_.-]+$", rel)):
            continue
        try:
            with open(os.path.join(root, "kit.yaml"), encoding="utf-8") as f:
                return re.search(r"(?m)^name:\s*adorno\s*$", f.read()) is not None
        except OSError:
            return False
    return False


def check(command, depth=0, cwd=None):
    """-> a MESSAGES key, or None. Raises ValueError on a command it cannot read."""
    if depth > 4:
        raise ValueError("nested too deep")
    command, bodies = heredocs(command)
    for prog, body, quoted in bodies:
        if prog in SHELLS:
            found = check(body, depth + 1, cwd)
        elif prog in INTERPRETERS:
            found = scan_code(body)
        else:
            found = None if quoted else next(filter(None, (check(x, depth + 1, cwd) for x in substitutions(body))), None)
        if found:
            return found
    for inner in substitutions(command):
        found = check(inner, depth + 1, cwd)
        if found:
            return found
    tokens = words(command)
    whole_mentions_adorno = "adorno" in command
    loops = {}  # for VAR in WORDS: what $VAR can be, globs expanded
    for cmd in simple_commands(tokens):
        if len(cmd) >= 3 and cmd[0] == "for" and cmd[2] == "in":
            names = []
            for w in cmd[3:]:
                found_ = sorted(glob.glob(os.path.join(cwd or ".", os.path.expanduser(w)))) if any(c in w for c in "*?[") else []
                names += [os.path.relpath(f, cwd or ".") for f in found_] or [w]
            loops[cmd[1]] = names
            continue
        env, words_ = strip(cmd)
        used = [v for v in loops if any(w in ("$" + v, "${" + v + "}") for w in words_)]
        if used and all("$" not in x for v in used for x in loops[v]):
            var = used[0]
            for value in loops[var]:
                expanded = [value if w in ("$" + var, "${" + var + "}") else w for w in words_]
                found = check(" ".join(shlex.quote(w) for w in expanded), depth + 1, cwd)
                if found:
                    return found
            continue
        exported = words_[1:] if words_[:1] in (["export"], ["declare"], ["typeset"], ["local"]) else []
        moved_home = any(e.startswith("HOME=") for e in env + exported)
        if moved_home and whole_mentions_adorno:
            return "home"
        if any(e.startswith(("CLAUDE_CODE_SESSION_ID=", "ADORNO_SESSION")) for e in env + exported) \
                or re.search(r"\bunset\b[^;&|]*\bCLAUDE_CODE_SESSION_ID\b", " ".join(cmd)):
            return "session"
        if not words_:
            continue
        prog, args = program(words_[0]), words_[1:]
        if "$" in prog:
            raise ValueError("the program is a variable")
        if prog in SHELLS:
            inline = next((args[j + 1] for j, a in enumerate(args)
                           if re.match(r"^-[a-z]*c[a-z]*$", a) and j + 1 < len(args)), None)
            if inline is not None:
                found = check(inline, depth + 1, cwd)
                if found:
                    return found
                continue
        if prog == "eval":
            found = check(" ".join(args), depth + 1, cwd)
            if found:
                return found
            continue
        if prog in INTERPRETERS:
            for j, a in enumerate(args):
                if a in INLINE_FLAGS and j + 1 < len(args):
                    found = scan_code(args[j + 1])
                    if found:
                        return found
        if prog == "git":
            sub = git_sub(args)
            if sub and "$" in sub:
                raise ValueError("the git subcommand is a variable")
            if sub == "push":
                return "push"
            alias = git_alias(args, cwd)
            if alias:
                if alias.startswith("!"):
                    if check(alias[1:], depth + 1, cwd) or scan_code(alias[1:]):
                        return "alias"
                elif re.match(r"^\s*push\b", alias) or scan_code("git " + alias):
                    return "alias"
        if prog == "gh":
            if any("$" in a for a in args[:3]):
                raise ValueError("a gh subcommand is a variable")
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
        is_adorno_script = "adorno-github/scripts/" in words_[0] or "adorno-watch/scripts/" in words_[0] \
            or "adorno-learn/scripts/" in words_[0] or "adorno-llm/scripts/" in words_[0]
        if redirected or (writes_state and prog not in READ_ONLY and not is_adorno_script):
            return "state"
        if not is_adorno_script:
            path = script_file(words_[0], args, prog, cwd)
            if path and os.path.getsize(path) <= SCRIPT_LIMIT and not adorno_source(path):
                try:
                    with open(path, encoding="utf-8", errors="replace") as f:
                        if scan_code(f.read()):
                            return "script"
                except OSError:
                    pass
    return None


HERE = os.path.dirname(os.path.realpath(__file__))
SKILLS_ROOT = os.path.dirname(os.path.dirname(HERE))
SAFE_READS = READ_ONLY - {"find"}
SUBST = "__ADORNO_SUBST__"
GIT_READS = {"status", "diff", "log", "show", "rev-parse"}
PUSH_FLAGS = {"-u", "--set-upstream", "-q", "--quiet", "-v", "--verbose", "--progress", "--no-progress"}
# every flag not listed here sends the command back to the normal decision (git accepts abbreviated long options:
# a blocklist would miss --no-verif)
ADD_FLAGS = {"-A", "--all", "-u", "--update", "-N", "--intent-to-add", "-v", "--verbose", "--"}
COMMIT_FLAGS = {"-q", "--quiet", "-a", "--all", "-s", "--signoff", "--amend", "--no-edit", "--allow-empty", "-S",
                "-v", "--verbose"}
COMMIT_VALUED = {"-m", "--message", "-F", "--file"}
GH_FLAGS = {"create": {"-d", "--draft", "--fill"}, "edit": set(), "ready": set()}
GH_VALUED = {"create": {"-t", "--title", "-F", "--body-file", "-b", "--body", "-r", "--reviewer", "-l", "--label",
                        "-a", "--assignee"},
             "edit": {"-t", "--title", "-F", "--body-file", "-b", "--body", "--add-label", "--remove-label"},
             "ready": set()}
# adorno's scripts that may run without a prompt: read-only, or checking require_level themselves. Never run-begin
# (opening a run, and its level, is the owner's call), nor the scripts that send data out or write local/.
ALLOWED_SCRIPTS = {"repo-conf", "run-check", "run-end", "pr-status", "pr-areas", "pr-diff", "pr-feedback-fetch",
                   "issue-fetch", "ci-wait", "ci-failed", "pr-workspace", "git-push", "pr-push", "pr-open", "pr-edit",
                   "pr-ready"}


def blank_substitutions(command):
    """The command with every $( … ) and ` … ` replaced by one marker word (their content is checked apart)."""
    out, i, n = [], 0, len(command)
    while i < n:
        if command.startswith("$(", i) and not command.startswith("$((", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if command.startswith("$(", j):
                    depth += 1; j += 2; continue
                if command[j] == ")":
                    depth -= 1
                j += 1
            out.append(SUBST); i = j
        elif command[i] == "`":
            j = command.find("`", i + 1)
            if j < 0:
                raise ValueError("unbalanced backtick")
            out.append(SUBST); i = j + 1
        else:
            out.append(command[i]); i += 1
    return "".join(out)


def without_redirects(cmd):
    """-> the words without their redirections, or None when one writes to anything but /dev/null or a descriptor."""
    out, i = [], 0
    while i < len(cmd):
        t = cmd[i]
        if t in (">", ">>"):
            if out and out[-1].isdigit():
                out.pop()
            target = cmd[i + 1] if i + 1 < len(cmd) else ""
            if target == "&" and i + 2 < len(cmd) and cmd[i + 2].isdigit():
                i += 3; continue
            if target != "/dev/null":
                return None
            i += 2; continue
        if t == ">&" and i + 1 < len(cmd) and cmd[i + 1].isdigit():
            if out and out[-1].isdigit():
                out.pop()
            i += 2; continue
        if t in ("<", "<&", "<>"):  # input from a file: `-F - < ~/.ssh/key` would publish it
            return None
        out.append(t); i += 1
    return out


def adorno_script(word, cwd):
    """True when the word runs one of ALLOWED_SCRIPTS, in the adorno-github folder this guard ships in."""
    path = os.path.realpath(os.path.join(cwd or ".", os.path.expanduser(word)))
    return os.path.isfile(path) and os.path.dirname(path) == HERE and os.path.basename(path) in ALLOWED_SCRIPTS


def toplevel(here):
    try:
        r = subprocess.run(["git", "-C", here, "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                           timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None


def repo_root(here):
    """The repo's toplevel, unless it is your home or above it (a dotfiles repo would cover everything)."""
    top, home = toplevel(here), os.path.realpath(os.path.expanduser("~"))
    return top if top and home != top and not home.startswith(top + os.sep) else None


def safe_file(path, here):
    """A file a commit message or a PR body may be read from: the agents' own folders only — the repo's .agent-run/,
    ~/.adorno/runs/ and ~/.adorno/tmp/, a temp folder named adorno*. Anything else (~/.ssh/…, .env, another tool's
    file in /tmp) could be published."""
    full = os.path.realpath(os.path.join(here, os.path.expanduser(path)))
    root = repo_root(here)
    roots = ([os.path.join(root, ".agent-run")] if root else []) + [
        os.path.realpath(os.path.expanduser(p)) for p in ("~/.adorno/runs", "~/.adorno/tmp")]
    if any(full.startswith(r + os.sep) for r in roots):
        return True
    for tmp in {os.path.realpath(tempfile.gettempdir()), os.path.realpath("/tmp")}:
        if full.startswith(tmp + os.sep) and os.path.relpath(full, tmp).split(os.sep)[0].startswith("adorno"):
            return True
    return False


def safe_dir(path, here):
    """A folder a script may work in: inside a repo (never its .git/), not your home nor above it."""
    full = os.path.realpath(os.path.join(here, os.path.expanduser(path)))
    root = repo_root(full)
    return bool(root) and ".git" not in os.path.relpath(full, root).split(os.sep)


def safe_paths(args, here):
    """Every argument of an allowed script that names an existing file or folder passes safe_file / safe_dir:
    `pr-edit … ~/.ssh/id_rsa` would publish it, `pr-workspace … --dir /etc` would work there."""
    for a in args:
        value = a.split("=", 1)[1] if a.startswith("--") and "=" in a else a
        full = os.path.join(here, os.path.expanduser(value))
        if value and os.path.exists(full):
            if not (safe_dir(value, here) if os.path.isdir(full) else safe_file(value, here)):
                return False
    return True


def options(args, flags, valued, here, files=()):
    """-> (positional words, {flag: value}) when every option is listed in flags / valued (`--x=v` allowed), and every
    value of a flag in files is "-" or a safe_file; else None."""
    pos, vals, i = [], {}, 0
    while i < len(args):
        a = args[i]
        if a.startswith("--") and "=" in a:
            k, v = a.split("=", 1)
        elif a in valued:
            if i + 1 >= len(args):
                return None
            k, v = a, args[i + 1]; i += 1
        elif a in flags:
            k, v = a, True
        elif a.startswith("-") and a != "-":
            return None
        else:
            pos.append(a); i += 1; continue
        if k not in valued and k not in flags:
            return None
        if k in files and v != "-" and not safe_file(str(v), here):
            return None
        vals[k] = v; i += 1
    return pos, vals


def push_branch(args):
    """`git push [flags] origin BRANCH | HEAD | BRANCH:BRANCH` -> (True, BRANCH or None for the current one); a bare
    push (git config decides its refspec), another remote, a refspec that renames, forced, --tags… -> (False, None)."""
    flags = [a for a in args if a.startswith("-")]
    rest = [a for a in args if not a.startswith("-")]
    if any(f not in PUSH_FLAGS for f in flags) or len(rest) != 2 or rest[0] != "origin":
        return False, None
    if rest[1] == "HEAD":
        return True, None
    ref = rest[1]
    if ":" in ref:
        src, dst = ref.split(":", 1)
        if src != dst:
            return False, None
        ref = src
    ref = re.sub(r"^refs/heads/", "", ref)
    if not ref or ref.startswith("+") or not re.match(r"^[A-Za-z0-9._/-]+$", ref):
        return False, None
    return True, ref


def allowable(command, cwd):
    """-> the checks that would let the whole command through without a prompt, or None when it is not made only of
    the end-of-workflow commands (see the module doc). Never raises."""
    try:
        stripped, bodies = heredocs(command)
        if any(not quoted or prog not in ("git", "cat") for prog, _, quoted in bodies):
            return None
        for inner in substitutions(stripped):
            # only `$(cat <<'EOF' … EOF)`: a message written inline, never a file read into it
            if [w for cmd in simple_commands(words(inner)) for w in cmd] not in ([], ["cat"]):
                return None
        tokens = words(blank_substitutions(stripped))
    except ValueError:
        return None
    if any(t in ("|", "&", "|&", "(", ")") for t in tokens):
        return None
    checks, here, wanted = [], cwd or os.getcwd(), False
    for cmd in simple_commands(tokens):
        ws = without_redirects(cmd)
        if ws is None or not ws or "$" in ws[0]:
            return None
        if strip(ws)[1] != ws:  # an assignment or a wrapper in front: not ours to approve
            return None
        prog, args = program(ws[0]), ws[1:]
        if prog == "cd" and ws[0] == "cd":
            if len(args) != 1:
                return None
            here = os.path.join(here, os.path.expanduser(args[0]))
        elif adorno_script(ws[0], here):
            if not safe_paths(args, here):
                return None
            wanted = True
        elif prog == "git" and ws[0] == "git":
            where, i = here, 0
            while i < len(args) and args[i] == "-C" and i + 1 < len(args):
                where = os.path.join(where, os.path.expanduser(args[i + 1])); i += 2
            sub, rest = (args[i], args[i + 1:]) if i < len(args) else (None, [])
            if sub in GIT_READS:
                if any(a.startswith("--output") for a in rest):
                    return None
                continue
            if sub == "add":
                if options(rest, ADD_FLAGS, set(), where) is None:
                    return None
                checks.append(("run", where, "L2", "")); wanted = True
            elif sub == "commit":
                if options(rest, COMMIT_FLAGS, COMMIT_VALUED, where, files=("-F", "--file")) is None:
                    return None
                checks.append(("run", where, "L2", "")); wanted = True
            elif sub == "push":
                fine, branch = push_branch(rest)
                if not fine:
                    return None
                checks.append(("push", where, branch)); wanted = True
            else:
                return None
        elif prog == "gh" and ws[0] == "gh":
            if any(SUBST in a for a in args):
                return None
            repos, rest, i = [], [], 0
            while i < len(args):
                if args[i] in ("-R", "--repo") and i + 1 < len(args):
                    repos.append(args[i + 1]); i += 2; continue
                if args[i].startswith("--repo="):
                    repos.append(args[i].split("=", 1)[1]); i += 1; continue
                rest.append(args[i]); i += 1
            if len(repos) > 1 or rest[:1] != ["pr"] or len(rest) < 2 or rest[1] not in GH_FLAGS:
                return None
            verb = rest[1]
            parsed = options(rest[2:], GH_FLAGS[verb], GH_VALUED[verb], here, files=("-F", "--body-file"))
            if parsed is None:
                return None
            pos = parsed[0]
            repo = repos[0] if repos else None
            if verb == "create":
                if pos:
                    return None
                checks.append(("pr", here, repo))
            else:  # edit, ready: your own open PR, named by its number
                if len(pos) != 1 or not pos[0].isdigit():
                    return None
                checks.append(("own-pr", here, repo, pos[0]))
            wanted = True
        elif prog in SAFE_READS and ws[0] == prog:
            continue
        else:
            return None
    return checks if wanted else None


def granted(checks, session):
    """Runs each check with the session's identity (run-check, git-push --check): True when all of them pass."""
    env = dict(os.environ)
    env["CLAUDE_CODE_SESSION_ID"] = session
    run_check, git_push = os.path.join(HERE, "run-check"), os.path.join(HERE, "git-push")

    def ok(argv):
        try:
            r = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.SubprocessError):
            return None
        if r.returncode != 0:
            return None
        try:
            return json.loads(r.stdout)
        except ValueError:
            return None

    for c in checks:
        if c[0] == "run":
            if not ok([run_check, "--dir", c[1], c[2]] + ([c[3]] if c[3] else [])):
                return False
        elif c[0] == "push":
            got = ok([run_check, "--dir", c[1], "L2", "push"])
            if not got or not ok([git_push, got["repo"]] + ([c[2]] if c[2] else []) + ["--dir", c[1], "--check"]):
                return False
        elif c[0] == "pr":  # gh pr create: the PR of the current branch, on the repo of the clone
            got = ok([run_check, "--dir", c[1], "L3", "open_pr"])
            if not got or (c[2] and c[2].lower() != got["repo"].lower()):
                return False
            if not ok([git_push, got["repo"], "--dir", c[1], "--check"]):
                return False
        elif c[0] == "own-pr":  # gh pr edit|ready N: your own open PR, not a fork's
            target = [c[2]] if c[2] else ["--dir", c[1]]
            if not ok([run_check] + target + ["L3", "open_pr", "--pr", c[3]]):
                return False
    return True


FORMATS = ("claude", "codex", "gemini")


def answer(fmt, decision, reason):
    """The decision in the hook protocol of each tool. Gemini has no `ask`: it denies."""
    reason = "adorno: " + reason
    if fmt == "gemini":
        return {"decision": "deny", "reason": reason}
    if fmt == "codex" and decision == "ask":
        decision = "deny"
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                                   "permissionDecisionReason": reason}}


def main():
    argv = sys.argv[1:]
    mode = next((a for a in argv if a in ("deny", "ask")), "deny")
    fmt = next((a.split("=", 1)[1] for a in argv if a.startswith("--format=")), "claude")
    if fmt not in FORMATS:
        fmt = "claude"
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    if event.get("tool_name") not in ("Bash", "run_shell_command", "shell"):
        return 0
    tool_input = event.get("tool_input") or {}
    command = tool_input.get("command")
    if isinstance(command, list):  # Codex can pass argv
        command = " ".join(shlex.quote(str(c)) for c in command)
    command = str(command or "")
    cwd = event.get("cwd") or tool_input.get("directory") or os.getcwd()
    try:
        found = check(command, cwd=cwd)
        decision, reason = (mode, MESSAGES[found]) if found else (None, None)
    except ValueError as e:
        found, decision, reason = "?", "ask", f"adorno could not read this command ({e}): check it is not a direct write"
    except Exception as e:  # a bug here must not let a write through
        found, decision, reason = "?", "ask", f"adorno's guard failed ({type(e).__name__}): check this command yourself"
    # the decision above stands; an allow can only replace it after every check passed, and a failure keeps it
    if fmt == "claude" and found in (None, "push", "gh"):
        try:
            checks = allowable(command, cwd)
            session = str(event.get("session_id") or os.environ.get("CLAUDE_CODE_SESSION_ID") or "")
            if checks is not None and granted(checks, session):
                decision, reason = "allow", "inside the open run, at its level (workflow:pr:ship)"
        except Exception:
            pass
    if decision:
        print(json.dumps(answer(fmt, decision, reason)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
