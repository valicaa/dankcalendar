#!/usr/bin/env python3
"""Keep CLAUDE.md, the project skills and tasks/lessons.md honest.

  check-docs.py                 run all checks on the repo you're in, print a report (exit 1 on errors)
  check-docs.py --ack           record that the docs were reviewed for the current change set
  check-docs.py --hook          PreToolUse hook: acts only on `git commit`; blocks on errors
                                or unreviewed doc-relevant changes, otherwise adds a reminder
  check-docs.py --session-start SessionStart hook: prints tasks/lessons.md into context

Errors (block the commit):
  - CLAUDE.md over its line budget
  - a repo path in backticks in CLAUDE.md, a skill or an agent that doesn't exist
  - a skill whose frontmatter name/description is missing or wrong, or that is missing from
    (or extra in) the CLAUDE.md skill table
  - an agent whose frontmatter name/description is missing or wrong, whose model/effort isn't
    a recognised value, or whose `skills:` list names a skill that doesn't exist
  - a `dcal-<x>` mentioned in CLAUDE.md or a skill with no matching .claude/agents/<x>.md, or
    an agent file not mentioned in .claude/skills/project-manager/SKILL.md (roster drift)
  - code changed that a doc describes (REVIEW_RULES), none of the named docs is staged, and
    no --ack for this exact change set
  - the commit's branch isn't issue-first (doesn't match feat|fix|chore/<issue-number>-<slug>)
    and isn't exempt (master, pr/*, a Claude Code worktree-agent branch (worktree-*), detached
    HEAD) — checked only for commits in this repo (same git common dir as this script's own repo)

Change set: the command isn't parsed for what it will stage (`-a`, `git add … &&`). Every
uncommitted file (staged, unstaged or untracked) counts as changed, but only a staged doc
counts as updated, so the hook may ask for a review it didn't need, never skip one it did.
A manual run credits any changed doc. --ack stores a hash of the same uncommitted set, so it
covers the next commit attempt until anything is edited, staged or unstaged.

Repo (hook): the hook's `cwd`, moved by each `cd <dir>` before `git … commit`, then by each
`git -C <dir>` before the `commit` subcommand. A `cd`/`-C` target with a shell expansion
(`$`, a backtick or `$(`) or that doesn't exist is treated as unknown, falling back to the
repo containing the hook's `cwd` rather than silently giving up. Outside a git repo, or in
one without CLAUDE.md and .claude/skills/ (e.g. a pr/* branch off upstream), the hook does
nothing. An unexpected failure on a commit is reported as context and never blocks it.

Known limits: a `cd` inside `( … )` subshells is treated as persisting past the subshell;
only the first `git commit` in a command is checked; `pushd`, `bash -c` and `--git-dir` are
not followed.
"""
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parents[2]
ROOT = SCRIPT_ROOT
CLAUDE_MD = ROOT / "CLAUDE.md"
SKILLS = ROOT / ".claude" / "skills"
AGENTS = ROOT / ".claude" / "agents"
LESSONS = ROOT / "tasks" / "lessons.md"
CLAUDE_MD_BUDGET = 120
SKILL_BUDGET = 250
AGENT_MODELS = {"sonnet", "opus", "haiku", "fable", "inherit"}
AGENT_EFFORTS = {"low", "medium", "high", "xhigh", "max"}

# Issue-first branch naming (see CLAUDE.md's Branch model). Exempt: master, pr/* (upstream-pr's
# cherry-pick branches), worktree-* (a real `isolation: worktree` agent's branch — confirmed by
# `git worktree add -b worktree-agent-abc123 <path> master` then `git worktree list` printing
# `<path>  <sha> [worktree-agent-abc123]`), detached HEAD.
BRANCH_RE = re.compile(r"^(feat|fix|chore)/\d+-")
EXEMPT_BRANCHES = {"master"}
EXEMPT_BRANCH_PREFIXES = ("pr/", "worktree-")

# changed path (regex) -> docs that describe it. A hit with none of those docs staged
# needs a review (update the doc, or --ack).
REVIEW_RULES = [
    (r"^core/internal/ipc/(registry|router|deps)\.go$", ["dcal-recipes"], "IPC method recipe"),
    (r"^core/cmd/dcal/daemon\.go$", ["CLAUDE.md", "dcal-recipes"], "architecture / Deps wiring"),
    (r"^(quickshell/Common/SettingsData\.qml|core/internal/settings/)", ["dcal-recipes"], "settings recipes"),
    (r"^core/ent/(schema|migrate)/", ["dcal-recipes", "deploy-local"], "schema and migration steps"),
    (r"^quickshell/Services/DankCalService\.qml$", ["dcal-recipes", "code-graph"], "QML client, IPC topics"),
    (r"^(Makefile|\.pre-commit-config\.yaml|core/\.golangci\.yml|core/\.pre-commit-config\.yaml|\.github/workflows/)",
     ["verify-change", "CLAUDE.md"], "build, lint and CI commands"),
    (r"^(\.graphifyignore|\.claude/tools/graph-)", ["code-graph"], "code graph usage"),
    (r"^\.claude/tools/check-docs\.py$", ["CLAUDE.md"], "doc-check rules"),
    (r"^\.claude/agents/", ["project-manager"], "agent roster (roster drift)"),
]

# Paths the docs name on purpose because they don't exist (e.g. a stale comment in the code).
KNOWN_WRONG = {"quickshell/Services/SettingsData.qml"}

# Known build/generated output dirs a doc may point into before they've been built. Not a
# general gitignore check: a broad pattern (e.g. this repo's `repo/`) would wrongly swallow
# a real, typo'd path like `core/repo/nope.go`.
KNOWN_BUILD_OUTPUTS = ("core/bin/", "core/internal/shellembed/dist/", "graphify-out/")

# `(?![-\w])` excludes `commit-tree`. The boundary chars (incl. `/`, for a path-qualified
# `/usr/bin/git commit`) are a heuristic: this can false-positive inside quoted text
# (`echo "git commit"`), which is acceptable for a hook meant to be cautious. Group `git`
# is `git` plus its global options, where a `-C <dir>` may sit.
COMMIT_RE = re.compile(
    r"""(^|[;&|(`]|\s|/)(?P<git>git(\s+(-[Cc]\s+("[^"]*"|'[^']*'|\S+)|--\S+))*)\s+commit(?![-\w])""")
SEPARATOR_CHARS = set(";&|(")


def set_root(root):
    global ROOT, CLAUDE_MD, SKILLS, AGENTS, LESSONS
    ROOT = root
    CLAUDE_MD = ROOT / "CLAUDE.md"
    SKILLS = ROOT / ".claude" / "skills"
    AGENTS = ROOT / ".claude" / "agents"
    LESSONS = ROOT / "tasks" / "lessons.md"


def use_repo(start):
    """Point the checks at the repo containing start. False if there's none, or it has no docs."""
    top = subprocess.run(["git", "-C", str(start), "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True)
    if top.returncode != 0:
        return False
    root = Path(top.stdout.strip())
    if not (root / "CLAUDE.md").is_file() or not (root / ".claude" / "skills").is_dir():
        return False
    set_root(root)
    return True


def shell_path(base, arg):
    return base / os.path.expanduser(os.path.expandvars(arg))


UNRESOLVABLE = re.compile(r"[$`]")  # a shell expansion (`$foo`, `$(…)`, backticks) we can't evaluate


def resolve_dir(where, arg):
    """A `cd`/`-C` target resolved against `where`, or None if it's a shell expansion or doesn't exist."""
    if UNRESOLVABLE.search(arg):
        return None
    candidate = shell_path(where, arg)
    return candidate if candidate.is_dir() else None


def commit_dir(cwd, command, match):
    """Where the matched `git … commit` runs: cwd, then each `cd` before it, then each `git -C`.

    A target we can't resolve (a shell expansion, or a path that doesn't exist) makes the whole
    chain unknown: rather than silently keep the last known `where` (which could be the wrong
    repo), fall back to the repo containing the hook's own `cwd`.
    """
    where = Path(cwd)
    unresolved = False
    lexer = shlex.shlex(command[:match.start("git")].replace("\n", ";"), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        before = list(lexer)
    except ValueError:  # unbalanced quotes: the match may sit inside a string; keep cwd
        before = []
    for i, tok in enumerate(before):
        starts_command = i == 0 or set(before[i - 1]) <= SEPARATOR_CHARS
        if tok != "cd" or not starts_command:
            continue
        arg = before[i + 1] if i + 1 < len(before) else "~"
        if set(arg) <= SEPARATOR_CHARS:
            arg = "~"
        if arg.startswith("-"):  # `cd -` / `cd -P dir`: rare, left unresolved
            continue
        resolved = resolve_dir(where, arg)
        if resolved is None:
            unresolved = True
            continue
        where = resolved
    opts = shlex.split(match.group("git"))
    for opt, value in zip(opts, opts[1:]):
        if opt == "-C":
            resolved = resolve_dir(where, value)
            if resolved is None:
                unresolved = True
                continue
            where = resolved
    return Path(cwd) if unresolved else where


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True).stdout


def paths(*args):
    return git(*args, "-z").decode(errors="replace").split("\0")[:-1]


def change_set():
    """(staged, changed): staged paths, and every uncommitted path (staged, unstaged, untracked)."""
    staged = paths("diff", "--cached", "--name-only", "--no-renames")
    unstaged = paths("diff", "--name-only", "--no-renames")
    untracked = paths("ls-files", "--others", "--exclude-standard")
    return sorted(staged), sorted({*staged, *unstaged, *untracked})


def untracked_digest(f):
    """An untracked file's content hash, streamed so a large file doesn't load fully into memory.

    A file we can't open (e.g. permissions) is fingerprinted as unreadable rather than crashing:
    it still changes the hash if it appears, disappears or becomes readable.
    """
    try:
        with f.open("rb") as fh:
            return hashlib.file_digest(fh, "sha256").digest()
    except OSError:
        return b"unreadable"


def fingerprint():
    """Hash of everything uncommitted, the same set change_set() calls changed."""
    h = hashlib.sha256()
    h.update(git("diff", "--cached", "--binary", "--no-ext-diff") + b"\0")
    h.update(git("diff", "--binary", "--no-ext-diff") + b"\0")
    for p in paths("ls-files", "--others", "--exclude-standard"):
        f = ROOT / p
        h.update(p.encode() + b"\0" + (untracked_digest(f) if f.is_file() else b"") + b"\0")
    return h.hexdigest()


def ack_path():
    # Per worktree (`--git-path info/…` is shared by all worktrees of a repo).
    return Path(git("rev-parse", "--absolute-git-dir").decode().strip()) / "doc-review-ack"


def is_acked():
    return ack_path().is_file() and ack_path().read_text() == fingerprint()


def doc_files():
    return [CLAUDE_MD, *sorted(SKILLS.glob("*/SKILL.md")), *sorted(AGENTS.glob("*.md"))]


def doc_name(path):
    return "CLAUDE.md" if path == "CLAUDE.md" else path.split("/")[2] if path.startswith(".claude/skills/") else None


def ignored(path):
    # Only the known build/generated outputs, not an arbitrary gitignore match: this repo's
    # `repo/` gitignore pattern would otherwise swallow a real, typo'd `core/repo/nope.go`.
    # A doc names these both as the bare dir (`core/bin`) and as paths under it.
    return any(path == out.rstrip("/") or path.startswith(out) for out in KNOWN_BUILD_OUTPUTS)


def unverifiable(path):
    # Inside an uninitialised submodule (empty dir) or behind a dangling symlink into one.
    for parent in path.parents:
        if os.path.lexists(parent):
            return parent.is_dir() and not any(parent.iterdir()) or parent.is_symlink() and not parent.exists()
    return False


def resolves(path):
    return os.path.lexists(path) or unverifiable(path) or ignored(str(path.relative_to(ROOT)))


def check_references(errors):
    # Docs also write paths relative to core/ or quickshell/ (`internal/ipc`, `Modules/`).
    bases = [ROOT, ROOT / "core", ROOT / "quickshell"]
    tops = [{p.name for p in base.iterdir()} - {".git"} if base.is_dir() else set() for base in bases]
    for doc in doc_files():
        rel = doc.relative_to(ROOT)
        for lineno, line in enumerate(doc.read_text().splitlines(), 1):
            for span in re.findall(r"`([^`]+)`", line):
                for token in span.split():
                    token = re.sub(r"^[(\"']+|^\./", "", token)
                    token = re.sub(r"(:L?\d+(-L?\d+)?)?[),.;:\"']*$", "", token).rstrip("/")
                    if not token or token in KNOWN_WRONG or re.search(r"[<>*{}$…~]|\.\.", token):
                        continue
                    candidates = [base / token for base, top in zip(bases, tops) if token.split("/")[0] in top]
                    if not candidates or any(resolves(c) for c in candidates):
                        continue
                    errors.append(f"{rel}:{lineno}: `{token}` does not exist")


def check_skills(errors, warnings):
    dirs = {d.name for d in SKILLS.iterdir() if (d / "SKILL.md").is_file()}
    table = set(re.findall(r"^\| `([a-z0-9-]+)` \|", CLAUDE_MD.read_text(), re.M))
    for name in sorted(dirs - table):
        errors.append(f"CLAUDE.md: skill `{name}` is missing from the skills table")
    for name in sorted(table - dirs):
        errors.append(f"CLAUDE.md: skills table lists `{name}`, but .claude/skills/{name}/SKILL.md doesn't exist")
    for name in sorted(dirs):
        text = (SKILLS / name / "SKILL.md").read_text()
        front = re.match(r"---\n(.*?)\n---\n", text, re.S)
        fields = dict(re.findall(r"^(\w+): *(.+)$", front.group(1), re.M)) if front else {}
        if fields.get("name") != name:
            errors.append(f".claude/skills/{name}/SKILL.md: frontmatter name must be `{name}`")
        if not fields.get("description"):
            errors.append(f".claude/skills/{name}/SKILL.md: frontmatter description is missing")
        if (n := text.count("\n")) > SKILL_BUDGET:
            warnings.append(f".claude/skills/{name}/SKILL.md is {n} lines; consider splitting (budget {SKILL_BUDGET})")


def parse_list_field(body, key):
    # A frontmatter list, either inline comma-separated (`key: a, b`) or YAML-style
    # (`key:` then indented `- a` lines). None if the key is absent.
    m = re.search(rf"^{key}:[ \t]*(.*)$", body, re.M)
    if not m:
        return None
    inline = m.group(1).strip()
    if inline:
        return [s.strip() for s in inline.split(",") if s.strip()]
    items = []
    for line in body[m.end():].splitlines():
        if not line.strip():
            continue
        item = re.match(r"^\s*-\s*(.+?)\s*$", line)
        if not item:
            break
        items.append(item.group(1))
    return items


def check_agents(errors):
    for path in sorted(AGENTS.glob("*.md")):
        name = path.stem
        text = path.read_text()
        front = re.match(r"---\n(.*?)\n---\n", text, re.S)
        body = front.group(1) if front else ""
        fields = dict(re.findall(r"^(\w+): *(.+)$", body, re.M))
        if fields.get("name") != name:
            errors.append(f".claude/agents/{path.name}: frontmatter name must be `{name}`")
        if not fields.get("description"):
            errors.append(f".claude/agents/{path.name}: frontmatter description is missing")
        if (model := fields.get("model")) and model not in AGENT_MODELS and not model.startswith("claude-"):
            errors.append(f".claude/agents/{path.name}: model `{model}` must be one of "
                          "sonnet|opus|haiku|fable|inherit or start with `claude-`")
        if (effort := fields.get("effort")) and effort not in AGENT_EFFORTS:
            errors.append(f".claude/agents/{path.name}: effort `{effort}` must be one of "
                          "low|medium|high|xhigh|max")
        for skill in parse_list_field(body, "skills") or []:
            if not (SKILLS / skill / "SKILL.md").is_file():
                errors.append(f".claude/agents/{path.name}: skill `{skill}` has no "
                              f".claude/skills/{skill}/SKILL.md")


def check_roster(errors):
    agents = {p.stem for p in AGENTS.glob("*.md")}
    skill_names = {d.name for d in SKILLS.iterdir()}  # `dcal-recipes` is a skill, not an agent
    mentioned = set()
    for doc in [CLAUDE_MD, *sorted(SKILLS.glob("*/SKILL.md"))]:
        mentioned |= set(re.findall(r"`(dcal-[a-z0-9-]+)`", doc.read_text()))
    for name in sorted(mentioned - agents - skill_names):
        errors.append(f"`{name}` is mentioned but .claude/agents/{name}.md doesn't exist")
    pm = SKILLS / "project-manager" / "SKILL.md"
    pm_text = pm.read_text() if pm.is_file() else ""  # branches from before the roster
    for name in sorted(agents):
        if not re.search(rf"\b{re.escape(name)}\b", pm_text):
            errors.append(f".claude/agents/{name}.md is not mentioned in "
                          ".claude/skills/project-manager/SKILL.md (roster drift)")


def check_budget(errors):
    n = CLAUDE_MD.read_text().count("\n")
    if n > CLAUDE_MD_BUDGET:
        errors.append(f"CLAUDE.md is {n} lines (budget {CLAUDE_MD_BUDGET}): move a procedure into a skill")


def current_branch():
    """The checked-out branch, or None for detached HEAD (e.g. a rebase or cherry-pick in progress)."""
    result = subprocess.run(["git", "symbolic-ref", "-q", "--short", "HEAD"],
                            cwd=ROOT, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def git_common_dir(path):
    """The repo's shared .git dir (same across all its worktrees), or None if `path` isn't a repo."""
    result = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=path,
                            capture_output=True, text=True)
    return (path / result.stdout.strip()).resolve() if result.returncode == 0 else None


def check_branch(errors):
    # Issue-first branch naming is this repo's own convention (see CLAUDE.md), not something to
    # impose on some other project that happens to reuse this script (or a worktree/clone of it
    # with its own CLAUDE.md + .claude/skills). Only gate commits that share this repo's .git.
    if git_common_dir(ROOT) != git_common_dir(SCRIPT_ROOT):
        return
    branch = current_branch()
    if branch is None or branch in EXEMPT_BRANCHES or branch.startswith(EXEMPT_BRANCH_PREFIXES):
        return
    if not BRANCH_RE.match(branch):
        errors.append(
            f"branch `{branch}` isn't issue-first: every change starts as a GitHub issue on "
            "valicaa/dankcalendar, and the branch is feat|fix|chore/<issue-number>-<slug>. "
            "Create it from the issue with `gh issue develop <N> -R valicaa/dankcalendar --name "
            "<prefix>/<N>-<slug> --base master --checkout`, then `git cherry-pick` your commits "
            "onto it (a plain `git branch -m` renames the branch but doesn't link it to the "
            "issue).")


def check_lessons(warnings):
    if not LESSONS.is_file():
        warnings.append("tasks/lessons.md is missing")
        return
    for lineno, line in enumerate(LESSONS.read_text().splitlines(), 1):
        if line.startswith("- ") and not re.match(r"- \d{4}-\d{2}-\d{2} — .+ → .+", line):
            warnings.append(f"tasks/lessons.md:{lineno}: not in `- YYYY-MM-DD — <what went wrong> → <rule>` form")


def reviews_needed(changed, credited):
    credited_docs = {doc_name(p) for p in credited} - {None}
    needed = []
    for pattern, docs, why in REVIEW_RULES:
        hits = [p for p in changed if re.search(pattern, p)]
        if hits and not credited_docs & set(docs):
            needed.append(f"{', '.join(hits)} changed → review {' / '.join(docs)} ({why})")
    return needed


def run_checks():
    errors, warnings = [], []
    check_budget(errors)
    check_references(errors)
    check_skills(errors, warnings)
    check_agents(errors)
    check_roster(errors)
    check_lessons(warnings)
    return errors, warnings


def report(errors, warnings, needed, acked):
    lines = [f"error: {e}" for e in errors] + [f"warning: {w}" for w in warnings]
    lines += [f"review: {r}" + (" (acked)" if acked else "") for r in needed]
    return "\n".join(lines)


def add_context(text):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": text}}))


def check_commit(cwd, command, match):
    if not use_repo(commit_dir(cwd, command, match)):
        return 0
    errors, warnings = run_checks()
    check_branch(errors)
    staged, changed = change_set()
    needed = reviews_needed(changed, credited=staged)
    acked = bool(needed) and is_acked()
    text = report(errors, warnings, needed, acked)
    if errors or (needed and not acked):
        ack = f"(cd {shlex.quote(str(ROOT))} && python3 {shlex.quote(str(Path(__file__).resolve()))} --ack)"
        tail = ("\nFix the errors." if errors else "") + (
            "\nUpdate the docs listed and stage them (an unstaged doc edit doesn't count), or if you "
            f"checked and nothing needs changing, run `{ack}` and commit again. The ack covers "
            "everything uncommitted at the time; any later edit or staging needs a new one."
            if needed and not acked else "")
        print(f"[check-docs] commit blocked:\n{text}{tail}", file=sys.stderr)
        return 2
    if any(not doc_name(p) and not p.startswith("tasks/") for p in changed):
        context = ("[check-docs] Before this commit: does CLAUDE.md or a skill describe what changed "
                   "and still say the right thing? Were you corrected, or did you catch a mistake "
                   "this session? Then add a rule to tasks/lessons.md.")
        add_context(context + ("\n" + text if text else ""))
    return 0


def hook():
    try:
        hook_input = json.load(sys.stdin)
        command = hook_input["tool_input"]["command"]
        match = COMMIT_RE.search(command)
    except Exception:  # not a Bash call we can read, so not a commit we could check
        return 0
    if not match:
        return 0
    try:
        return check_commit(hook_input.get("cwd") or os.getcwd(), command, match)
    except Exception as exc:
        add_context(f"[check-docs] internal error: {type(exc).__name__}: {exc} — docs not checked")
        return 0


def main():
    args = sys.argv[1:]
    if args == ["--session-start"]:
        if LESSONS.is_file():
            print("Lessons from past sessions (tasks/lessons.md). Apply them; add a dated rule "
                  "whenever you are corrected or catch your own mistake.\n")
            print(LESSONS.read_text())
        return 0
    if args == ["--hook"]:
        return hook()
    if args not in ([], ["--ack"]):
        sys.exit(__doc__)
    if not use_repo(Path.cwd()):
        print(f"check-docs: {Path.cwd()} is not in a git repo with CLAUDE.md and .claude/skills/",
              file=sys.stderr)
        return 1
    if args == ["--ack"]:
        ack_path().write_text(fingerprint())
        print(f"doc review recorded for everything uncommitted in {ROOT} "
              "(re-run --ack after any further edit, or after staging or unstaging anything)")
        return 0
    errors, warnings = run_checks()
    check_branch(errors)
    _, changed = change_set()
    needed = reviews_needed(changed, credited=changed)
    print(report(errors, warnings, needed, bool(needed) and is_acked()) or "docs OK")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
